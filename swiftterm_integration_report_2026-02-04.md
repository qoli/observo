# SwiftTerm 整合分析報告（observo）

- 生成日期：2026-02-04
- 分析範圍：
  - SwiftTerm 核心庫：`/Volumes/Data/Github/SwiftTerm/`
  - SwiftTerm MacTerminal：`/Volumes/Data/Github/SwiftTerm/TerminalApp/MacTerminal/`
  - SwiftTermApp：`/Volumes/Data/Github/SwiftTermApp/`
  - CodeEdit 整合：`/Volumes/Data/Github/CodeEdit/`
  - 目標專案：`/Volumes/Data/Github/observo/`

## 1) 結論摘要（先看這段）

`observo` 目前已具備可用的 SwiftTerm 終端能力（SSH + Local Shell + 多 Session + 命令橋接）。
技術路線上，現階段偏向「`LocalProcessTerminalView + /usr/bin/ssh`」模型，開發速度快、落地簡單。

若目標是「更高可控性／更完整 SSH 能力／更強安全策略」，下一階段應逐步導向類似 SwiftTermApp 的「網路層與終端層解耦」設計（例如 Session Actor + libssh2）。

## 2) observo 現況（重點）

### 2.1 架構定位

- 核心終端：`SSHLoggingTerminalView : LocalProcessTerminalView`
- SwiftUI 橋接：`SSHMacTerminalContainer : NSViewControllerRepresentable`
- 生命週期與焦點管理：`TerminalHostViewController`
- 連線/命令協調：`SSHIOBridge`

主要代碼集中在：
- `observo/AppTerminalView.swift`

### 2.2 已完成且有價值的能力

1. **終端嵌入與橋接完整**
   - `NSViewControllerRepresentable` + Host VC 的做法清楚，切換與聚焦流程合理。

2. **連線模型可用**
   - 支援 SSH 與 Local Shell 兩種 request 模式。
   - 支援 pending command 注入與去重。

3. **終端命令橋接齊全**
   - Soft/Hard reset、Escape、F1~F12、選取操作都已就緒。

4. **UI 使用性不錯**
   - Session Sidebar、多 session 基礎管理、Inspector（AI Chat / Diff placeholder）皆已串接。

5. **主題套用有基礎**
   - 已有 terminal palette 套用與暗亮外觀切換邏輯。

## 3) 與三個參考專案的對照

### 3.1 對照 SwiftTerm MacTerminal（官方最小示例）

- `observo` 已超越示例：
  - 有多 session、SwiftUI 容器化、命令橋接與附加 AI 面板。
- 保持了示例的核心優點：
  - 以 `LocalProcessTerminalView` 快速落地。

### 3.2 對照 CodeEdit（大型產品整合）

CodeEdit 的關鍵做法：
- 自訂 `CELocalShellTerminalView`（不完全依賴原版 `LocalProcessTerminalView`）
- 解決 zero-frame 清屏問題（`CETerminalView`）
- Terminal cache 保持 session 狀態
- Shell integration 注入（title/cwd 等事件更穩定）

`observo` 的對照結果：
- 已有 Host+Bridge 架構，但**尚未做 terminal view cache**。
- 目前依賴 `LocalProcessTerminalView` 原生行為，若後續遇到視圖重掛載邊界問題，可能需要 CodeEdit 式補丁。

### 3.3 對照 SwiftTermApp（完整 SSH 產品路線）

SwiftTermApp 的關鍵做法：
- `SessionActor` 封裝 libssh2 非阻塞工作流（EAGAIN/retry）
- 通道、SFTP、known_hosts、安全策略、重連與 tmux 等完整能力
- 主題系統（XRDB）成熟

`observo` 的對照結果：
- 目前 SSH 仍是 `/usr/bin/ssh` 子進程模型。
- 功能上可用，但在下列方面可控性較弱：
  - host key 驗證策略細節
  - reconnect / connection reuse
  - SFTP/子通道能力
  - 細粒度錯誤恢復

## 4) 主要風險與缺口（按優先級）

### P0（建議優先處理）

1. **可攜性風險：本地絕對路徑套件依賴**
   - `AnyLanguageModel` 使用絕對路徑 local package。
   - 團隊協作與 CI 複製環境成本高。

2. **安全策略仍偏「開發友善」**
   - SSH 參數使用 `StrictHostKeyChecking=accept-new`。
   - 對生產場景不夠嚴謹（首次信任仍有風險面）。

3. **敏感資訊儲存**
   - API key 使用 `@AppStorage`（UserDefaults）而非 Keychain。

### P1（近期應處理）

4. **單檔過大，維護成本快速上升**
   - `AppTerminalView.swift` 集中 UI、狀態、橋接、模型 client、命令等多責任。

5. **TODO 文檔與現況存在偏差**
   - TODO 提到部分已存在/未落地的設計（如 `TerminalVisualStyle`）未與實碼一致。

6. **測試覆蓋不足**
   - 缺少 terminal bridge/session 狀態流的單元測試與 UI 測試。

## 5) 建議路線圖（務實版）

### Phase 0：先穩定（1~2 週）

- 將敏感設定（API key）移到 Keychain。
- 修正 package 依賴策略（避免絕對路徑）。
- 補最小測試：
  - `SSHIOBridge` request 切換
  - pending command 去重
  - disconnect/reset context

### Phase 1：拆責任（1~2 週）

把 `AppTerminalView.swift` 拆成：
- `TerminalSessionStore.swift`
- `SSHIOBridge.swift`
- `TerminalHostViewController.swift`
- `AIChatDetailView.swift`
- `TerminalCommandBridge.swift`

收益：降低耦合，後續改 SSH 核心時風險較小。

### Phase 2：SSH 核心升級評估（2~4 週）

- 先做 PoC，不直接替換現有流程：
  - 建立 `SessionActor` 原型（可參考 SwiftTermApp 思路）
  - 驗證：連線、讀寫、resize、斷線恢復
- 若 PoC 成功，再逐步替換 `/usr/bin/ssh` path。

## 6) 對你專案的具體建議（可直接開工）

1. 建立 `Security` 子模組：
   - `KeychainStore`（token/密鑰存取）
   - `HostKeyPolicy`（先記錄策略，再逐步收斂）

2. 建立 `TerminalCore` 子模組：
   - `TerminalRequest`, `TerminalBridge`, `TerminalCommandDispatcher`

3. 建立 `TerminalTheme` 子模組：
   - 將 `TerminalPalette` 升級成可配置模型（預留 XRDB 匯入）

4. 補測試目標 `observoTests`：
   - 首批先覆蓋非 UI 邏輯（bridge/store/parser）

## 7) 最終判斷

`observo` 現在已經跨過「能不能用」階段，進入「要不要長期可演進」階段。

短期最有價值的投入順序：
1) 安全與可攜性
2) 大檔拆分與測試
3) SSH 核心 PoC（是否升級到 SessionActor/libssh2）

---

若要，我可以在下一步直接幫你產出：
- 「按檔案拆分的實作清單（含每檔骨架）」
- 「第一批測試用例清單（可直接轉 XCTest）」
