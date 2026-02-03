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
  - 已适配 Light / Dark mode 分流主题键（foreground/background/ANSI 16 色）。
  - 见：`observo/AppTerminalView.swift:15`、`observo/AppTerminalView.swift:576`
  - 已补：ANSI 16 色安装（CSV palette → SwiftTerm Color[] → `installColors`）。

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

- [x] **外部色票 → SwiftTerm Color 主题转换**
  - 已支持 `terminal.ansiPaletteHexCSV`（16 色）并转换后安装到 SwiftTerm 调色板。
  - 见：`observo/AppTerminalView.swift`

## 下一步建议（按优先级）

1. 整理终端容器输入通道：把 keyboard/快捷键入口再收敛到单一层。
2. 为 ANSI 主题补 UI 编辑入口（目前只有 `AppStorage` 配置键）。
3. 评估是否切到 `libssh2` 架构（成本高、收益主要在可控性与可观测性）。


## More
  - SSH 非同步封裝：libssh2 的 EAGAIN/retry + actor 串行化，這套很有參考價值（SwiftTermApp/Ssh/SessionActor.swift, SwiftTermApp/Ssh/
    Session.swift）。
  - 連線重用/重連策略：同 host 重掛 terminal、tmux reconnect、session 管理（SwiftTermApp/Connections.swift, SwiftTermApp/Terminal/
    SshTerminalView.swift）。
  - 安全面：Keychain + Secure Enclave + known_hosts 驗證流程（SwiftTermApp/Keys/KeychainTools.swift, SwiftTermApp/Keys/KeyTools.swift,
    SwiftTermApp/Ssh/LibsshKnownHost.swift）。
  - 資料層抽象：Host/Key protocol + CoreData 實體 + memory model，解耦 UI 與儲存層（SwiftTermApp/Model/DataModelTypes.swift, SwiftTermApp/
    Model/CHost-DataHelpers.swift, SwiftTermApp/Model/MemoryModels.swift）。
  - CoreData + CloudKit 雙 store 配置：本地＋雲端分開的容器設定很實用（SwiftTermApp/Model/DataController.swift）。
  - 終端 UX 細節：bell 行為、快捷鍵、buffer export、字型/主題熱更新（SwiftTermApp/Terminal/SshTerminalView.swift, SwiftTermApp/
    Commands.swift, SwiftTermApp/Terminal/AppTerminalView.swift）。
  - Metal 背景整合：把即時 shader 跟 terminal 疊合（SwiftTermApp/Metal/MetalHost.swift, SwiftTermApp/Terminal/AppTerminalView.swift）。

• 有，主題這塊其實做得很完整，重點在這幾層
  - 主題模型與解析：ThemeColor 定義了 ANSI 16 色 + foreground/background/cursor/selection，並可從 XRDB 字串解析。看 SwiftTermApp/Settings/
    ColorLoader.swift:12、SwiftTermApp/Settings/ColorLoader.swift:48。
  - 主題來源：內建多組 theme（Solarized、Material、Pro...）直接放在 SettingsView.swift，由 themes 陣列組裝。看 SwiftTermApp/Settings/
    SettingsView.swift:424。
  - 全域主題設定：Settings.themeName 存進 UserDefaults，getTheme() 統一取主題。看 SwiftTermApp/Settings/SettingsView.swift:44、SwiftTermApp/
    Settings/SettingsView.swift:82。
  - 每台主機覆蓋：Host 可設定自己的 style；空字串代表「跟隨全域」。看 SwiftTermApp/Hosts/HostEditView.swift:302、SwiftTermApp/Terminal/
    AppTerminalView.swift:51。
  - 即時套用機制：AppTerminalView 監聽設定變更與 host runtime 事件，動態重套主題，不需重連。看 SwiftTermApp/Terminal/
    AppTerminalView.swift:70、SwiftTermApp/Terminal/AppTerminalView.swift:84。
  - 實際落地到 SwiftTerm：applyTheme() 把色彩寫入 TerminalView（ansi/fg/bg/caret/selection）。看 SwiftTermApp/Terminal/
    AppTerminalView.swift:237。
  - 首次開終端套用：terminal 建立時，依 host.style 決定用 host 或全域主題。看 SwiftTermApp/Terminal/TerminalViewController.swift:70。
  - 連線中改主題：齒輪面板 RunningTerminalConfig 會送 runtimeVisibleChanges，讓已開的 terminal 立刻更新。看 SwiftTermApp/Terminal/
    ConfigurableTerminal.swift:19、SwiftTermApp/Terminal/ConfigurableTerminal.swift:24。

  你如果要改主題系統，最好的切入點是：新增一個 XRDB 主題字串 + 加到 themes 陣列，其他 UI/套用流程都已經接好了。

  • 字體設定在這個專案是「全域設定 + 執行中即時套用」：

  - 字體來源與清單：可選字體在 SwiftTermApp/Settings/SettingsView.swift:107（fontNames），UI 在 SwiftTermApp/Settings/
    SettingsView.swift:222（FontSelector）與 SwiftTermApp/Settings/SettingsView.swift:242（FontSizeSelector）。
  - 持久化：Settings 用 UserDefaults 存 fontName / fontSize，啟動時回讀。見 SwiftTermApp/Settings/SettingsView.swift:49、SwiftTermApp/
    Settings/SettingsView.swift:56、SwiftTermApp/Settings/SettingsView.swift:90。
  - 系統字級模式：fontSize == 0 代表用系統建議字級，由 resolveFontSize 轉成實際 point size。見 SwiftTermApp/Settings/SettingsView.swift:65。
  - 套用到 TerminalView：AppTerminalView 監聽 settings.$fontName/$fontSize，呼叫 updateFont 直接改 TerminalView.font。見 SwiftTermApp/
    Terminal/AppTerminalView.swift:59、SwiftTermApp/Terminal/AppTerminalView.swift:65、SwiftTermApp/Terminal/AppTerminalView.swift:199。
  - 手勢覆寫：pinch 會即時改字體，並把 userOverrideSize = true，之後就不再跟隨全域 fontSize 更新。見 SwiftTermApp/Terminal/
    AppTerminalView.swift:209。
  - 字體檔註冊：Source Code Pro 透過 UIAppFonts 註冊在 SwiftTermApp/Info.plist:89，實際檔案在 SwiftTermApp/Fonts/。
  - 小重點：RunningTerminalConfig 裡的字體儲存會寫回全域 settings，不是 per-host。見 SwiftTermApp/Terminal/ConfigurableTerminal.swift:25。