//
//  ContentView.swift
//  observo
//
//  Created by 黃佁媛 on 2/3/26.
//

import SwiftUI

#if os(macOS)
    private struct SidebarSession: Identifiable, Hashable {
        let id: UUID
        var title: String
        let symbol: String

        init(id: UUID = UUID(), title: String, symbol: String = "terminal") {
            self.id = id
            self.title = title
            self.symbol = symbol
        }
    }

    private struct SessionSidebarRow: View {
        let baseTitle: String
        let symbol: String
        @ObservedObject var sessionStore: TerminalSessionStore

        private var displayTitle: String {
            if !sessionStore.terminalTitle.isEmpty {
                return sessionStore.terminalTitle
            }
            if let descriptor = sessionStore.connectionDescriptor, !descriptor.isEmpty {
                return descriptor
            }
            return baseTitle
        }

        var body: some View {
            Label(displayTitle, systemImage: symbol)
                .lineLimit(1)
        }
    }
#endif

struct ContentView: View {
    #if os(macOS)
        @State private var sessions: [SidebarSession]
        @State private var selectedSessionID: SidebarSession.ID?
        @State private var sessionStores: [SidebarSession.ID: TerminalSessionStore]
        @AppStorage("ui.showInspector") private var showInspector = true
    #endif

    #if os(macOS)
        init() {
            let initial = SidebarSession(title: "SSH Session 1")
            _sessions = State(initialValue: [initial])
            _selectedSessionID = State(initialValue: initial.id)
            _sessionStores = State(initialValue: [initial.id: TerminalSessionStore()])
        }
    #endif

    var body: some View {
        #if os(macOS)
            NavigationSplitView {
                List(sessions, selection: $selectedSessionID) { session in
                    Group {
                        if let store = sessionStores[session.id] {
                            SessionSidebarRow(baseTitle: session.title, symbol: session.symbol, sessionStore: store)
                        } else {
                            Label(session.title, systemImage: session.symbol)
                        }
                    }
                    .tag(session.id)
                }
                .navigationTitle("Sessions")
                .listStyle(.sidebar)
            } detail: {
                sessionContent
            }
            .inspector(isPresented: $showInspector) {
                inspectorContent
            }
            .toolbar {
                topLevelToolbar
            }
        #else
            NavigationStack {
                SwiftTermDemoView()
            }
        #endif
    }

    #if os(macOS)
        private var selectedSessionStore: TerminalSessionStore? {
            guard let selectedSessionID else { return nil }
            return sessionStores[selectedSessionID]
        }

        @ViewBuilder
        private var sessionContent: some View {
            if let selectedSessionStore {
                AppTerminalView(sessionStore: selectedSessionStore)
            } else {
                ContentUnavailableView("Select a Session", systemImage: "sidebar.left")
            }
        }

        @ViewBuilder
        private var inspectorContent: some View {
            if let selectedSessionStore {
                SessionInspectorView(sessionStore: selectedSessionStore)
            } else {
                ContentUnavailableView("No Inspector", systemImage: "sidebar.right")
            }
        }

        @ToolbarContentBuilder
        private var topLevelToolbar: some ToolbarContent {
            ToolbarItem(placement: .primaryAction) {
                Button("New Session", systemImage: "plus.rectangle.on.rectangle") {
                    createSession()
                }
                .help("Create a new SSH session")
            }

            ToolbarItem(placement: .primaryAction) {
                Button("Disconnect", systemImage: "bolt.slash") {
                    selectedSessionStore?.requestDisconnect()
                }
                .disabled(selectedSessionStore?.isConnected != true)
                .help("Disconnect SSH session")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showInspector.toggle()
                } label: {
                    Label(
                        showInspector ? "Hide Inspector" : "Show Inspector",
                        systemImage: showInspector ? "sidebar.trailing" : "sidebar.right"
                    )
                }
                .help(showInspector ? "Hide Inspector" : "Show Inspector")
            }
        }

        private func createSession() {
            let index = sessions.count + 1
            let session = SidebarSession(title: "SSH Session \(index)")
            sessions.append(session)
            sessionStores[session.id] = TerminalSessionStore()
            selectedSessionID = session.id
        }
    #endif
}

#Preview {
    ContentView()
}
