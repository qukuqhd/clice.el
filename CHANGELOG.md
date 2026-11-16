# Changelog

## 0.1.0 (2026-11-16)

Initial release.

- Register `clice serve` with Eglot, with clice's language ids.
- Advertise `documentLink`, `foldingRange`, `selectionRange` and
  `experimental.restartServer`; reconnect on `clice/restartServer`.
- Compilation contexts: list, switch, reset, show/hide other contexts,
  mode-line indicator.
- Build configurations: list and switch, restarting the server.
- Header/source counterparts and the compile command.
- Document links, folding ranges and selection ranges (the features Eglot
  does not implement).
- clice semantic-token legend, including `inactive` dimming, plus automatic
  semantic tokens and inlay hints.
- CLI wrappers for `lint`, `format --check`, `index`, `scan` and `query`.
- `clice.toml` helpers.
- Unit tests and integration tests against a real clice server.
