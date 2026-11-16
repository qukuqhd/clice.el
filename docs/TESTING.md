# Testing

The integration suite starts a real `clice serve` through Eglot for each
test.  A fixture project is copied to a temporary directory, a
`compile_commands.json` is written for it, and the assertions exercise both
clice's responses and the package's own UI.

```sh
make test              # 26 unit tests, no server or clice needed
make test-integration  # 10 end-to-end tests, needs clice on PATH
```

The suite was run against clice 0.1.0 (distribution package) and the
official 1.0.0 release.  Tests are skipped when `clice` is missing; the
modules test also needs `clang++`.

## Coverage

| clice feature | Test | Fixture |
|---|---|---|
| server detection, capabilities, client capability injection | `connect-and-capabilities` | basics |
| code completion | `completion-hover-signature-navigation`, `modules` | basics, modules |
| hover | `completion-hover-signature-navigation`, `modules`, `forced-include` | basics, modules, forced_include |
| signature help | `completion-hover-signature-navigation` | basics |
| definition / references / implementation | `completion-hover-signature-navigation` | basics |
| document highlight | `completion-hover-signature-navigation` | basics |
| workspace symbols | `completion-hover-signature-navigation` | basics |
| call hierarchy (prepare + incoming calls) | `completion-hover-signature-navigation` | basics |
| type hierarchy (prepare + supertypes) | `completion-hover-signature-navigation` | basics |
| rename | `rename-symbols-diagnostics-actions` | basics |
| document symbols (hierarchical) | `rename-symbols-diagnostics-actions` | basics |
| diagnostics (pull) | `rename-symbols-diagnostics-actions`, `forced-include` | basics, forced_include |
| code actions (quickfix: add include) | `rename-symbols-diagnostics-actions` | basics |
| semantic tokens | `semantic-inlay-formatting` | basics |
| semantic tokens: `inactive` modifier | `contexts-and-inactive` | contexts |
| inlay hints | `semantic-inlay-formatting` | basics |
| formatting (document and range) | `semantic-inlay-formatting` | basics |
| document links (`#include`, `__has_include`) | `links-fold-selection` | basics |
| folding ranges | `links-fold-selection` | basics |
| selection ranges (expand/contract) | `links-fold-selection` | basics |
| compilation contexts (list/switch/reset) | `contexts-and-inactive` | contexts |
| other-context code (`showOtherContexts`) | `contexts-and-inactive` | contexts |
| header/source counterparts | `contexts-and-inactive` | contexts |
| compile command | `contexts-and-inactive` | contexts |
| build configurations + restart request | `build-configurations` | configs |
| C++20 modules | `modules` | modules |
| forced includes (`-include`) | `forced-include` | forced_include |
| CLI: `scan`, `lint`, `query` | `cli-tools` | basics |
| `clice index` (needed by counterparts/query) | `contexts-and-inactive`, `cli-tools`, `completion-hover-signature-navigation` | contexts, basics |

## Not covered

These need toolchains or setups that are not portable enough for this
suite:

- Objective-C/C++, CUDA, HIP and OpenCL language support;
- precompiled headers and multi-configuration databases beyond the simple
  `configs` fixture;
- non-UTF-8 and CRLF files;
- `#include_next` and `#embed` document links;
- semantic-token deltas, inlay-hint tooltips, call-hierarchy outgoing calls,
  type-hierarchy subtypes;
- refactor code-action kinds other than the quickfix tested here;
- multi-root workspaces (Eglot itself runs one server per project root).

## Writing a test

```elisp
(let* ((dir (clice-test--project "basics" '("src/main.cpp" "src/shapes.cpp")))
       (file (expand-file-name "src/main.cpp" dir))
       (server nil))
  (unwind-protect
      (progn
        (setq server (clice-test--connect file))
        (should (clice-current-server)))
    (clice-test--cleanup server dir)))
```

`clice-test--database` accepts `(RELATIVE . PLIST)` entries with
`:arguments` (the file is appended) or `:command`; `${ROOT}` and `${FILE}`
are substituted.  Fixtures live in `test/fixtures/<name>`.
