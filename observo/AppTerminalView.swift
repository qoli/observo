import Combine
import Foundation
import SwiftTerm
import SwiftUI

#if canImport(AnyLanguageModel)
    import AnyLanguageModel
#endif

#if os(macOS)
    import AppKit

    struct AppTerminalView: View {
        @ObservedObject var sessionStore: TerminalSessionStore

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

        private var sessionTitle: String {
            guard let request = activeRequest else { return "SSH Session" }
            return "\(request.username)@\(request.host):\(request.port)"
        }

        var body: some View {
            VStack(spacing: 14) {
                if isConnected {
                    connectedSessionPanel
                } else {
                    connectionPanel
                }
            }
            .padding(12)
            .navigationTitle(sessionTitle)
            .onReceive(sessionStore.$disconnectRequestID.dropFirst()) { _ in
                guard activeRequest != nil else { return }
                activeRequest = nil
            }
            .onChange(of: activeRequest) { _, newValue in
                sessionStore.setConnected(newValue != nil)
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

                VStack(alignment: .leading, spacing: 10) {
                    TextField("Host", text: $host)
                    TextField("Port", text: $port)
                    TextField("Username", text: $username)
                }
                .textFieldStyle(.roundedBorder)
                .controlSize(.regular)

                Spacer()

                HStack {
                    Spacer(minLength: 0)
                    Button("Connect") {
                        connect()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canConnect)
                }
            }
            .padding(12)
        }

        @ViewBuilder
        private var commandComposer: some View {
            VStack(alignment: .leading, spacing: 10) {
                ExpandTextField(
                    value: $commandInput,
                    placeholder: "Type command here (Enter newline, Cmd+Enter send)",
                    lineLimit: 3
                )

                Button {
                    sendCommand()
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(commandInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }

        @ViewBuilder
        private var connectedSessionPanel: some View {
            SSHMacTerminalContainer(
                request: activeRequest,
                pendingCommand: pendingCommand,
                sessionStore: sessionStore
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            commandComposer
        }
    }

    struct ExpandTextField: View {
        @Binding var value: String
        let placeholder: String
        let lineLimit: Int
        @FocusState private var isFocused: Bool

        var body: some View {
            TextField(placeholder, text: $value, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .lineLimit(lineLimit, reservesSpace: true)
                .focused($isFocused)
                .onSubmit(of: .text) {
                    value.append("\n")
                    isFocused = true
                }
        }
    }

    enum InspectorPane: String, CaseIterable, Identifiable {
        case aiChat
        case diff

        var id: String { rawValue }

        var title: String {
            switch self {
            case .aiChat:
                return "AI Chat"
            case .diff:
                return "Diff"
            }
        }
    }

    struct SessionInspectorView: View {
        @ObservedObject var sessionStore: TerminalSessionStore
        @State private var selectedPane: InspectorPane = .aiChat

        var body: some View {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Inspector")
                        .font(.headline)
                    Text("\(sessionStore.eventCount) events captured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Picker("Inspector", selection: $selectedPane) {
                    ForEach(InspectorPane.allCases) { pane in
                        Text(pane.title).tag(pane)
                    }
                }
                .pickerStyle(.segmented)

                switch selectedPane {
                case .aiChat:
                    AIChatDetailView(sessionStore: sessionStore)
                case .diff:
                    DiffPlaceholderView()
                }
            }
            .padding(12)
        }
    }

    struct AIChatDetailView: View {
        @ObservedObject var sessionStore: TerminalSessionStore

        @AppStorage("llm.analysisPrompt") private var analysisPrompt = """
        請根據以下終端紀錄提供精煉分析：
        1) 目前狀態摘要
        2) 可能錯誤與風險
        3) 下一步建議命令（請附上命令）
        """
        @AppStorage("llm.openaiCompatibleBaseURL") private var openAICompatibleBaseURL = "http://localhost:11434/v1"
        @AppStorage("llm.openaiCompatibleAPIKey") private var openAICompatibleAPIKey = "local"
        @AppStorage("llm.openaiCompatibleModelName") private var openAICompatibleModelName = "qwen3:8b"

        @State private var modelResponse = ""
        @State private var modelError: String?
        @State private var isRequestingModel = false

        private let localModelClient = LocalModelClient()

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("AI Chat")
                    .font(.headline)

                Group {
                    TextField("OpenAI-Compatible Endpoint", text: $openAICompatibleBaseURL)
                    TextField("API Key", text: $openAICompatibleAPIKey)
                    TextField("Model", text: $openAICompatibleModelName)
                }
                .textFieldStyle(.roundedBorder)

                Text("Prompt")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $analysisPrompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 110)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.secondary.opacity(0.2))
                    }

                HStack {
                    Button {
                        askModel()
                    } label: {
                        Label(isRequestingModel ? "Asking..." : "Ask Model", systemImage: "sparkles")
                    }
                    .disabled(isRequestingModel || !sessionStore.hasEvents)

                    if isRequestingModel {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Spacer()
                }

                ScrollView {
                    Text(modelResponse.isEmpty ? "No response yet." : modelResponse)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

        private func askModel() {
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
    }

    struct DiffPlaceholderView: View {
        var body: some View {
            VStack(spacing: 10) {
                Image(systemName: "rectangle.split.3x1")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Diff View")
                    .font(.headline)
                Text("Not implemented yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

    struct TerminalEvent {
        enum Kind {
            case command(String)
            case stdout(String)
            case stderr(String)
        }

        let kind: Kind
    }

    @MainActor
    final class TerminalSessionStore: ObservableObject {
        @Published private(set) var hasEvents = false
        @Published private(set) var eventCount = 0
        @Published private(set) var isConnected = false
        @Published var disconnectRequestID = UUID()

        private var events: [TerminalEvent] = []
        private let maxStoredEvents = 1200

        func append(_ event: TerminalEvent) {
            let normalized: TerminalEvent?
            switch event.kind {
            case let .command(text):
                let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                normalized = value.isEmpty ? nil : TerminalEvent(kind: .command(value))
            case let .stdout(text):
                let cleaned = text.cleanedForSemanticLog
                normalized = cleaned.isEmpty ? nil : TerminalEvent(kind: .stdout(cleaned))
            case let .stderr(text):
                let cleaned = text.cleanedForSemanticLog
                normalized = cleaned.isEmpty ? nil : TerminalEvent(kind: .stderr(cleaned))
            }

            guard let normalized else { return }

            events.append(normalized)
            if events.count > maxStoredEvents {
                events.removeFirst(events.count - maxStoredEvents)
            }

            hasEvents = !events.isEmpty
            eventCount = events.count

            switch normalized.kind {
            case let .command(value):
                print("[CMD] \(value)")
            case let .stdout(value):
                print("[OUT]\n\(value)")
            case let .stderr(value):
                print("[ERR]\n\(value)")
            }
        }

        func transcriptForModel(maxEvents: Int, maxCharacters: Int) -> String {
            let recent = Array(events.suffix(maxEvents))
            var blocks: [String] = []
            blocks.reserveCapacity(recent.count)

            for event in recent {
                switch event.kind {
                case let .command(value):
                    blocks.append("[CMD] \(value)")
                case let .stdout(value):
                    blocks.append("[OUT]\n\(value)")
                case let .stderr(value):
                    blocks.append("[ERR]\n\(value)")
                }
            }

            let joined = blocks.joined(separator: "\n\n")
            if joined.count <= maxCharacters {
                return joined
            }
            return String(joined.suffix(maxCharacters))
        }

        func setConnected(_ connected: Bool) {
            isConnected = connected
        }

        func requestDisconnect() {
            disconnectRequestID = UUID()
        }
    }

    private extension String {
        var cleanedForSemanticLog: String {
            var output = self
            let patterns = [
                #"\u{001B}\[[0-?]*[ -/]*[@-~]"#,
                #"\u{001B}\][^\u{0007}]*\u{0007}"#,
                #"\u{001B}\][^\u{001B}]*\u{001B}\\"#,
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
                    login,
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
                Task { @MainActor in
                    sessionStore?.setConnected(false)
                }
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

    struct SessionInspectorView: View {
        var body: some View {
            ContentUnavailableView("Inspector", systemImage: "sidebar.right")
        }
    }

    final class TerminalSessionStore: ObservableObject {
        @Published private(set) var hasEvents = false
        @Published private(set) var eventCount = 0
        @Published private(set) var isConnected = false
        @Published var disconnectRequestID = UUID()

        func setConnected(_ connected: Bool) {
            isConnected = connected
        }

        func requestDisconnect() {
            disconnectRequestID = UUID()
        }
    }

#endif
