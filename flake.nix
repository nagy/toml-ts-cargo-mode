{
  description = "Cargo.toml extras for toml-ts-mode (Emacs package)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    # One formatter entry point: `nix fmt' formats every tracked file, and
    # the module adds the `checks.treefmt' gate.
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      flake-parts,
      treefmt-nix,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ treefmt-nix.flakeModule ];

      # Pure Elisp: no ELF binaries, so evaluate on every Linux arch.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      perSystem =
        {
          pkgs,
          lib,
          config,
          ...
        }:
        let
          # The tests need tree-sitter grammars loaded at runtime, which the
          # bare `emacs` from nixpkgs does not provide; wrap it. Used both as
          # the build's Emacs and to run the ERT suite in checkPhase.
          # One grammar is all this package needs; `with-all-grammars` would
          # link ~477 parsers (~1.3 GiB) to get it.
          grammar = pkgs.emacs31.pkgs.treesit-grammars.with-grammars (grammars: [
            grammars.tree-sitter-toml
          ]);
          emacsWithGrammars = pkgs.emacs31.pkgs.withPackages (_: [ grammar ]);

          # Nix rejects versions Nixpkgs cannot parse. Convention for
          # unreleased packages: <upstream-version>-unstable-<YYYY-MM-DD>,
          # where the upstream version is the file header's `Version:` and
          # the date is the last commit touching the source. Fall back to the
          # epoch when the source is not a git checkout.
          version =
            let
              d = self.lastModifiedDate or "19700101000000";
            in
            "0.2.0-unstable-${builtins.substring 0 4 d}-${builtins.substring 4 2 d}-${builtins.substring 6 2 d}";
        in
        {
          # Overridable, so a consumer can swap the grammar-carrying Emacs:
          #   inputs.toml-ts-cargo-mode.packages.${system}.toml-ts-cargo-mode.override
          #   { emacs = pkgs.emacs31-nox; }
          packages.toml-ts-cargo-mode = lib.makeOverridable (
            {
              # `melpaBuild' closes over the Emacs of its package set, so the
              # grammar has to arrive through this argument.
              emacs ? emacsWithGrammars,
              emacsPackages ? pkgs.emacsPackagesFor emacs,
              melpaBuild ? emacsPackages.melpaBuild,
              # The flake passes this, so a plain import stays explicit.
              version,
            }:
            melpaBuild {
              pname = "toml-ts-cargo-mode";
              preferLocalBuild = true;
              inherit version;

              # Only git-tracked files enter a flake build; cleanSource also
              # drops VCS dirs and byte-compiled .eln caches.
              src = lib.cleanSource ./.;

              # melpaBuild byte-compiles against this Emacs rather than the
              # default one, so the tree-sitter grammars are available.
              emacs = emacsWithGrammars;

              # Byte-compilation warnings fail the build. Keep it on: it is
              # the cheapest lint the package will ever get.
              turnCompilationWarningToError = true;

              # The suite drives real toml-ts-mode buffers, so it must run
              # inside the same grammar-equipped Emacs used to build.
              nativeBuildInputs = [
                # Gives Emacs a writable HOME, so the builder needs no
                # `export HOME=$TMPDIR' line and no two checks share a home
                # directory.
                pkgs.writableTmpDirAsHomeHook
              ];

              checkPhase = ''
                runHook preCheck
                # `melpaBuild' stages only the files matched by its `files'
                # spec, so the test tree has to be copied back before the glob
                # below can see it.
                cp -r ${./test} ./test
                # printf repeats "-l %s" per match.  failglob makes an empty
                # glob a shell error, so the || guard fires even without
                # `set -e'.  Restore the default right after: later commands
                # must keep default glob semantics.  The unquoted $test_args is
                # intentional: the words must split into -l <file> pairs, which
                # is safe because test file names never contain spaces.
                shopt -s failglob
                test_args=$(printf -- "-l %s " test/*-test.el) || { echo 'no tests matched test/*-test.el' >&2; exit 1; }
                shopt -u failglob
                ${emacsWithGrammars}/bin/emacs --batch -L . -L test \
                  $test_args \
                  -f ert-run-tests-batch-and-exit
                runHook postCheck
              '';

              doCheck = true;

              meta = {
                description = "Cargo.toml extras for toml-ts-mode";
                longDescription = ''
                  A minor mode that enhances toml-ts-mode buffers for Cargo.toml
                  files.  Dependency keys inside dependency tables are
                  underlined and thing-at-point returns their crates.io URLs.
                '';
                # Read from the file header, which declares AGPL-3.0-or-later.
                license = lib.licenses.agpl3Plus;
                homepage = "https://github.com/nagy/toml-ts-cargo-mode";
                maintainers = with lib.maintainers; [ nagy ];
                platforms = lib.platforms.unix;
              };
            }
          ) { inherit version; };

          packages.default = config.packages.toml-ts-cargo-mode;

          # The package byte-compiles with warnings as errors and runs ERT in
          # checkPhase, so building it is the gate; no second build.
          checks.default = config.packages.toml-ts-cargo-mode;

          # package-lint and checkdoc cover what byte-compilation cannot.
          # Both lint the test tree too, so tests keep the same header,
          # docstring and prefix rules as the code under test.
          checks.lint =
            pkgs.runCommand "toml-ts-cargo-mode-lint"
              {
                nativeBuildInputs = [
                  # Emacs carries package-lint; the same major version the
                  # package builds against keeps the built-in package list
                  # (toml-ts-mode, treesit) in sync with the build.
                  (pkgs.emacs31.pkgs.withPackages (epkgs: [ epkgs.package-lint ]))
                  # Gives Emacs a writable HOME, so the builder needs no
                  # `export HOME=$TMPDIR' line and no two checks share a home
                  # directory.
                  pkgs.writableTmpDirAsHomeHook
                ];
                # `src' is pre-filtered and melpaBuild staged only root files,
                # so copy the whole tree and lint it from there.
                src = config.packages.toml-ts-cargo-mode.src;
              }
              ''
                cp -r "$src"/. .
                emacs --batch -l package-lint \
                  --eval '(setq package-lint-main-file "toml-ts-cargo-mode.el")' \
                  --eval '(setq package-lint--sane-prefixes (concat package-lint--sane-prefixes "\\|toml-ts-cargo"))' \
                  -f package-lint-batch-and-exit \
                  *.el test/*.el
                # checkdoc exits 0 on findings, so gate on non-empty output.
                lint_log=$(emacs --batch -l checkdoc \
                  --eval '(setq checkdoc-arguments-in-order-flag t)' \
                  --eval '(mapc (lambda (f) (checkdoc-file f)) command-line-args-left)' \
                  *.el test/*.el 2>&1)
                if [ -n "$lint_log" ]; then printf '%s\n' "$lint_log"; exit 1; fi
                touch $out
              '';

          # treefmt-nix has no Elisp formatter, so this formats the flake
          # itself.
          treefmt = {
            projectRootFile = "flake.nix";
            programs.nixfmt.enable = true;
          };

          devShells.default = pkgs.mkShell {
            # A grammar-equipped Emacs plus tree-sitter tooling, so the ERT
            # suite can be run interactively the same way the check does,
            # and the treefmt wrapper for `nix fmt'.
            packages = [
              emacsWithGrammars
              pkgs.tree-sitter
              config.treefmt.build.wrapper
            ];
          };
        };
    };
}
