import Combine
import Foundation
import SwiftTerm
import SwiftUI
import Textual

#if canImport(AnyLanguageModel)
    import AnyLanguageModel
#endif

#if os(macOS)
    import AppKit

    private enum AIChatSettingsDefaults {
        static let analysisPrompt = """
        請根據以下終端紀錄提供精煉分析：
        1) 目前狀態摘要
        2) 可能錯誤與風險
        3) 下一步建議命令（請附上命令）
        """
        static let baseURL = "http://localhost:11434/v1"
        static let apiKey = "local"
        static let modelName = "qwen3:8b"
    }

    struct AppTerminalView: View {
        @ObservedObject var sessionStore: TerminalSessionStore

        private var canConnectSSH: Bool {
            !sessionStore.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !sessionStore.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && Int(sessionStore.port) != nil
        }

        private var defaultLocalShellPath: String {
            let shell = ProcessInfo.processInfo.environment["SHELL"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return shell.isEmpty ? "/bin/zsh" : shell
        }

        private var isConnected: Bool {
            sessionStore.activeRequest != nil
        }

        private var navigationTitleText: String {
            if !sessionStore.terminalTitle.isEmpty {
                return sessionStore.terminalTitle
            }
            if let descriptor = sessionStore.connectionDescriptor {
                return descriptor
            }
            return "Terminal Session"
        }

        var body: some View {
            VStack(spacing: 0) {
                if isConnected {
                    connectedSessionPanel
                } else {
                    connectionPanel
                }
            }
            .navigationTitle(navigationTitleText)
            .navigationSubtitle(sessionStore.currentDirectory ?? "")
            .onReceive(sessionStore.$disconnectRequestID.dropFirst()) { _ in
                guard sessionStore.activeRequest != nil else { return }
                sessionStore.activeRequest = nil
            }
            .onChange(of: sessionStore.activeRequest) { _, newValue in
                sessionStore.setConnected(newValue != nil)
                guard let request = newValue else {
                    sessionStore.resetTerminalContext()
                    return
                }

                switch request {
                case let .ssh(ssh):
                    sessionStore.setConnectionDescriptor("\(ssh.username)@\(ssh.host):\(ssh.port)")
                case let .localShell(local):
                    sessionStore.setConnectionDescriptor(local.displayName)
                }
            }
        }

        private func connect() {
            guard let portValue = Int(sessionStore.port) else { return }
            let cleanHost = sessionStore.host.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanUser = sessionStore.username.trimmingCharacters(in: .whitespacesAndNewlines)
            sessionStore.activeRequest = .ssh(SSHSessionRequest(host: cleanHost, port: portValue, username: cleanUser))
            sessionStore.setConnectionDescriptor("\(cleanUser)@\(cleanHost):\(portValue)")
        }

        private func connectLocalShell() {
            let shellPath = defaultLocalShellPath
            let shellName = URL(fileURLWithPath: shellPath).lastPathComponent
            let displayName = "Local Shell (\(shellName))"
            sessionStore.activeRequest = .localShell(
                LocalShellRequest(
                    executable: shellPath,
                    args: ["-l"],
                    displayName: displayName
                )
            )
            sessionStore.setConnectionDescriptor(displayName)
        }

        private func sendCommand() {
            let trimmed = sessionStore.commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            sessionStore.pendingCommand = PendingCommand(text: trimmed)
            sessionStore.commandInput = ""
        }

        private func printTerminalPlainText() {
            guard
                let terminal = TerminalHostViewController.visibleTerminal
            else {
                print("[Terminal Plain Text] No visible terminal buffer.")
                return
            }

            let data = terminal.getTerminal().getBufferAsData()
            guard
                let raw = String(data: data, encoding: .utf8)
            else {
                print("[Terminal Plain Text] No visible terminal buffer.")
                return
            }

            let plain = raw.strippingANSIEscapeCodes
            print("[Terminal Plain Text]\n\(plain)")
        }

        @ViewBuilder
        private var connectionPanel: some View {
            VStack {
                HStack {
                    Label("Connection", systemImage: "network")
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
                    TextField("Host", text: $sessionStore.host)
                    TextField("Port", text: $sessionStore.port)
                    TextField("Username", text: $sessionStore.username)
                }
                .textFieldStyle(.roundedBorder)
                .controlSize(.regular)

                Spacer()

                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button("Local Shell") {
                        connectLocalShell()
                    }
                    .buttonStyle(.bordered)

                    Button("Connect") {
                        connect()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canConnectSSH)
                }
            }
            .padding(12)
        }

        @ViewBuilder
        private var commandComposer: some View {
            VStack(alignment: .leading) {
                ExpandTextField(
                    value: $sessionStore.commandInput,
                    placeholder: "Type command here (Enter newline, Cmd+Enter send)",
                    lineLimit: 3,
                    onCommandEnter: sendCommand
                )

                HStack(spacing: 8) {
                    Button {
                        sendCommand()
                    } label: {
                        Label("Send", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(sessionStore.commandInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        printTerminalPlainText()
                    } label: {
                        Label("Print", systemImage: "printer")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }

        @ViewBuilder
        private var connectedSessionPanel: some View {
            SSHMacTerminalContainer(
                request: sessionStore.activeRequest,
                pendingCommand: sessionStore.pendingCommand,
                sessionStore: sessionStore
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal)

            commandComposer
        }
    }

    struct ExpandTextField: View {
        @Binding var value: String
        let placeholder: String
        let lineLimit: Int
        var onCommandEnter: (() -> Void)?
        @State private var measuredContentHeight: CGFloat = 0

        private var lineHeight: CGFloat {
            let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            return ceil(font.ascender - font.descender + font.leading)
        }

        private var minimumHeight: CGFloat {
            max(44, lineHeight * CGFloat(max(1, lineLimit)) + 16)
        }

        private var maximumHeight: CGFloat {
            lineHeight * 12 + 16
        }

        private var resolvedHeight: CGFloat {
            max(minimumHeight, min(maximumHeight, measuredContentHeight))
        }

        var body: some View {
            ZStack(alignment: .topLeading) {
                ExpandTextViewRepresentable(
                    text: $value,
                    onCommandEnter: onCommandEnter,
                    onHeightChange: { height in
                        measuredContentHeight = height
                    }
                )
                .frame(height: resolvedHeight)

                if value.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            }
        }
    }

    private struct ExpandTextViewRepresentable: NSViewRepresentable {
        @Binding var text: String
        var onCommandEnter: (() -> Void)?
        var onHeightChange: (CGFloat) -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(text: $text, onHeightChange: onHeightChange)
        }

        func makeNSView(context: Context) -> NSScrollView {
            let scrollView = NSScrollView()
            scrollView.drawsBackground = false
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.borderType = .noBorder

            let textView = CommandTextView()
            textView.delegate = context.coordinator
            textView.commandEnterHandler = onCommandEnter
            textView.isRichText = false
            textView.importsGraphics = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.allowsUndo = true
            textView.backgroundColor = .clear
            textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            textView.textContainerInset = NSSize(width: 6, height: 6)
            textView.isHorizontallyResizable = false
            textView.isVerticallyResizable = true
            textView.autoresizingMask = [.width]
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
            textView.string = text

            scrollView.documentView = textView
            context.coordinator.reportHeightIfNeeded(for: textView)
            return scrollView
        }

        func updateNSView(_ scrollView: NSScrollView, context: Context) {
            guard let textView = scrollView.documentView as? CommandTextView else { return }
            textView.commandEnterHandler = onCommandEnter
            if textView.string != text {
                textView.string = text
                context.coordinator.reportHeightIfNeeded(for: textView)
            }
            context.coordinator.onHeightChange = onHeightChange
        }

        final class Coordinator: NSObject, NSTextViewDelegate {
            private var text: Binding<String>
            var onHeightChange: (CGFloat) -> Void
            private var lastHeight: CGFloat = 0

            init(text: Binding<String>, onHeightChange: @escaping (CGFloat) -> Void) {
                self.text = text
                self.onHeightChange = onHeightChange
            }

            func textDidChange(_ notification: Notification) {
                guard let textView = notification.object as? NSTextView else { return }
                text.wrappedValue = textView.string
                reportHeightIfNeeded(for: textView)
            }

            func reportHeightIfNeeded(for textView: NSTextView) {
                let contentHeight = measuredHeight(for: textView)
                guard abs(contentHeight - lastHeight) > 0.5 else { return }
                lastHeight = contentHeight
                DispatchQueue.main.async { [onHeightChange] in
                    onHeightChange(contentHeight)
                }
            }

            private func measuredHeight(for textView: NSTextView) -> CGFloat {
                guard let layoutManager = textView.layoutManager,
                      let textContainer = textView.textContainer
                else {
                    return 44
                }

                layoutManager.ensureLayout(for: textContainer)
                let usedRect = layoutManager.usedRect(for: textContainer)
                let inset = textView.textContainerInset.height * 2
                let height = ceil(usedRect.height + inset)
                return max(44, height)
            }
        }
    }

    private final class CommandTextView: NSTextView {
        var commandEnterHandler: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            let isReturn = event.keyCode == 36 || event.keyCode == 76
            let commandPressed = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
            if isReturn, commandPressed {
                commandEnterHandler?()
                return
            }
            super.keyDown(with: event)
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
        @AppStorage("inspector.selectedPane") private var selectedPane: InspectorPane = .aiChat

        var body: some View {
            VStack(spacing: 0) {
                Picker("Inspector", selection: $selectedPane) {
                    ForEach(InspectorPane.allCases) { pane in
                        Text(pane.title).tag(pane)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch selectedPane {
                case .aiChat:
                    AIChatDetailView(sessionStore: sessionStore)
                case .diff:
                    DiffPlaceholderView()
                }
            }
        }
    }

    struct AIChatDetailView: View {
        @ObservedObject var sessionStore: TerminalSessionStore

        @AppStorage("llm.analysisPrompt") private var analysisPrompt = AIChatSettingsDefaults.analysisPrompt
        @AppStorage("llm.openaiCompatibleBaseURL") private var openAICompatibleBaseURL = AIChatSettingsDefaults.baseURL
        @AppStorage("llm.openaiCompatibleAPIKey") private var openAICompatibleAPIKey = AIChatSettingsDefaults.apiKey
        @AppStorage("llm.openaiCompatibleModelName") private var openAICompatibleModelName = AIChatSettingsDefaults.modelName

        @State private var modelResponse = ""
        @State private var modelError: String?
        @State private var isRequestingModel = false

        private let localModelClient = LocalModelClient()

        var body: some View {
            VStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(openAICompatibleModelName) @ \(openAICompatibleBaseURL)")
                        .font(.caption)
                        .lineLimit(1)
                }
                .padding(.all, 0)

                HStack {
                    Button {
                        askModel()
                    } label: {
                        Label(isRequestingModel ? "Asking..." : "Ask Model", systemImage: "sparkles")
                    }
                    .disabled(isRequestingModel)

                    if isRequestingModel {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Spacer()

                    SettingsLink {
                        Text("Settings...")
                    }
                }

                Divider()

                ScrollView {
                    StructuredText(markdown: modelResponse.isEmpty ? "No response yet." : modelResponse)
                        .textual.textSelection(.enabled)
                        .textual.structuredTextStyle(.gitHub)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
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
            let transcript = currentTerminalPlainText(maxCharacters: 12000)
            guard !transcript.isEmpty else {
                modelError = "目前沒有可分析的終端純文本輸出。"
                return
            }

            let prompt = analysisPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty else {
                modelError = "提示詞不能為空。"
                return
            }

            let fullPrompt = """
            \(prompt)

            --- Terminal Transcript ---
            \(transcript)
            """
            print("[AskModel Prompt]\n\(fullPrompt)")

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

        private func currentTerminalPlainText(maxCharacters: Int) -> String {
            guard
                let terminal = TerminalHostViewController.visibleTerminal
            else {
                return ""
            }

            let data = terminal.getTerminal().getBufferAsData()
            guard let raw = String(data: data, encoding: .utf8) else {
                return ""
            }

            let plain = raw.strippingANSIEscapeCodes.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !plain.isEmpty else { return "" }
            if plain.count <= maxCharacters {
                return plain
            }
            return String(plain.suffix(maxCharacters))
        }
    }

    struct AppSettingsView: View {
        @AppStorage("llm.analysisPrompt") private var analysisPrompt = AIChatSettingsDefaults.analysisPrompt
        @AppStorage("llm.openaiCompatibleBaseURL") private var openAICompatibleBaseURL = AIChatSettingsDefaults.baseURL
        @AppStorage("llm.openaiCompatibleAPIKey") private var openAICompatibleAPIKey = AIChatSettingsDefaults.apiKey
        @AppStorage("llm.openaiCompatibleModelName") private var openAICompatibleModelName = AIChatSettingsDefaults.modelName

        var body: some View {
            Form {
                Section("AI Chat") {
                    TextField("OpenAI-Compatible Endpoint", text: $openAICompatibleBaseURL)
                    SecureField("API Key", text: $openAICompatibleAPIKey)
                    TextField("Model", text: $openAICompatibleModelName)
                }

                Section("Prompt") {
                    TextEditor(text: $analysisPrompt)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 180)
                }
            }
            .formStyle(.grouped)
            .padding(16)
            .frame(minWidth: 620, minHeight: 460)
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

    struct SSHSessionRequest: Equatable {
        let host: String
        let port: Int
        let username: String
    }

    struct LocalShellRequest: Equatable {
        let executable: String
        let args: [String]
        let displayName: String
    }

    enum TerminalSessionRequest: Equatable {
        case ssh(SSHSessionRequest)
        case localShell(LocalShellRequest)
    }

    struct PendingCommand: Equatable {
        let id = UUID()
        let text: String
    }

    @MainActor
    final class TerminalSessionStore: ObservableObject {
        @Published var host = "127.0.0.1"
        @Published var port = "22"
        @Published var username = NSUserName()
        @Published var activeRequest: TerminalSessionRequest?
        @Published var commandInput = ""
        @Published var pendingCommand: PendingCommand?

        @Published private(set) var isConnected = false
        @Published private(set) var terminalTitle = ""
        @Published private(set) var currentDirectory: String?
        @Published private(set) var connectionDescriptor: String?
        @Published var disconnectRequestID = UUID()

        func setConnected(_ connected: Bool) {
            isConnected = connected
        }

        func setConnectionDescriptor(_ descriptor: String?) {
            let trimmed = descriptor?.trimmingCharacters(in: .whitespacesAndNewlines)
            connectionDescriptor = (trimmed?.isEmpty == false) ? trimmed : nil
        }

        func setTerminalTitle(_ title: String) {
            terminalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func setCurrentDirectory(_ directory: String?) {
            currentDirectory = directory?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func resetTerminalContext() {
            terminalTitle = ""
            currentDirectory = nil
            connectionDescriptor = nil
            pendingCommand = nil
        }

        func requestDisconnect() {
            disconnectRequestID = UUID()
        }
    }

    private extension String {
        var strippingANSIEscapeCodes: String {
            var output = self
            let patterns = [
                #"\u{001B}\[[0-?]*[ -/]*[@-~]"#,
                #"\u{001B}\][^\u{0007}]*\u{0007}"#,
                #"\u{001B}\][^\u{001B}]*\u{001B}\\"#,
            ]

            for pattern in patterns {
                output = output.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            }

            return output.replacingOccurrences(of: "\r", with: "")
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
        private var appliedPaletteStyle: NSAppearance.Name?

        func applySystemPalette() {
            let style = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) ?? .aqua
            guard style != appliedPaletteStyle else { return }
            appliedPaletteStyle = style
            let pair = TerminalPalette.palette(for: style)
            let isDark = (style == .darkAqua)

            setColors(
                foreground: isDark ? pair.darkFG : pair.lightFG,
                background: isDark ? pair.darkBG : pair.lightBG,
                cursor: .white,
                selection: .selectedTextBackgroundColor,
                palette: isDark ? pair.dark : pair.light
            )
        }

        private func setColors(
            foreground: NSColor,
            background: NSColor,
            cursor: NSColor,
            selection: NSColor,
            palette: [NSColor]
        ) {
            guard palette.count == 16 else { return }

            nativeForegroundColor = foreground
            nativeBackgroundColor = background
            caretColor = cursor
            selectedTextBackgroundColor = selection
            installColors(palette.map(\.terminalColorValue))
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applySystemPalette()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            applySystemPalette()
        }

        override func dataReceived(slice: ArraySlice<UInt8>) {
            // Semantic event capture is disabled; keep the fast path focused on terminal rendering.
            feed(byteArray: slice)
        }
    }

    private final class TerminalHostViewController: NSViewController {
        weak static var visibleTerminal: SSHLoggingTerminalView?

        let terminalView: SSHLoggingTerminalView
        private var scrollWheelMonitor: Any?

        init(terminalView: SSHLoggingTerminalView) {
            self.terminalView = terminalView
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func loadView() {
            view = NSView()
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            terminalView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(terminalView)
            NSLayoutConstraint.activate([
                terminalView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                terminalView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                terminalView.topAnchor.constraint(equalTo: view.topAnchor),
                terminalView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }

        override func viewDidAppear() {
            super.viewDidAppear()
            TerminalHostViewController.visibleTerminal = terminalView
            terminalView.applySystemPalette()
            installScrollWheelBridgeIfNeeded()
            focusTerminalInput()
        }

        override func viewWillDisappear() {
            super.viewWillDisappear()
            removeScrollWheelBridge()
            if TerminalHostViewController.visibleTerminal === terminalView {
                TerminalHostViewController.visibleTerminal = nil
            }
        }

        deinit {
            removeScrollWheelBridge()
        }

        func focusTerminalInput() {
            if let window = view.window {
                window.makeFirstResponder(terminalView)
            } else {
                _ = terminalView.becomeFirstResponder()
            }
        }

        private func installScrollWheelBridgeIfNeeded() {
            guard scrollWheelMonitor == nil else { return }

            scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                guard let window = self.view.window, event.window === window else { return event }

                let location = self.terminalView.convert(event.locationInWindow, from: nil)
                guard self.terminalView.bounds.contains(location) else { return event }

                // Match MacTerminal behavior but support devices that only provide scrollingDeltaY.
                let rawDelta = event.deltaY != 0 ? event.deltaY : event.scrollingDeltaY
                guard rawDelta != 0 else { return event }

                let velocity = self.scrollingVelocity(for: rawDelta, precise: event.hasPreciseScrollingDeltas)
                if rawDelta > 0 {
                    self.terminalView.scrollUp(lines: velocity)
                } else {
                    self.terminalView.scrollDown(lines: velocity)
                }
                return nil
            }
        }

        private func removeScrollWheelBridge() {
            if let scrollWheelMonitor {
                NSEvent.removeMonitor(scrollWheelMonitor)
                self.scrollWheelMonitor = nil
            }
        }

        private func scrollingVelocity(for delta: CGFloat, precise: Bool) -> Int {
            let value = abs(delta)
            if precise {
                if value > 12 { return max(terminalView.getTerminal().rows, 20) }
                if value > 6 { return 10 }
                if value > 2 { return 3 }
                return 1
            }

            let intValue = Int(value)
            if intValue > 9 { return max(terminalView.getTerminal().rows, 20) }
            if intValue > 5 { return 10 }
            if intValue > 1 { return 3 }
            return 1
        }
    }

    enum TerminalCommandBridge {
        static var hasActiveTerminal: Bool {
            TerminalHostViewController.visibleTerminal != nil
        }

        static func softReset() {
            TerminalHostViewController.visibleTerminal?.getTerminal().softReset()
        }

        static func hardReset() {
            TerminalHostViewController.visibleTerminal?.getTerminal().resetToInitialState()
        }

        static func selectAll() {
            TerminalHostViewController.visibleTerminal?.selectAll()
        }

        static func clearSelection() {
            TerminalHostViewController.visibleTerminal?.selectNone()
        }

        static func sendEscape() {
            guard let terminal = TerminalHostViewController.visibleTerminal else { return }
            terminal.send(data: EscapeSequences.cmdEsc[...])
        }

        static func sendFunctionKey(_ key: Int) {
            guard (1 ... EscapeSequences.cmdF.count).contains(key) else { return }
            guard let terminal = TerminalHostViewController.visibleTerminal else { return }
            terminal.send(data: EscapeSequences.cmdF[key - 1][...])
        }
    }

    private struct SSHMacTerminalContainer: NSViewControllerRepresentable {
        let request: TerminalSessionRequest?
        let pendingCommand: PendingCommand?
        @ObservedObject var sessionStore: TerminalSessionStore

        func makeCoordinator() -> Coordinator {
            Coordinator(sessionStore: sessionStore)
        }

        func makeNSViewController(context: Context) -> TerminalHostViewController {
            let terminal = SSHLoggingTerminalView(frame: .zero)
            terminal.getTerminal().silentLog = true
            terminal.getTerminal().setCursorStyle(.steadyBlock)
            // Faster for tmux-like full-screen redraws; keeps glyph rendering on the platform text stack.
            terminal.customBlockGlyphs = false
            terminal.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            terminal.applySystemPalette()
            terminal.feed(text: "[Terminal] Ready. Connect SSH or start Local Shell.\r\n")
            let controller = TerminalHostViewController(terminalView: terminal)
            context.coordinator.bind(sessionStore: sessionStore, terminal: terminal, hostController: controller)
            return controller
        }

        func updateNSViewController(_ controller: TerminalHostViewController, context: Context) {
            controller.terminalView.applySystemPalette()
            context.coordinator.bind(sessionStore: sessionStore, terminal: controller.terminalView, hostController: controller)
            context.coordinator.apply(request: request, pendingCommand: pendingCommand)
        }

        final class Coordinator {
            private let ioBridge = SSHIOBridge()
            private weak var hostController: TerminalHostViewController?
            private weak var terminalView: SSHLoggingTerminalView?

            init(sessionStore: TerminalSessionStore) {
                ioBridge.bind(sessionStore: sessionStore)
            }

            func bind(
                sessionStore: TerminalSessionStore,
                terminal: SSHLoggingTerminalView,
                hostController: TerminalHostViewController
            ) {
                self.hostController = hostController
                terminalView = terminal
                ioBridge.bind(sessionStore: sessionStore)
                terminal.processDelegate = ioBridge
            }

            func apply(request: TerminalSessionRequest?, pendingCommand: PendingCommand?) {
                guard let terminal = terminalView else { return }
                ioBridge.apply(
                    request: request,
                    pendingCommand: pendingCommand,
                    to: terminal,
                    focusHandler: { [weak hostController] in
                        hostController?.focusTerminalInput()
                    }
                )
            }
        }
    }

    private final class SSHIOBridge: NSObject, LocalProcessTerminalViewDelegate {
        private var lastRequest: TerminalSessionRequest?
        private var lastCommandID: UUID?
        private weak var sessionStore: TerminalSessionStore?

        func bind(sessionStore: TerminalSessionStore) {
            self.sessionStore = sessionStore
        }

        func apply(
            request: TerminalSessionRequest?,
            pendingCommand: PendingCommand?,
            to terminal: LocalProcessTerminalView,
            focusHandler: @escaping () -> Void
        ) {
            guard request != lastRequest else {
                sendIfNeeded(pendingCommand, to: terminal)
                return
            }

            if terminal.process.running {
                terminal.terminate()
            }

            guard let request else {
                let prefix = sessionPrefix(for: lastRequest)
                terminal.feed(text: "\r\n\(prefix) Disconnected.\r\n")
                lastRequest = nil
                Task { @MainActor in
                    sessionStore?.resetTerminalContext()
                }
                return
            }

            lastRequest = request

            switch request {
            case let .ssh(ssh):
                terminal.feed(text: "\r\n[SSH] Connecting to \(ssh.username)@\(ssh.host):\(ssh.port) ...\r\n")

                let login = "\(ssh.username)@\(ssh.host)"
                let args = [
                    "-tt",
                    "-p", "\(ssh.port)",
                    "-o", "ServerAliveInterval=30",
                    "-o", "ServerAliveCountMax=3",
                    "-o", "StrictHostKeyChecking=accept-new",
                    login,
                ]

                terminal.startProcess(executable: "/usr/bin/ssh", args: args)
            case let .localShell(local):
                terminal.feed(text: "\r\n[Local Shell] Starting \(local.displayName)...\r\n")
                terminal.startProcess(executable: local.executable, args: local.args)
            }

            focusHandler()
            sendIfNeeded(pendingCommand, to: terminal)
        }

        private func sessionPrefix(for request: TerminalSessionRequest?) -> String {
            guard let request else { return "[Terminal]" }
            switch request {
            case .ssh:
                return "[SSH]"
            case .localShell:
                return "[Local Shell]"
            }
        }

        private func sendIfNeeded(_ pendingCommand: PendingCommand?, to terminal: LocalProcessTerminalView) {
            guard let pendingCommand else { return }
            guard pendingCommand.id != lastCommandID else { return }

            guard terminal.process.running else {
                return
            }

            lastCommandID = pendingCommand.id
            Task { @MainActor in
                sessionStore?.pendingCommand = nil
            }
            terminal.send(txt: pendingCommand.text + "\n")
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
            // LocalProcessTerminalView already updates PTY winsize before this callback.
            _ = (newCols, newRows)
        }

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            Task { @MainActor in
                sessionStore?.setTerminalTitle(title)
            }
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            Task { @MainActor in
                sessionStore?.setCurrentDirectory(directory)
            }
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            let prefix = sessionPrefix(for: lastRequest)
            lastRequest = nil
            Task { @MainActor in
                sessionStore?.activeRequest = nil
                sessionStore?.setConnected(false)
                sessionStore?.resetTerminalContext()
            }
            if let exitCode {
                source.feed(text: "\r\n\(prefix) Session ended (exit: \(exitCode)).\r\n")
            } else {
                source.feed(text: "\r\n\(prefix) Session ended.\r\n")
            }
        }
    }

    private extension NSColor {
        nonisolated var terminalColorValue: SwiftTerm.Color {
            guard let color = usingColorSpace(.deviceRGB) else {
                return SwiftTerm.Color(red: 0, green: 0, blue: 0)
            }

            var red: CGFloat = 0.0
            var green: CGFloat = 0.0
            var blue: CGFloat = 0.0
            var alpha: CGFloat = 1.0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

            return SwiftTerm.Color(
                red: UInt16(red * 65535.0),
                green: UInt16(green * 65535.0),
                blue: UInt16(blue * 65535.0)
            )
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
        @Published private(set) var terminalTitle = ""
        @Published private(set) var currentDirectory: String?
        @Published private(set) var connectionDescriptor: String?
        @Published var disconnectRequestID = UUID()

        func setConnected(_ connected: Bool) {
            isConnected = connected
        }

        func setConnectionDescriptor(_ descriptor: String?) {
            connectionDescriptor = descriptor
        }

        func setTerminalTitle(_ title: String) {
            terminalTitle = title
        }

        func setCurrentDirectory(_ directory: String?) {
            currentDirectory = directory
        }

        func resetTerminalContext() {
            terminalTitle = ""
            currentDirectory = nil
            connectionDescriptor = nil
        }

        func requestDisconnect() {
            disconnectRequestID = UUID()
        }
    }

#endif
