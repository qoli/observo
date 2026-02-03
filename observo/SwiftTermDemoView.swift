import SwiftUI
import SwiftTerm
import Foundation
import Combine

#if canImport(AnyLanguageModel)
import AnyLanguageModel
#endif

#if os(macOS)
import AppKit

struct SwiftTermDemoView: View {
    @State private var host = "127.0.0.1"
    @State private var port = "22"
    @State private var username = NSUserName()
    @State private var activeRequest: SSHSessionRequest?
    @State private var commandInput = ""
    @State private var pendingCommand: PendingCommand?

    @AppStorage("llm.analysisPrompt") private var analysisPrompt = """
請根據以下終端紀錄提供精煉分析：
1) 目前狀態摘要
2) 可能錯誤與風險
3) 下一步建議命令（請附上命令）
"""
    @State private var modelResponse = ""
    @State private var modelError: String?
    @State private var isRequestingModel = false
    @State private var showModelResponseSheet = false
    @AppStorage("llm.openaiCompatibleBaseURL") private var openAICompatibleBaseURL = "http://localhost:11434/v1"
    @AppStorage("llm.openaiCompatibleAPIKey") private var openAICompatibleAPIKey = "local"
    @AppStorage("llm.openaiCompatibleModelName") private var openAICompatibleModelName = "qwen3:8b"

    @StateObject private var sessionStore = TerminalSessionStore()
    private let localModelClient = LocalModelClient()

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

