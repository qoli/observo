# Termius Terminal Stack Deep Probe Report (macOS)

Date: 2026-02-09  
Target: `/Applications/Termius.app`  
Observed app version: `9.36.3`  
Observed Electron framework version: `21.4.4`

## 1) Executive Summary

Termius desktop on macOS is an **Electron app** with a **hybrid terminal architecture**:

- Renderer terminal UI: **xterm.js** (+ Fit/Search/Serialize/WebLinks and custom addons)
- Local PTY: **`@termius/node-pty`** native addon
- SSH/Telnet/SFTP core: **`@termius/libtermius`** native addon (depends on `libssh2`)
- Mosh: **`@termius/mosh`** native addon
- Shell integration: custom **OSC 4545 protocol** (`SetCwd`, prompt begin/end, command start/exit)
- Process model: main process forks isolated utility processes (`service-process`, `fido-process`)

For your own “Termius-like” terminal app, the most critical technical pattern is:
**xterm.js in renderer + protocol engines in isolated Node/native process + explicit shell integration protocol over OSC**.

## 2) Probe Method & Repro

Main commands used:

```bash
plutil -p /Applications/Termius.app/Contents/Info.plist
plutil -p "/Applications/Termius.app/Contents/Frameworks/Electron Framework.framework/Resources/Info.plist"
find /Applications/Termius.app/Contents/Resources/app.asar.unpacked -maxdepth 6 -type f
otool -L <native_module>.node
lipo -archs <native_module>.node
strings <native_module>.node | rg ...
```

To inspect minified JS inside `app.asar`, I extracted key files and normalized them to line-friendly text:

```bash
# extract (asar CLI via npx + tmp cache)
export npm_config_cache=/tmp/npm-cache-codex
npx -y asar list /Applications/Termius.app/Contents/Resources/app.asar
npx -y asar extract-file ... main-process/main-process.js
npx -y asar extract-file ... utilities-process/service-process.js
npx -y asar extract-file ... ui-process/assets/ui-process-757d6568.js
npx -y asar extract-file ... ui-process/assets/reconnectSaga-487daae2.js

# normalize one-line bundles
perl -pe 's/;/;\n/g' <file.js> > /tmp/termius_probe/<file>.pretty.js
```

## 3) Evidence: Terminal Implementation

### 3.1 Renderer terminal is xterm.js

Evidence in normalized UI bundle:

- `/tmp/termius_probe/ui-process-757d6568.pretty.js:3953`
  - `this.terminal=new r.Terminal({... windowsPty ...})`
- `/tmp/termius_probe/ui-process-757d6568.pretty.js:3966`
  - loads addons: `WebLinksAddon`, `searchAddon`, `serializeAddon`, Unicode11, etc.
- `/tmp/termius_probe/ui-process-757d6568.pretty.js:3905`
  - `serializeAddon` initialized
- `/tmp/termius_probe/ui-process-757d6568.pretty.js:3906`
  - `searchAddon` initialized

Interpretation:

- Core terminal rendering/parsing is xterm.js.
- They layer custom behavior (shell integration bridge, cursor/highlight/autofit/flow-control) around xterm.

### 3.2 Local terminal uses node-pty

Evidence:

- `/tmp/termius_probe/service-process.pretty.js:1860`
  - local provider `class OP`
- `/tmp/termius_probe/service-process.pretty.js:1866`
  - `Ev.spawn(...)` from `@termius/node-pty`
- `/Applications/Termius.app/Contents/Resources/app.asar.unpacked/node_modules/@termius/node-pty/lib/index.js:28`
  - `spawn(file, args, opt) { return new terminalCtor(...) }`
- `strings` on `pty.node` shows `forkpty`, `openpty`, `ioctl`:
  - confirms real PTY implementation in native layer.

### 3.3 SSH/Telnet/SFTP are native (not pure JS ssh2 flow)

Evidence:

- `/tmp/termius_probe/service-process.pretty.js:4480`
  - `this.client=new H.SshClient`
- `/tmp/termius_probe/service-process.pretty.js:4767`
  - `new H.TelnetClient`
- `/tmp/termius_probe/service-process.pretty.js:4631`
  - session log writer hooks around shell data stream
- `/Applications/Termius.app/Contents/Resources/app.asar.unpacked/node_modules/@termius/libtermius/index.js:16`
  - loads `termius.node` by platform/arch
- `otool -L termius.node`
  - links `@loader_path/libssh2.1.dylib`
- `strings termius.node`
  - symbols include `SshClient`, `TelnetClient`, `sftp`, `terminalOutput`, forwarding/pty related symbols.

### 3.4 Mosh is separate native engine

Evidence:

- `/tmp/termius_probe/service-process.pretty.js:1894`
  - executes `mosh_server_command` via SSH
- `/tmp/termius_probe/service-process.pretty.js:1901`
  - `new wv.MoshClient`
- `/Applications/Termius.app/Contents/Resources/app.asar.unpacked/node_modules/@termius/mosh/index.js:16`
  - loads `moshclient.node`
- `strings moshclient.node`
  - protobuf/network source paths from `termius-mosh-client`.

### 3.5 Shell integration protocol is explicit OSC 4545

Evidence in bridge bundle:

- `/tmp/termius_probe/reconnectSaga-487daae2.pretty.js:13504`
  - OSC enum includes `SetCwd`, `ShellPromptBegins`, `ShellPromptEnds`, `CommandStarted`, `CommandExited`
