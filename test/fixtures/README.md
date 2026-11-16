# Fixtures

Each directory is copied into a temporary git project by
`clice-test--project`; the compilation database is generated at test time
(see `docs/TESTING.md`).

| Fixture | Purpose |
|---|---|
| `basics` | headers, classes, functions, a broken file (`diagnostics.cpp`), a missing include (`code_action.cpp`) and a badly formatted file (`format.cpp`) |
| `contexts` | a header compiled under two hosts with different macros; used for contexts, `inactive` tokens, counterparts and compile commands |
| `configs` | `clice.toml` with `debug` and `release` build configurations |
| `modules` | a C++20 module interface (`math.ixx`) imported by `main.cpp` |
| `forced_include` | a macro provided through the command's `-include` |
