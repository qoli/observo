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
    @State private var isInspectorVisible = true
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
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
        } content: {
            Group {
                switch selectedSession {
                case .primary:
                    SwiftTermDemoView(sessionStore: primarySessionStore)
                case .none:
                    ContentUnavailableView("Select a Session", systemImage: "sidebar.left")
                }
            }
            .navigationSplitViewColumnWidth(min: 560, ideal: 760)
        } detail: {
            Group {
                if isInspectorVisible {
                    switch selectedSession {
                    case .primary:
                        SessionInspectorView(sessionStore: primarySessionStore)
                    case .none:
                        ContentUnavailableView("No Inspector", systemImage: "sidebar.right")
                    }
                } else {
                    Color.clear
                }
            }
            .navigationSplitViewColumnWidth(
                min: isInspectorVisible ? 300 : 0,
                ideal: isInspectorVisible ? 360 : 0,
                max: isInspectorVisible ? 460 : 1
            )
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isInspectorVisible.toggle()
                } label: {
                    Label(
                        isInspectorVisible ? "Hide Inspector" : "Show Inspector",
                        systemImage: isInspectorVisible ? "sidebar.trailing" : "sidebar.right"
                    )
                }
                .help(isInspectorVisible ? "Hide Inspector" : "Show Inspector")
            }
        }
#else
        NavigationStack {
            SwiftTermDemoView()
        }
#endif
    }

}

#Preview {
    ContentView()
}
