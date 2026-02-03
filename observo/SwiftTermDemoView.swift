import SwiftUI
import SwiftTerm

#if os(macOS)
import AppKit

struct SwiftTermDemoView: View {
    @State private var host = "127.0.0.1"
    @State private var port = "22"
    @State private var username = NSUserName()
    @State private var activeRequest: SSHSessionRequest?
    @State private var commandInput = ""
    @State private var pendingCommand: PendingCommand?

    private var canConnect: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Int(port) != nil
    }

    private var isConnected: Bool {
        activeRequest != nil
    }

    var body: some View {
        VStack(spacing: 14) {
            connectionPanel

            SSHMacTerminalContainer(request: activeRequest, pendingCommand: pendingCommand)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }
                .overlay(alignment: .bottom) {
                    commandComposer
                }
        }
        .padding(12)
        .navigationTitle("SwiftTerm SSH")
    }

    private func connect() {
        guard let portValue = Int(port) else { return }
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        activeRequest = SSHSessionRequest(host: cleanHost, port: portValue, username: cleanUser)
    }

    private func sendCommand() {
        let trimmed = commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingCommand = PendingCommand(text: trimmed)
        commandInput = ""
    }

    @ViewBuilder
    private var connectionPanel: some View {
        VStack(spacing: 10) {
            HStack {
                Label("SSH Connection", systemImage: "network")
                    .font(.headline)
                Spacer()
                Label(isConnected ? "Connected" : "Disconnected", systemImage: isConnected ? "checkmark.circle.fill" : "bolt.slash.circle")
                    .font(.callout)
                    .foregroundStyle(isConnected ? .green : .secondary)
            }

            HStack(spacing: 10) {
                TextField("Host", text: $host)
                TextField("Port", text: $port)
                    .frame(width: 80)
                TextField("Username", text: $username)
                    .frame(width: 170)
                Spacer(minLength: 0)
                Button("Connect") {
                    connect()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canConnect)

                Button("Disconnect") {
                    activeRequest = nil
                }
                .buttonStyle(.bordered)
                .disabled(!isConnected)
            }
            .textFieldStyle(.roundedBorder)
            .controlSize(.regular)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var commandComposer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if commandInput.isEmpty {
                    Text("Type a command, then click Send")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                        .padding(.leading, 8)
                }

                TextEditor(text: $commandInput)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 68, maxHeight: 68)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
            .padding(6)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button {
                sendCommand()
            } label: {
                Label("Send", systemImage: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(commandInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

private struct SSHSessionRequest: Equatable {
    let host: String
    let port: Int
    let username: String
}

private struct PendingCommand: Equatable {
    let id = UUID()
    let text: String
}

private struct SSHMacTerminalContainer: NSViewRepresentable {
    let request: SSHSessionRequest?
    let pendingCommand: PendingCommand?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.processDelegate = context.coordinator
        terminal.nativeBackgroundColor = .black
        terminal.nativeForegroundColor = .systemGreen
        terminal.caretColor = .systemGreen
        terminal.feed(text: "[SSH] Ready. Fill host/port/user and press Connect.\n")

        DispatchQueue.main.async {
            terminal.window?.makeFirstResponder(terminal)
        }

        return terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        context.coordinator.apply(request: request, pendingCommand: pendingCommand, to: nsView)
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        private var lastRequest: SSHSessionRequest?
        private var lastCommandID: UUID?

        func apply(request: SSHSessionRequest?, pendingCommand: PendingCommand?, to terminal: LocalProcessTerminalView) {
            guard request != lastRequest else {
                sendIfNeeded(pendingCommand, to: terminal)
                return
            }

            if terminal.process.running {
                terminal.terminate()
            }

            guard let request else {
                terminal.feed(text: "\n[SSH] Disconnected.\n")
                lastRequest = nil
                return
            }

            lastRequest = request
            terminal.feed(text: "\n[SSH] Connecting to \(request.username)@\(request.host):\(request.port) ...\n")

            let login = "\(request.username)@\(request.host)"
            let args = [
                "-tt",
                "-p", "\(request.port)",
                "-o", "ServerAliveInterval=30",
                "-o", "ServerAliveCountMax=3",
                "-o", "StrictHostKeyChecking=accept-new",
                login
            ]

            terminal.startProcess(executable: "/usr/bin/ssh", args: args)

            DispatchQueue.main.async {
                terminal.window?.makeFirstResponder(terminal)
            }

            sendIfNeeded(pendingCommand, to: terminal)
        }

        private func sendIfNeeded(_ pendingCommand: PendingCommand?, to terminal: LocalProcessTerminalView) {
            guard let pendingCommand else { return }
            guard pendingCommand.id != lastCommandID else { return }
            lastCommandID = pendingCommand.id

            guard terminal.process.running else {
                terminal.feed(text: "[SSH] Not connected. Command ignored.\n")
                return
            }

            terminal.send(txt: pendingCommand.text + "\n")
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            if let exitCode {
                source.feed(text: "\n[SSH] Session ended (exit: \(exitCode)).\n")
            } else {
                source.feed(text: "\n[SSH] Session ended.\n")
            }
        }
    }
}

#else

struct SwiftTermDemoView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("SwiftTerm SSH Demo")
                .font(.headline)
            Text("This demo is configured for macOS SSH mode.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("SwiftTerm SSH")
    }
}

#endif