- `/tmp/termius_probe/reconnectSaga-487daae2.pretty.js:13512`
  - `TermiusShellIntegrationIdentifier=4545`
- `/tmp/termius_probe/reconnectSaga-487daae2.pretty.js:13518`
  - `registerOscHandler(4545, ...)`
- `/tmp/termius_probe/reconnectSaga-487daae2.pretty.js:13519`
  - payload uses `decodeBase64(...)` for CWD/command text

Evidence in shell injection scripts:

- `bash`: `/Applications/Termius.app/Contents/Resources/app.asar.unpacked/out/shell-integration/bashrc.sh:74`
- `zsh`: `/Applications/Termius.app/Contents/Resources/app.asar.unpacked/out/shell-integration/zdotdir/.zshrc:43`
- `fish`: `/Applications/Termius.app/Contents/Resources/app.asar.unpacked/out/shell-integration/xdg_data/fish/vendor_conf.d/termius.fish:19`

These scripts print sequences like:

- `\e]4545;SetCwd;<base64>\a`
- `\e]4545;ShellPromptBegins\a`
- `\e]4545;ShellPromptEnds\a`
- `\e]4545;CommandStarted;<base64>\a`
- `\e]4545;CommandExited;<exit_code>\a`

This is the key mechanism enabling prompt-aware UX and command lifecycle tracking.

### 3.6 Shell integration reliability guardrails

Evidence:

- `/tmp/termius_probe/service-process.pretty.js:4581`
  - timeout/stream checks for integration bootstrap
- `/tmp/termius_probe/service-process.pretty.js:4582`
  - detects non-shell prompt and alternate buffer failures
- `/tmp/termius_probe/service-process.pretty.js:4755`
  - checks for marker match
- `/tmp/termius_probe/service-process.pretty.js:4762`
  - waits for `\x1B]4545;B` marker with timeout

Interpretation:

- They actively avoid false positives (interactive auth prompts, alternate screen apps like vim/top, timeouts).

### 3.7 Process boundaries

Evidence:

- `/tmp/termius_probe/main-process.pretty.js:12059`
  - forks utility processes with `child_process.fork(...)`
- `/tmp/termius_probe/main-process.pretty.js:12069`
  - process allocator for `"fido"` and `"service"`
- `/tmp/termius_probe/main-process.pretty.js:12071`
  - utility process path: `../utilities-process/${t}-process.js`
- `/tmp/termius_probe/service-process.pretty.js:4792`
  - `ipcSingleton.serve(...)`

Interpretation:

- Terminal/network native work is intentionally not in renderer.
- This reduces blast radius of crashes and keeps IPC contract explicit.

### 3.8 Preload bridge and native module preload

Evidence:

- `/tmp/termius_probe/preload.pretty.js:8058`
  - `exposeInMainWorld("fileImports", ...)`
- `/tmp/termius_probe/preload.pretty.js:8059`
  - preloads `@termius/libfido2`, `@termius/libtermius`, `@termius/mosh`, `@termius/registry-js`
- `/tmp/termius_probe/preload.pretty.js:5`
  - uses `@termius/serialport-bindings`

## 4) Terminal Data Flow (Inferred)

1. User input in xterm renderer  
2. Renderer forwards bytes/events to service process  
3. Service provider dispatches by protocol (`ssh`/`mosh`/`telnet`/`local`/`serial`)  
4. Native client emits output bytes  
5. Service side does charset decode + optional session log write  
6. Renderer writes to xterm with flow control  
7. OSC 4545 frames are parsed by shell integration bridge, updating CWD/prompt/command state

## 5) What This Means for Your Own App

If your target is “Termius-grade terminal UX”, you likely need this shape:

- Renderer:
  - xterm.js + Fit/Search/Serialize/WebLinks
  - shell integration bridge addon (your own OSC protocol)
- Service process:
  - protocol abstraction layer
  - local PTY (`node-pty`)
  - SSH/Telnet/SFTP/Mosh engines (native addons or Rust/C++ core)
  - session log pipeline
- Main process:
  - utility process allocator + IPC contracts
  - crash containment and lifecycle management

### Recommended implementation sequence

1. Build minimal shell (`xterm + node-pty local`)  
2. Add service-process boundary + typed IPC  
3. Add SSH engine + reconnection  
4. Add OSC shell integration protocol (CWD/prompt/command events)  
5. Add session log pipeline + replay  
6. Add Mosh + serial as separate providers

## 6) Risk Notes for a New Product

- Shell integration is the hardest UX multiplier and easiest place to get flaky behavior.
- Protocol-native code requires strict crash isolation and watchdogs.
- Session logging needs encryption/key handling from day one if enterprise is a goal.
- macOS notarization/signing and native module packaging complexity is non-trivial.

## 7) Quick Tech Stack Recommendation

For fastest time-to-market (desktop first):

- UI/runtime: Electron + React + xterm.js
- Local terminal: node-pty
- Remote protocols:
  - Phase 1: mature library path (SSH first)
  - Phase 2: native performance path (Rust/C++ core, Node addon bridge)
- Shell integration:
  - Keep OSC-based protocol (similar to 4545 approach), base64 payloads, strict parser + timeout guards
- Logging:
  - append-only encrypted chunks + replay reader

This architecture matches the strongest implementation patterns observed in Termius.
