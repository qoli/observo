import SwiftUI

#if os(macOS)
    struct TerminalCommands: Commands {
        var body: some Commands {
            CommandMenu("Terminal") {
                Button("Soft Reset") {
                    TerminalCommandBridge.softReset()
                }
                .keyboardShortcut("r", modifiers: [.command, .option])

                Button("Hard Reset") {
                    TerminalCommandBridge.hardReset()
                }
                .keyboardShortcut("r", modifiers: [.command, .option, .control])

                Divider()

                Button("Select All in Terminal") {
                    TerminalCommandBridge.selectAll()
                }

                Button("Clear Selection") {
                    TerminalCommandBridge.clearSelection()
                }
            }

            CommandMenu("Terminal Keys") {
                Button("Escape") {
                    TerminalCommandBridge.sendEscape()
                }
                .keyboardShortcut("[", modifiers: [.control])

                Divider()

                Button("F1") { TerminalCommandBridge.sendFunctionKey(1) }
                    .keyboardShortcut("1", modifiers: [.command, .shift])
                Button("F2") { TerminalCommandBridge.sendFunctionKey(2) }
                    .keyboardShortcut("2", modifiers: [.command, .shift])
                Button("F3") { TerminalCommandBridge.sendFunctionKey(3) }
                    .keyboardShortcut("3", modifiers: [.command, .shift])
                Button("F4") { TerminalCommandBridge.sendFunctionKey(4) }
                    .keyboardShortcut("4", modifiers: [.command, .shift])
                Button("F5") { TerminalCommandBridge.sendFunctionKey(5) }
                    .keyboardShortcut("5", modifiers: [.command, .shift])
                Button("F6") { TerminalCommandBridge.sendFunctionKey(6) }
                    .keyboardShortcut("6", modifiers: [.command, .shift])
                Button("F7") { TerminalCommandBridge.sendFunctionKey(7) }
                    .keyboardShortcut("7", modifiers: [.command, .shift])
                Button("F8") { TerminalCommandBridge.sendFunctionKey(8) }
                    .keyboardShortcut("8", modifiers: [.command, .shift])
                Button("F9") { TerminalCommandBridge.sendFunctionKey(9) }
                    .keyboardShortcut("9", modifiers: [.command, .shift])
                Button("F10") { TerminalCommandBridge.sendFunctionKey(10) }
                    .keyboardShortcut("0", modifiers: [.command, .shift])
                Button("F11") { TerminalCommandBridge.sendFunctionKey(11) }
                    .keyboardShortcut("-", modifiers: [.command, .shift])
                Button("F12") { TerminalCommandBridge.sendFunctionKey(12) }
                    .keyboardShortcut("=", modifiers: [.command, .shift])
            }
        }
    }
#endif
