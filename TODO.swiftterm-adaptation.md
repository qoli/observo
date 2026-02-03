# SwiftTerm 适配 TODO（对照 SwiftTermApp）

> 基线参考：`/Volumes/Data/Github/SwiftTermApp`  
> 最后核对：2026-02-03

## 状态总览

- [x] **SwiftUI ↔ ViewController 桥接（macOS）**
  - 已使用 `NSViewControllerRepresentable` 封装 `TerminalHostViewController`（`SSHMacTerminalContainer`）。
  - 关键点：支持新建 terminal、重绑 session 状态、更新 style。

- [x] **终端容器控制（约束 / first responder / 可见终端指针）**
  - `TerminalHostViewController` 负责约束、`viewDidAppear` 聚焦、`visibleTerminal` 管理。
  - `viewWillDisappear` 会清理可见指针，避免命令桥接误发。

- [~] **输入与快捷键入口统一**
  - 已有两条稳定通道：  
    1) 命令编辑区（`Cmd+Enter` 发送）  
    2) App `Commands` 菜单（Reset/Selection/Escape/F1~F12）
  - 仍可优化：把“命令发送”和“终端控制键”映射进一步收敛到同一输入层。

- [x] **App 级 Adapter（主题/字体绑定）**
  - 已有 `TerminalVisualStyle` + `@AppStorage` + `apply(style:)`。
  - 已支持 light/dark 分流主题键：`terminal.light.*`、`terminal.dark.*`。
  - 背景 token 已切换为 `lightBackground` / `darkBackground`。

- [x] **I/O 桥接层**
  - `SSHIOBridge` 负责连接生命周期、发送 pending command、标题与目录同步。
  - 已修复断线重连后“重放最后一条命令”问题（重置与发送后都会清空 pending）。

- [x] **性能细节：分块 feed**
  - 远端输出按 1KB chunk feed 到 SwiftTerm，避免大包导致 UI 卡顿。

- [ ] **底层网络分离（NWConnection + libssh2 + SessionActor）**
  - 当前仍为 `LocalProcessTerminalView + /usr/bin/ssh` 模式。
  - 该项是后续最大改造点（高成本，高可控性收益）。

- [x] **终端命令层能力**
  - 已有 `TerminalCommandBridge`：soft/hard reset、selection、escape、F1~F12。

- [x] **主题颜色转换**
  - ANSI 16 色 CSV -> SwiftTerm `Color[]` -> `installColors` 已打通。
  - AI 分析改为读取 terminal plain text（而非 raw VT stream）。

## 下一步（建议优先级）

1. **P0：网络层解耦评估**  
   起草 `SessionActor` 原型（先不替换 UI），验证 libssh2 非阻塞读写与重连策略。

2. **P1：输入路径统一**  
   把 composer send / 菜单命令 / 快捷键映射收敛到单一 action dispatcher。

3. **P1：主题设置 UI 完整化**  
   目前已支持存储与应用，建议补一个可视化编辑页（前景/背景/16 色）。

4. **P2：导出能力补齐**  
   在菜单补 `Export Plain Text`（当前已有 Print 按钮可打印纯文本快照）。

## More（規劃中的更多優化）

> 這一節保留為「後續優化清單」，不是當前完成項。

- [ ] **非同步 SSH 核心強化**  
  參考 `SessionActor` + libssh2 EAGAIN/retry，提升穩定性與可觀測性。

- [ ] **連線重用與重連策略**  
  補 host/session 管理、同 host 重掛、可選 tmux reconnect。

- [ ] **安全面完善**  
  引入 Keychain / Secure Enclave / known_hosts 驗證流程。

- [ ] **資料層抽象化**  
  拆分 Host/Key protocol、memory model、儲存層，降低 UI 耦合。

- [ ] **資料持久化升級**  
  評估 CoreData（含本地 + CloudKit 雙 store）作為 session/host 設定儲存。

- [ ] **終端 UX 細節提升**  
  補 bell 策略、buffer export、字型/主題熱更新、更多快捷鍵。

- [ ] **主題系統進階化**  
  參考 SwiftTermApp：XRDB 匯入、內建主題集、每主機覆寫、執行中即時套用。

- [ ] **字體系統進階化**  
  補字體清單管理、系統字級模式、pinch 覆寫策略、執行中同步更新。

- [ ] **視覺層擴展（可選）**  
  評估 Metal 背景/特效疊合終端畫面（保留性能開關）。
