# toml-ts-cargo-mode — Architecture

A minor mode for `toml-ts-mode` that adds Cargo.toml-specific smarts.

## Core design: single predicate, two consumers

`toml-ts-cargo--crate-key-p` is the sole truth of "is this a crate key?". It:

1. Walks from the key node up to its `pair` parent
2. Walks up to the `table` / `table_array_element`
3. Reads the table header (using `toml-ts-cargo--key-text` for bare/quoted/dotted)
4. Checks if the header names a toplevel dep table via `toml-ts-cargo--dep-table-header-p`

This predicate is consumed by:

- **URL provider** (`toml-ts-cargo--url-provider`): registered in `thing-at-point-provider-alist`, walks from `treesit-node-at (point)` up to the containing pair's key.
- **Font-lock** (`toml-ts-cargo--fontify-crate-key`): a function capture in tree-sitter font-lock rules, called for every `(pair (bare_key|quoted_key|dotted_key))` inside `table` and `table_array_element` nodes. Uses `treesit-fontify-with-override`.

## Activation

- `toml-ts-cargo-mode` is a `define-minor-mode`
- `toml-ts-cargo-maybe-enable` is a nil-safe autoloaded hook function
- Enable: registers URL provider (guards against double-registration), adds font-lock rules via `treesit-add-font-lock-rules`
- Disable: removes only its own URL provider entry (not other packages'), removes `cargo-dependency` settings via `treesit-font-lock-setting-feature`

## Table header classification

`toml-ts-cargo--dep-table-header-p` returns:
- `top`: last component is a dep-table name and second-to-last is NOT (e.g. `dependencies`, `workspace.dependencies`, `target.X.dependencies`)
- `sub`: last component is NOT a dep name but second-to-last IS (e.g. `dependencies.serde`)
- `nil`: nothing matches

## Key text utilities

- `toml-ts-cargo--strip-quotes`: strips surrounding quotes from string keys
- `toml-ts-cargo--key-text`: recursive key text for bare_key, quoted_key, dotted_key nodes (uses named children only, skipping anonymous `.` nodes)

## TODO

- [ ] `foo = { package = "bar" }` should resolve to `bar` not `foo` (renamed dependencies)
- [ ] `[dependencies.SERDE]` headers should be underlined as crate references
- [ ] Font-lock face assertion in batch tests is fragile; function capture with `:override t` in `treesit-add-font-lock-rules` appears to clobber non-matching keys during batch test runs. Predicate logic verified via direct `crate-key-p` test.
