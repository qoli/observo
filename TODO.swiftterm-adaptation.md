# SwiftTerm 适配 TODO（对照 SwiftTermApp）

> 基线参考：`/Volumes/Data/Github/SwiftTermApp`
> 更新时间：2026-02-03

## 状态总览

- [x] **SwiftUI ↔ ViewController 桥接（macOS）**
  - 已有 `NSViewControllerRepresentable` 封装：`SSHMacTerminalContainer`。
  - 见：`observo/AppTerminalView.swift:665`

- [~] **终端容器控制（约束 / first responder / 可见终端指针）**
  - 已有 `TerminalHostViewController`，包含约束、聚焦、`visibleTerminal`。
  - 见：`observo/AppTerminalView.swift:612`
  - 待补：统一 keyboard/快捷键管理入口（目前分散在 View 与容器中）。

- [~] **App 级 Adapter（主题/字型绑定）**
  - 已有 `@AppStorage` + `TerminalVisualStyle` + `apply(style:)`。
  - 见：`observo/AppTerminalView.swift:15`、`observo/AppTerminalView.swift:576`
  - 待补：像 SwiftTermApp 一样支持完整 ANSI 主题安装（不仅前景/背景/光标）。

- [x] **I/O 桥接层**
  - 已有 `SSHIOBridge` 处理连接生命周期、命令发送、标题/目录回调。
  - 见：`observo/AppTerminalView.swift:728`

- [x] **性能细节：分块 feed**
  - 已按 1KB 分块喂给 terminal。
  - 见：`observo/AppTerminalView.swift:583`、`observo/AppTerminalView.swift:602`

- [ ] **底层网络分离（NWConnection + libssh2 Session/Actor）**
  - 目前仍是 `LocalProcessTerminalView + /usr/bin/ssh` 模式。
  - 见：`observo/AppTerminalView.swift:774`

- [x] **快捷键与终端命令层（reset/selection/F-keys）**
  - 已新增 app 级 `Commands` 菜单与命令桥接：Soft/Hard Reset、Selection、Escape、F1-F12。
  - 见：`observo/TerminalCommands.swift`、`observo/AppTerminalView.swift:665`

- [ ] **外部色票 → SwiftTerm Color 主题转换**
  - 目前仅 hex 转 `NSColor` 并设置 foreground/background。
  - 见：`observo/AppTerminalView.swift:829`

## 下一步建议（按优先级）

1. 补「完整主题层」：引入 ANSI 16 色映射并安装到 SwiftTerm。
2. 整理终端容器输入通道：把 keyboard/快捷键入口再收敛到单一层。
3. 评估是否切到 `libssh2` 架构（成本高、收益主要在可控性与可观测性）。
