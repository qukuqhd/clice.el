# clice.el 设计说明

## 目标

在**不修改 eglot** 的前提下，让 Emacs 对 clice 的能力覆盖接近官方 VS Code
扩展：

- 标准 LSP：交给 eglot；
- eglot 缺的 3 个通用能力（documentLink / foldingRange / selectionRange）：包内实现；
- clice 自定义协议（contexts / configurations / counterparts / restart）：包内实现；
- CLI 工具与 `clice.toml`：可选封装。

## 调研结论（2026-11）

### Emacs / eglot

- 本机 Emacs 31.1，eglot 内置。
- eglot 已有：补全、悬停、签名、导航、引用、重命名、pull 诊断、代码操作、
  格式化、语义 Token、内联提示、调用/类型层次、进度、文件监听、position
  encoding 协商。
- eglot 缺：`foldingRange`、`selectionRange`、`documentLink`（仅出现在
  `eglot-ignored-server-capabilities`，无实现）。
- eglot master（1.26）仍无这三项；上游没有相关 issue/PR。
- MELPA 上没有能填补这些空白的包（eglot-x/eglotx 解决的是别的問題）。

### clice

- 标准 LSP 能力齐全，额外支持 pull 诊断、语义 Token delta、内联提示。
- 自定义方法见 `PROTOCOL.md`；`clice/restartServer` 只有在客户端声明
  `capabilities.experimental.restart_server = true` 时才发送。
- "其他编译上下文变暗"来自语义 Token 的 `inactive` modifier，不需要新协议。
- 配置：项目根 `clice.toml` / `.clice/config.toml`，保存后请求重启；
  支持 JSON Schema（`#:schema` 注释）。
- 参考实现：`editors/vscode/src/feature/`（context、configuration、
  counterparts、command、inactive、includes、refactor、aliases、conflicts）。

## 架构

```
clice.el            入口：defcustom、eglot 注册、能力注入、restart、全局 minor mode
clice-protocol.el   clice/* 请求封装（唯一允许碰 eglot 内部 API 的地方）
clice-context.el    上下文 / 构建配置 / counterparts / 编译命令 / mode-line
clice-links.el      textDocument/documentLink -> 可点击按钮
clice-fold.el       textDocument/foldingRange -> invisible overlay
clice-select.el     textDocument/selectionRange -> 语法选区扩展
clice-semantic.el   扩展 eglot 的语义 token face 与白名单
clice-cli.el        clice lint/format/index/query/scan 封装
clice-toml.el       clice.toml 辅助
```

依赖：Emacs 30.1+、内置 eglot、`cl-transient` 可选。

### 能力注入

`clice--inject-capabilities` advice `eglot-client-capabilities`，仅当
`(process-command (jsonrpc--process server))` 是 clice 时追加：

```elisp
:textDocument (:documentLink (:dynamicRegistration :json-false)
               :foldingRange (:dynamicRegistration :json-false)
               :selectionRange (:dynamicRegistration :json-false))
:experimental (:restart_server t)
```

`eglot-client-capabilities` 原本的 `:experimental` 是空 hash table，直接替换为
plist；Emacs 的 json 序列化会把 `:restart_server` 写成 `restart_server`。

### 重启

```elisp
(cl-defmethod eglot-handle-request
  (server (_method (eql clice/restartServer)) &key reason)
  (clice--handle-restart-request server reason))
```

先回应请求，再用 `run-at-time` 调用 `eglot-reconnect`，避免在 process filter
里同步关闭连接。

### 其它要点

- **语义 Token**：为 clice legend 的额外 type/modifier 定义
  `eglot-semantic-*` face（例如 `field`、`templateParameter`、`module`），
  追加进 `eglot-semantic-token-types` / `-modifiers`；`inactive` 继承
  `shadow`，即可得到"其他上下文变暗"。
- **documentLink**：按钮 + `RET`/鼠标，保存后与空闲时刷新。
- **folding**：自己的 minor mode；与 `hs-minor-mode`（很多发行版在
  `prog-mode` 默认开启）二选一。
- **selectionRange**：范围栈 + `clice-expand-region` / `clice-contract-region`，
  可选桥接 `expand-region`。
- **上下文 UI**：`queryContext`（分页）+ `currentContext`；`switchContext`
  带 epoch，`stale` 时自动重查；mode-line 显示当前上下文。
- **配置切换**：`listConfigurations` → `switchConfiguration` → 等
  `clice/restartServer` 自动重连。
- **counterparts**：有 `preferred` 直达，否则用 `reasons` 做选择列表。
- **CLI**：`compilation-mode` + `--json` 解析；避免与运行中的 LSP 同时写索引
  缓存（提示/开关）。

## 兼容性与风险

| 风险 | 应对 |
|---|---|
| eglot 内部 API（`eglot--request`、`jsonrpc--process`）变动 | 集中在 `clice-protocol.el`，CI 跑 Emacs 30/31 矩阵 |
| clice 0.1 协议演进 | 按 `serverInfo.version` 与 server capability 做能力探测，失败降级 |
| 折叠/链接刷新开销 | 保存 + 空闲去抖；可在 `defcustom` 关闭 |
| `hs-minor-mode` 冲突 | clice 缓冲区关闭 hs；文档说明 |
| 与 clangd/lsp-mode 同时启用 | 一个 buffer 只允许一个 server；检测并提示 |
| 多工作区 | eglot 单 project root；每个项目一个 clice 进程，文档说明限制 |

## 里程碑

| 阶段 | 内容 | 状态 |
|---|---|---|
| M0 | 配置层：官方 eglot 条目、语义 face、开关 inlay/semantic | 待做（可先落自定义配置） |
| M1 | 包骨架 + 能力注入 + restart + context/config/counterparts/compile command | **骨架已完成**，命令待实现 |
| M2 | documentLink、folding、selection、inactive 完善 | 待做 |
| M3 | CLI、clice.toml、诊断 codeDescription、语言 id | 待做 |
| M4 | 集成测试、CI、文档、MELPA、可选上游 PR | 进行中（CI/文档已有） |

## 验收标准

- clice 的标准 LSP 功能全部可用，且不依赖 clangd；
- 3 个 eglot 缺口有等价交互；
- 上下文/配置切换、头源切换、编译命令可发现且可键盘操作；
- clice 重启请求自动处理；
- 所有功能在无 clice 时不影响普通 eglot 用户；
- 单元测试 + 真实 server 集成测试覆盖上述路径。
