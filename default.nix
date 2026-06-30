{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
  emacs ? pkgs.emacs,
  emacsPackages ? emacs.pkgs,
  melpaBuild ? emacsPackages.melpaBuild,
}:

melpaBuild {
  pname = "toml-ts-cargo-mode";
  version = "0.1.0";
  src = lib.cleanSource ./.;

  emacs = emacs.pkgs.withPackages
    (epkgs: [ epkgs.treesit-grammars.with-all-grammars ]);

  turnCompilationWarningToError = true;

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
}
