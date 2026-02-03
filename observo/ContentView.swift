//
//  ContentView.swift
//  observo
//
//  Created by 黃佁媛 on 2/3/26.
//

import SwiftUI

#if os(macOS)
private enum SidebarSession: String, CaseIterable, Identifiable {
    case primary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .primary:
            return "SSH Session"
        }
    }

    var symbol: String {
        switch self {
        case .primary:
            return "terminal"
        }
    }
}
#endif

struct ContentView: View {
#if os(macOS)
    @State private var selectedSession: SidebarSession? = .primary
    @StateObject private var primarySessionStore = TerminalSessionStore()
    @State private var showInspector = true
#endif

    var body: some View {
#if os(macOS)
        NavigationSplitView {
            List(SidebarSession.allCases, selection: $selectedSession) { session in
                Label(session.title, systemImage: session.symbol)
                    .tag(session)
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
    @ViewBuilder
    private var sessionContent: some View {
        switch selectedSession {
        case .primary:
            SwiftTermDemoView(sessionStore: primarySessionStore)
        case .none:
            ContentUnavailableView("Select a Session", systemImage: "sidebar.left")
        }
    }

    @ViewBuilder
    private var inspectorContent: some View {
        switch selectedSession {
        case .primary:
            SessionInspectorView(sessionStore: primarySessionStore)
        case .none:
            ContentUnavailableView("No Inspector", systemImage: "sidebar.right")
        }
    }

    @ToolbarContentBuilder
    private var topLevelToolbar: some ToolbarContent {
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
#endif
}

#Preview {
    ContentView()
}
