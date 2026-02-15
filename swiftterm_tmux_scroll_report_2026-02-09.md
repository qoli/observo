# SwiftTerm 與 tmux 滾輪問題評估報告（observo）

日期：2026-02-09  
專案：`/Volumes/Data/Github/observo`

## 1. 結論（先看）

你目前遇到的「tmux 內無法正常滾動」不是單一 app 寫法問題，而是 **SwiftTerm macOS 端預設滾輪處理策略的能力缺口**。

建議決策：

1. **先不切技術棧**（不急著放棄 SwiftTerm）
2. 先做 **SwiftTerm 滾輪 mouse-reporting 補丁**（fork）
3. 同步調整 `observo` 自己的 scroll monitor，避免事件被提前吃掉
4. 驗證後再決定是否要走更大規模遷移

## 2. 問題背景

你觀察到：

- `observo` 在 tmux 內滾輪體驗不如 Termius
- 另外兩個同樣基於 SwiftTerm 的終端也有相同問題

這個訊號很強，代表問題很可能在共享底層，而不是單一產品實作。

## 3. 根因證據

### 3.1 SwiftTerm 的 macOS `scrollWheel` 目前只做本地 scrollback

- `SwiftTerm/Sources/SwiftTerm/Mac/MacTerminalView.swift:1198`
  - `scrollWheel(with:)` 僅呼叫 `scrollUp/scrollDown`
  - 沒有在滾輪路徑下送出 `sendEvent(button 4/5)` 到終端後端

對照同檔其他事件：

- `SwiftTerm/Sources/SwiftTerm/Mac/MacTerminalView.swift:1024`
  - `mouseDown` 在 mouse reporting 模式會送事件
- `SwiftTerm/Sources/SwiftTerm/Mac/MacTerminalView.swift:1084`
  - `mouseDragged` 在 mouse reporting 模式會送 motion 事件

=> 結論：**點擊/拖曳有 reporting，滾輪沒有 reporting**。

### 3.2 SwiftTerm 核心其實已支援 mouse mode 與 wheel button 編碼

- `SwiftTerm/Sources/SwiftTerm/Terminal.swift:4067`
  - 解析 DECSET `1000/1002/1003/1006` 等 mouse mode
- `SwiftTerm/Sources/SwiftTerm/Terminal.swift:5347`
  - button `4/5` 已定義（wheel up/down）

=> 結論：能力在核心已存在，但 **macOS 滾輪入口沒接上**。

### 3.3 observo 還有第二層事件攔截（會加劇）

- `observo/AppTerminalView.swift:837`
  - `installScrollWheelBridgeIfNeeded()`
- `observo/AppTerminalView.swift:840`
  - `NSEvent.addLocalMonitorForEvents(.scrollWheel)`
- `observo/AppTerminalView.swift:857`
  - `return nil`（事件被消耗）

=> 即使 SwiftTerm 之後修好，這層也可能攔截掉事件，需同步調整。

## 4. 為什麼 Termius 不受影響

Termius 不是走 SwiftTerm；它是自己的事件路由與終端實作，會在適當狀態把 wheel 轉成遠端可理解的輸入事件（含 tmux/vim 類場景），所以體驗正常。

## 5. 技術路線比較

### 路線 A：保留 SwiftTerm，修補滾輪 reporting（建議）

做法：

- 在 SwiftTerm `MacTerminalView.scrollWheel` 補分支：
  - `allowMouseReporting && terminal.mouseMode != .off` 時，送 wheel mouse event
  - 否則維持本地 `scrollUp/scrollDown`
- `observo` 端 monitor 改為「條件攔截」，避免一律 `return nil`

優點：

- 成本最低、見效最快
- 保留既有 SwiftUI/bridge/session 架構
- 可回饋上游 PR，降低長期維護成本

風險：

- 需維護 fork（至少短期）

### 路線 B：完全換棧（例如 xterm.js 路線）

優點：

- 可得更成熟的 terminal ecosystem（addon、事件處理、既有社群解法）

缺點：

- 成本高、遷移長
- 你現有 `LocalProcessTerminalView`、`TerminalSessionStore`、命令橋接要重做

### 路線 C：維持現狀不修

結果：

- tmux 族群體驗持續落差
- 產品定位若偏 power-user，風險高

## 6. 建議執行計畫（兩週內可落地）

### 第 1 階段（1-2 天）

1. Fork SwiftTerm，修 `MacTerminalView.scrollWheel`  
2. `observo` 移除或條件化 scroll monitor 攔截  

### 第 2 階段（2-3 天）

回歸測試：

1. 一般 shell（非 tmux）本地 scrollback 正常  
2. `tmux set -g mouse on` 下：
   - pane 滾動
   - copy-mode
   - alternate screen app（`vim`, `less`, `htop`）不退化

### 第 3 階段（1 天）

1. 若 patch 穩定，整理為上游 PR
2. 專案保留暫時 fork pin；待上游合併後回切

## 7. 驗收標準

達成以下即視為可接受：

1. tmux 內滾輪行為與主流終端一致（至少不比 iTerm2 差）
2. 非 tmux 場景本地滾動無退化
3. 不新增明顯 CPU 抖動或輸入延遲

## 8. 補充觀察（非本問題核心）

- 目前 SSH 仍是 `/usr/bin/ssh` 子程序：
  - `observo/AppTerminalView.swift:1031`
- host key 策略目前偏開發友善：
  - `observo/AppTerminalView.swift:1027`
- 本地套件依賴有絕對路徑（後續建議整理）：
  - `observo.xcodeproj/project.pbxproj:383`

---

最終建議：**先補 SwiftTerm 滾輪 reporting，不要先換技術型態。**  
這是目前風險最低、最符合你現況架構的路線。
