# AGENTS.md — toml-ts-cargo-mode

## Purpose

`toml-ts-cargo-mode`: Emacs minor mode for `toml-ts-mode` that adds
Cargo.toml-specific smarts. It links crate names in dependency tables and
provides a `thing-at-point` URL for them. Emacs 31 or newer, because
`toml-ts-mode` needs it. License: AGPL-3.0-or-later.

## Layout

| File | Ownership |
|---|---|
| `toml-ts-cargo-mode.el` | The mode: predicate, URL provider, font-lock, activation. |
| `test/toml-ts-cargo-mode-test.el` | ERT suite, regression tests for the region-clobber bug. |
| `test/toml-ts-cargo-mode-test-helper.el` | Shared ERT fixtures and stubs. |
| `flake.nix` | `melpaBuild` package, grammar-wrapped Emacs, checkPhase, lint check, devShell. |

## Build and test

- `nix flake check` — the package (byte-compile plus the ERT suite in `checkPhase`)
  and the `lint` check.
- `nix build` — the package.
- `nix develop` — dev shell. `default.nix` and `shell.nix` do not ship.
- `nixfmt flake.nix` — the flake is nixfmt-formatted. No treefmt formatter ships, so
  `nix fmt` is unavailable.

## Architecture

### Single predicate, two consumers

`toml-ts-cargo--crate-key-p` holds the sole truth of "this is a crate key". It
walks from the key node up to its `pair` parent, walks up to the
`table`/`table_array_element`, reads the table header through
`toml-ts-cargo--key-text` for bare, quoted and dotted keys, and checks whether the
header names a toplevel dep table through `toml-ts-cargo--dep-table-header-p`.

Two consumers use it:

- **URL provider** (`toml-ts-cargo--url-provider`), registered in
  `thing-at-point-provider-alist`. It walks from `treesit-node-at (point)` up to
  the containing pair key.
- **Font-lock** (`toml-ts-cargo--fontify-crate-key`), a function capture in
  tree-sitter font-lock rules, called for every
  `(pair (bare_key|quoted_key|dotted_key))` inside `table` and
  `table_array_element` nodes.

### Table header classification

`toml-ts-cargo--dep-table-header-p` returns:

- `top`: the last component names a dep table and the second-to-last does not,
  for example `dependencies`, `workspace.dependencies`,
  `target.X.dependencies`.
- `sub`: the last component does not name a dep, but the second-to-last does, for
  example `dependencies.serde`.
- `nil`: nothing matches.

### Key text utilities

`toml-ts-cargo--strip-quotes` strips surrounding quotes from string keys.
`toml-ts-cargo--key-text` returns recursive key text for `bare_key`,
`quoted_key` and `dotted_key` nodes, using named children only and skipping
anonymous `.` nodes.

### Activation

`toml-ts-cargo-mode` is a `define-minor-mode` and `toml-ts-cargo-maybe-enable`
is a nil-safe autoloaded hook function. Enable registers the URL provider, with a
guard against double registration, and adds font-lock rules through
`treesit-add-font-lock-rules`. Disable removes only its own URL provider entry,
never another package's entry, and removes the `cargo-dependency` settings through
`treesit-font-lock-setting-feature`.

### Tests

Tests live in `test/` (singular), one file per source unit, named
`<unit>-test.el`. Shared fixtures go in `toml-ts-cargo-mode-test-helper.el`,
which must not match `*-test.el` so the glob loader keeps treating it as a
helper. `checkPhase` loads `test/*-test.el` by glob, guarded by `failglob` and an
`exit 1`, so a new test file needs no flake edit but must be `git add`ed.
`checks.lint` runs package-lint and checkdoc over `*.el test/*.el`, with
`package-lint-main-file` set so each test file is not linted as its own package.

## Rules

- Pass the node's own start and end as the face bounds in
  `toml-ts-cargo--fontify-crate-key`. Do not pass the fontify-region `start` and
  `end` arguments.
- Pass the region bounds through as `bound-start` and `bound-end`, so the
  byte-compiler sees `start` and `end` as used.
  `turnCompilationWarningToError` treats an unused-argument warning as an error.
- Keep the two regression tests.
  `toml-ts-cargo-fontify-only-captured-node` calls the fontifier directly with
  the whole buffer as region bounds and asserts that only the node gets painted.
  `toml-ts-cargo-font-lock-region-bounds` runs a full `font-lock-ensure` pass and
  asserts that the cargo face appears on exactly the crate keys, including no
  `[dependencies.serde]` sub-table keys.
- Build the package with `emacsWithGrammars`. The ERT suite needs a real
  `toml-ts-mode`.
- Do not hand-bump `version`. The flake passes `self` into `outputs` and derives
  `0-unstable-YYYY-MM-DD` from the source tree date, with an epoch fallback for
  non-git sources.
- `git add` a new `*.el` file. Flake sources are git-tracked files only.
- Keep `Package-Requires` in step with the code. `checks.lint` fails when a
  builtin function lands in a newer Emacs than the header declares, as
  `treesit-font-lock-setting-feature` did for `emacs` `31.1`.

## Conventions

- Prefix internals with `toml-ts-cargo--`.
- Name the font-lock feature `cargo-dependency`.
- Name tests `toml-ts-cargo-<behaviour>`.

## Open work

- `foo = { package = "bar" }` should resolve to `bar`, not `foo`, for a renamed
  dependency.
- A `[dependencies.SERDE]` header should underline as a crate reference.
