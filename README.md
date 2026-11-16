# clice.el

Eglot support for [clice](https://github.com/clice-io/clice), the LLVM/Clang
based C/C++ language server.

Eglot already covers the standard LSP surface.  This package supplies what
Eglot does not, and implements clice's own protocol extensions:

- **compilation contexts** — headers compiled under different hosts, sources
  compiled with different database entries;
- **build configurations** — `clice.toml` rules tags, with automatic server
  restart when the selection changes;
- **header/source counterparts** — jump between a header and its sources or a
  module interface and its implementation;
- **compile command** — show the command clice compiles the file with;
- **document links** — clickable `#include` targets;
- **folding** — clang-accurate folding ranges from the server;
- **selection ranges** — syntax-aware expand/contract;
- **semantic tokens** — clice's richer legend, including the `inactive`
  modifier that dims code belonging to other contexts;
- **CLI wrappers** — `lint`, `format --check`, `index`, `scan`, `query`;
- **`clice.toml` helpers**.

## Requirements

- Emacs 30.1 or later (31.1 recommended: semantic tokens, inlay hints and
  pull diagnostics)
- `clice` on `PATH` (or set `clice-executable`)

## Install

```elisp
(add-to-list 'load-path "~/path/to/clice.el")

(require 'clice)
(clice-mode 1)
```

With `use-package`:

```elisp
(use-package clice
  :load-path "~/path/to/clice.el"
  :config
  (clice-mode 1))
```

No Eglot changes are needed: the package registers its own
`eglot-server-programs` entry (with clice's language ids), so clangd is not
started for C/C++ buffers.

## Commands

| Command | Description |
|---|---|
| `clice-mode` | global minor mode: install/remove the integration |
| `clice-switch-context` | choose the compilation context of the file |
| `clice-reset-context` | back to the automatic context |
| `clice-toggle-other-contexts` | show/dim code from the other contexts |
| `clice-switch-configuration` | choose a build configuration (restarts) |
| `clice-switch-counterparts` | header ↔ source, interface ↔ implementation |
| `clice-show-compile-command` | show the file's complete compile command |
| `clice-restart-server` | restart the clice server |
| `clice-expand-region` / `clice-contract-region` | syntax selection ranges |
| `clice-toggle-fold` / `clice-fold-all` / `clice-unfold-all` | folding |
| `clice-open-project-config` | open (or create) `clice.toml` |
| `clice-insert-schema-comment` | add the `#:schema` line to `clice.toml` |
| `clice-lint`, `clice-format-check`, `clice-index`, `clice-scan` | CLI tools |
| `clice-scan-json`, `clice-lint-json` | JSON reports in a buffer |
| `clice-query` | run a `clice query` subcommand |
| `clice-cli-menu` | dispatch to the CLI tools |

Buffer-local minor modes (enabled automatically in clice buffers; each has a
`defcustom` to opt out):

| Mode | Effect |
|---|---|
| `clice-links-mode` | render document links as clickable overlays |
| `clice-fold-mode` | fold using `textDocument/foldingRange`; disables `hs-minor-mode` in the buffer |

Semantic tokens and inlay hints are turned on automatically; see
`clice-enable-semantic-tokens` and `clice-enable-inlay-hints`.

### Suggested keybindings

The package does not bind keys globally.  For example:

```elisp
(with-eval-after-load 'clice
  (keymap-set eglot-mode-map "C-c c" clice-command-map))

(with-eval-after-load 'clice
  (define-key clice-fold-mode-map (kbd "TAB") #'clice-toggle-fold)
  (with-eval-after-load 'c++-ts-mode
    (keymap-set c++-ts-mode-map "C-=" #'clice-expand-region)))
```

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `clice-executable` | `"clice"` | executable name or path |
| `clice-server-args` | `'("serve")` | server arguments |
| `clice-auto-restart` | `t` | reconnect when clice asks for a restart |
| `clice-auto-enable-links` | `t` | enable `clice-links-mode` in clice buffers |
| `clice-auto-enable-fold` | `t` | enable `clice-fold-mode` in clice buffers |
| `clice-enable-semantic-tokens` | `t` | enable `eglot-semantic-tokens-mode` |
| `clice-enable-inlay-hints` | `t` | enable `eglot-inlay-hints-mode` |
| `clice-context-mode-line` | `t` | show the active context in the mode line |
| `clice-context-refresh-on-save` | `t` | refresh the context after saving |
| `clice-links-auto-refresh` | `t` | refresh links after edits |
| `clice-fold-auto-refresh` | `t` | refresh folds after edits |
| `clice-cli-jobs` | `nil` | `--jobs` value for CLI commands |

## How it works

- `clice.el` registers the server and injects the client capabilities clice
  looks for: `documentLink`, `foldingRange`, `selectionRange`, and
  `experimental.restartServer`.
- `clice-protocol.el` wraps the custom `clice/*` requests (see
  `docs/PROTOCOL.md`).
- `clice/restartServer` is answered by reconnecting Eglot, so saving
  `clice.toml` or switching a build configuration applies immediately.
- The three features Eglot lacks are implemented in this package with plain
  overlays/text properties; `docs/DESIGN.md` records the research and the
  design.

## Limitations

- Eglot runs one server per project root; clice's multi-root workspaces are
  not mapped to multiple Eglot servers.
- `clice/counterparts` needs a built index (`clice index` or the server's
  background indexing); until then it may return no candidates.
- Diagnostics do not yet show `codeDescription` links (Eglot does not
  advertise that capability).
- The CLI commands and the running server share clice's cache; avoid a long
  `clice index` while the server is compiling heavily.

## Development and testing

```sh
make compile           # byte-compile
make lint              # checkdoc
make test              # 26 unit tests (no server needed)
make test-integration  # 10 end-to-end tests, needs clice on PATH
```

Integration tests copy fixture projects from `test/fixtures/`, write a
compilation database and start a real `clice serve` through Eglot.  They
are skipped when `clice` is not installed; the modules test also needs
`clang++`.  See `docs/TESTING.md` for the coverage matrix and known gaps.

## License

GPL-3.0-or-later.  See `LICENSE`.
