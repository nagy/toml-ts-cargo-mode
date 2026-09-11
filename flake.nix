{
  description = "Cargo.toml extras for toml-ts-mode (Emacs package)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
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
          emacsWithGrammars = pkgs.emacs31.pkgs.withPackages (
            epkgs: [ epkgs.treesit-grammars.with-all-grammars ]
          );
        in
        {
          packages.toml-ts-cargo-mode = pkgs.emacsPackages.melpaBuild (finalAttrs: {
            pname = "toml-ts-cargo-mode";
            # Nix rejects versions Nixpkgs cannot parse. The package is
            # unreleased, so follow the house convention for that case.
            version = "0.2.0-unstable-2026-08-10";

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
            checkPhase = ''
              runHook preCheck
              ${emacsWithGrammars}/bin/emacs --batch -L . \
                -l toml-ts-cargo-mode-tests.el \
                -f ert-run-tests-batch-and-exit
              runHook postCheck
            '';

            doCheck = true;

            meta = {
              description = "Cargo.toml extras for toml-ts-mode";
              longDescription = ''
                A minor mode that enhances toml-ts-mode buffers for Cargo.toml
                files.  Dependency keys inside dependency tables are
                underlined, thing-at-point returns their crates.io URLs, and
                RET opens them in a browser.
              '';
              # Read from the file header, which declares AGPL-3.0-or-later.
              license = lib.licenses.agpl3Plus;
              homepage = "https://github.com/nagy/toml-ts-cargo-mode";
              maintainers = with lib.maintainers; [ nagy ];
              platforms = lib.platforms.unix;
            };
          });

          packages.default = config.packages.toml-ts-cargo-mode;

          devShells.default = pkgs.mkShell {
            # A grammar-equipped Emacs plus tree-sitter tooling, so the ERT
            # suite can be run interactively the same way the check does.
            packages = [
              emacsWithGrammars
              pkgs.tree-sitter
            ];
          };
        };
    };
}
