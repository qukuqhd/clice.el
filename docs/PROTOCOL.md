# clice client protocol

Everything here is from clice's `src/server/extension.cppm` and the VS Code
extension (`editors/vscode/src/feature/`).  These are clice-specific methods on
top of LSP; they do not appear in `initialize` capabilities.

## Client capabilities

```json
{
  "capabilities": {
    "experimental": { "restartServer": true }
  }
}
```

When `restartServer` is true, clice sends `clice/restartServer` (a request)
instead of a "restart to apply" diagnostic.  In Emacs, `:restartServer` is
the plist key that serialises to `restartServer`.

## Requests (client → server)

| Method | Params | Result |
|---|---|---|
| `clice/queryContext` | `{uri, offset?}` | `{contexts: [ContextItem], total, epoch}` |
| `clice/currentContext` | `{uri}` | `{context?, automatic, inactiveChoice?, command?, epoch, otherContexts}` |
| `clice/switchContext` | `{uri, contextUri, occurrence?, commandHash?, epoch?}` | `{success, stale}` |
| `clice/resetContext` | `{uri}` | `{success, stale}` |
| `clice/showOtherContexts` | `{uri, show}` | `{success, stale}` |
| `clice/listConfigurations` | `{uri?}` | `{configurations, active, build?, selected, defaultConfiguration}` |
| `clice/switchConfiguration` | `{name, uri?}` | `{success, reason?}` |
| `clice/counterparts` | `{uri}` | `{candidates: [{uri, reasons}], preferred?}` |

### ContextItem

| Field | Meaning |
|---|---|
| `label` | shown in the context menu |
| `description` | path or build configuration |
| `uri` | host source file (header contexts) or the file itself |
| `occurrence?` | which `#include` site, when a header is entered more than once |
| `commandHash?` | identifies a compilation-database entry for multiply-compiled sources |

`epoch` in `queryContext` and `currentContext` is the workspace generation the
listing was computed against.  Pass it back to `switchContext`; if the
workspace changed meanwhile the server answers `stale: true` and the client
must re-query and retry.

### CompileCommand

| Field | Meaning |
|---|---|
| `source` | `database`, `host`, `default`, `borrowed` or `fallback` |
| `from?` | the file whose command it borrows |
| `directory` | working directory |
| `arguments` | compiler arguments |
| `queryFailure?` | why the compiler could not be queried |

`currentContext` returns it only for an open document.

## Server → client request

| Method | Params | Meaning |
|---|---|---|
| `clice/restartServer` | `{reason}` | what was started on changed (settings file, build configuration); restart the server |

## CLI

`clice` also exposes project-wide operations outside LSP:

```
clice analyze | command | format | index | inspect | lint | modularize |
      query | refactor | scan | serve
```

`lint`, `index`, `scan` and `query` accept `--json`; `format` has `--check`.
Workspace discovery: nearest directory at or above the current one containing
`clice.toml` or `compile_commands.json` (or `build/` for the former).
