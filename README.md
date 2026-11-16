# clice.el

Eglot support for [clice](https://github.com/clice-io/clice), the LLVM/Clang
based C/C++ language server.

`clice` speaks standard LSP for the usual editor features.  Eglot already
covers most of it; this package supplies what Eglot does not, and implements
clice's own protocol extensions (compilation contexts, build configurations,
header/source counterparts, restart-on-config-change).

## Status

Early scaffold.  Implemented and tested:

- registers `clice serve` with Eglot, with clice's language ids
  (`c`, `cpp`, `objective-c`, `objective-c++`, `cuda-cpp`, `hip`, `opencl`);
- advertises the client capabilities clice looks for: `documentLink`,
  `foldingRange`, `selectionRange`, and `experimental.restart_server`;
- answers `clice/restartServer` by reconnecting Eglot, so switching a build
  configuration or saving `clice.toml` applies without manual restarts.

Planned (see `docs/DESIGN.md`):

| Module | Feature |
|---|---|
| `clice-context` | switch compilation context, build configuration, header/source counterparts, show compile command, mode-line context |
| `clice-links` | `#include` document links |
| `clice-fold` | folding from `textDocument/foldingRange` |
| `clice-select` | syntax selection ranges |
| `clice-semantic` | clice's richer semantic-token legend, including `inactive` dimming |
| `clice-cli` | wrappers for `clice lint/format/index/query/scan` |
| `clice-toml` | `clice.toml` helpers |

## Requirements

- Emacs 30.1 or later (31.1 recommended: semantic tokens, inlay hints and
  pull diagnostics are used when available)
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

No Eglot changes are needed.  The package adds a mode-specific
`eglot-server-programs` entry (with `:language-id`), so clangd is not started
for C/C++ buffers.

## Commands

| Command | Description |
|---|---|
| `clice-mode` | global minor mode: install/remove the integration |
| `clice-setup`, `clice-unsetup` | programmatic install/remove |
| `clice-restart-server` | restart the clice server of the current buffer |
| `clice-version` | print `clice --version` output |

## Development

```sh
make compile   # byte-compile
make test      # ERT unit tests (no server needed)
```

Integration tests against a real clice will live in `test/integration/` and are
skipped when the executable is absent.

## License

GPL-3.0-or-later.  See `LICENSE`.
