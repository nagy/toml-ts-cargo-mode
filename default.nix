{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
  emacs31 ? pkgs.emacs31,
  emacsPackages ? emacs31.pkgs,
  melpaBuild ? emacsPackages.melpaBuild,
}:

let
  emacsWithGrammars = emacs31.pkgs.withPackages (epkgs: [ epkgs.treesit-grammars.with-all-grammars ]);
in
melpaBuild (finalAttrs: {
  pname = "toml-ts-cargo-mode";
  version = "0.1.0";
  src = lib.cleanSource ./.;

  emacs = emacsWithGrammars;

  turnCompilationWarningToError = true;

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
      files.  Dependency keys inside dependency tables are underlined,
      thing-at-point returns their crates.io URLs, and RET opens them
      in a browser.
    '';
    license = lib.licenses.agpl3Plus;
    homepage = "https://github.com/nagy/toml-ts-cargo-mode";
    maintainers = with lib.maintainers; [ nagy ];
    platforms = lib.platforms.unix;
  };
})