            SSHMacTerminalContainer(
                request: activeRequest,
                pendingCommand: pendingCommand,
                sessionStore: sessionStore
            )
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
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    askLocalModel()
                } label: {
                    Label(isRequestingModel ? "Asking..." : "Ask Local Model", systemImage: "sparkles")
                }
                .disabled(isRequestingModel || !sessionStore.hasEvents)

                if isRequestingModel {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .sheet(isPresented: $showModelResponseSheet) {
            modelResponseSheet
        }
        .alert(
            "Local Model Error",
            isPresented: Binding(
                get: { modelError != nil },
                set: { newValue in if !newValue { modelError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(modelError ?? "Unknown error")
        }
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

    private func askLocalModel() {
        let transcript = sessionStore.transcriptForModel(maxEvents: 300, maxCharacters: 12000)
        guard !transcript.isEmpty else {
            modelError = "目前沒有可分析的終端輸出。"
            return
        }

        let prompt = analysisPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            modelError = "提示詞不能為空。"
            return
        }

        isRequestingModel = true
        modelError = nil

        Task {
            do {
                let response = try await localModelClient.ask(
                    prompt: prompt,
                    transcript: transcript,
                    modelName: openAICompatibleModelName,
                    baseURLString: openAICompatibleBaseURL,
                    apiKey: openAICompatibleAPIKey
                )
                await MainActor.run {
                    modelResponse = response
                    showModelResponseSheet = true
                    isRequestingModel = false
                }
            } catch {
                await MainActor.run {
                    modelError = error.localizedDescription
                    isRequestingModel = false
                }
            }
        }
    }

    @ViewBuilder
    private var connectionPanel: some View {
        VStack(spacing: 10) {
            HStack {
                Label("SSH Connection", systemImage: "network")
                    .font(.headline)
                Spacer()
                Label(
                    isConnected ? "Connected" : "Disconnected",
                    systemImage: isConnected ? "checkmark.circle.fill" : "bolt.slash.circle"
                )
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

            HStack(spacing: 10) {
                TextField("OpenAI-Compatible Endpoint", text: $openAICompatibleBaseURL)
                TextField("API Key", text: $openAICompatibleAPIKey)
                    .frame(width: 160)
                TextField("Model", text: $openAICompatibleModelName)
                    .frame(width: 180)
            }
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
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
                    Text("Type a command, then click Send (Cmd+Enter)")
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
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(commandInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    @ViewBuilder
    private var modelResponseSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    TextField("OpenAI-Compatible Endpoint", text: $openAICompatibleBaseURL)
                    TextField("API Key", text: $openAICompatibleAPIKey)
                        .frame(width: 160)
                    TextField("Model", text: $openAICompatibleModelName)
                        .frame(width: 180)
                }
                .textFieldStyle(.roundedBorder)

                TextEditor(text: $analysisPrompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 88)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.secondary.opacity(0.2))
                    }

                ScrollView {
                    Text(modelResponse)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(16)
            .navigationTitle("Model Response")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        showModelResponseSheet = false
                    }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
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

private struct TerminalEvent {
    enum Kind {
        case command(String)
        case stdout(String)
        case stderr(String)
    }

    let kind: Kind
}

@MainActor
private final class TerminalSessionStore: ObservableObject {
    @Published private(set) var hasEvents = false

    private var events: [TerminalEvent] = []
    private let maxStoredEvents = 1200

    func append(_ event: TerminalEvent) {
        let normalized: TerminalEvent?
        switch event.kind {
        case .command(let text):
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            normalized = value.isEmpty ? nil : TerminalEvent(kind: .command(value))
        case .stdout(let text):
            let cleaned = text.cleanedForSemanticLog
            normalized = cleaned.isEmpty ? nil : TerminalEvent(kind: .stdout(cleaned))
        case .stderr(let text):
            let cleaned = text.cleanedForSemanticLog
            normalized = cleaned.isEmpty ? nil : TerminalEvent(kind: .stderr(cleaned))
        }

        guard let normalized else { return }

        events.append(normalized)
        if events.count > maxStoredEvents {
            events.removeFirst(events.count - maxStoredEvents)
        }

        hasEvents = !events.isEmpty

        switch normalized.kind {
        case .command(let value):
            print("[CMD] \(value)")
        case .stdout(let value):
            print("[OUT]\n\(value)")
        case .stderr(let value):
            print("[ERR]\n\(value)")
        }
    }

    func transcriptForModel(maxEvents: Int, maxCharacters: Int) -> String {
        let recent = Array(events.suffix(maxEvents))
        var blocks: [String] = []
        blocks.reserveCapacity(recent.count)

        for event in recent {
            switch event.kind {
            case .command(let value):
                blocks.append("[CMD] \(value)")
            case .stdout(let value):
                blocks.append("[OUT]\n\(value)")
            case .stderr(let value):
                blocks.append("[ERR]\n\(value)")
            }
        }

        let joined = blocks.joined(separator: "\n\n")
        if joined.count <= maxCharacters {
            return joined
        }
        return String(joined.suffix(maxCharacters))
    }
}

private extension String {
    var cleanedForSemanticLog: String {
        var output = self
        let patterns = [
            #"\u{001B}\[[0-?]*[ -/]*[@-~]"#,
            #"\u{001B}\][^\u{0007}]*\u{0007}"#,
            #"\u{001B}\][^\u{001B}]*\u{001B}\\"#
        ]

        for pattern in patterns {
            output = output.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        output = output.replacingOccurrences(of: "\r", with: "")
        output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return output
    }
}

private enum LocalModelClientError: LocalizedError {
    case missingAnyLanguageModel
    case invalidBaseURL

    var errorDescription: String? {
        switch self {
        case .missingAnyLanguageModel:
            return "AnyLanguageModel 尚未集成或不可用。"
        case .invalidBaseURL:
            return "OpenAI 相容端點 URL 無效。"
        }
    }
}

private struct LocalModelClient {
    func ask(prompt: String, transcript: String, modelName: String, baseURLString: String, apiKey: String) async throws -> String {
        #if canImport(AnyLanguageModel)
        guard let baseURL = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw LocalModelClientError.invalidBaseURL
        }

        let token = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = OpenAILanguageModel(
            baseURL: baseURL,
            apiKey: token.isEmpty ? "local" : token,
            model: modelName,
            apiVariant: .chatCompletions
        )
        let session = LanguageModelSession(model: model)

        let mergedPrompt = """
\(prompt)

--- Terminal Transcript ---
\(transcript)
"""

        let options = GenerationOptions(temperature: 0.1, maximumResponseTokens: 1200)
        let response = try await session.respond(to: Prompt(mergedPrompt), options: options)
        return response.content
        #else
        throw LocalModelClientError.missingAnyLanguageModel
        #endif
    }
}

private final class SSHLoggingTerminalView: LocalProcessTerminalView {
    weak var sessionStore: TerminalSessionStore?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        let text = String(decoding: slice, as: UTF8.self)
        guard !text.isEmpty else { return }
        Task { @MainActor in
            sessionStore?.append(TerminalEvent(kind: .stdout(text)))
        }
    }
}

private struct SSHMacTerminalContainer: NSViewRepresentable {
    let request: SSHSessionRequest?
    let pendingCommand: PendingCommand?
    @ObservedObject var sessionStore: TerminalSessionStore

    func makeCoordinator() -> Coordinator {
        Coordinator(sessionStore: sessionStore)
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = SSHLoggingTerminalView(frame: .zero)
        terminal.getTerminal().silentLog = true
        terminal.processDelegate = context.coordinator
        terminal.nativeBackgroundColor = .black
        terminal.nativeForegroundColor = .systemGreen
        terminal.caretColor = .systemGreen
        terminal.sessionStore = sessionStore
        terminal.feed(text: "[SSH] Ready. Fill host/port/user and press Connect.\n")
        return terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        if let loggingTerminal = nsView as? SSHLoggingTerminalView {
            loggingTerminal.sessionStore = sessionStore
        }
        context.coordinator.apply(request: request, pendingCommand: pendingCommand, to: nsView)
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        private var lastRequest: SSHSessionRequest?
        private var lastCommandID: UUID?
        private weak var sessionStore: TerminalSessionStore?

        init(sessionStore: TerminalSessionStore) {
            self.sessionStore = sessionStore
        }

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
            focusTerminal(terminal)
            sendIfNeeded(pendingCommand, to: terminal)
        }

        private func focusTerminal(_ terminal: LocalProcessTerminalView) {
            Task { @MainActor in
                _ = terminal.becomeFirstResponder()
            }
        }

        private func sendIfNeeded(_ pendingCommand: PendingCommand?, to terminal: LocalProcessTerminalView) {
            guard let pendingCommand else { return }
            guard pendingCommand.id != lastCommandID else { return }
            lastCommandID = pendingCommand.id

            guard terminal.process.running else {
                terminal.feed(text: "[SSH] Not connected. Command ignored.\n")
                return
            }

            Task { @MainActor in
                sessionStore?.append(TerminalEvent(kind: .command(pendingCommand.text)))
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
