//
//  ContentView.swift
//  observo
//
//  Created by 黃佁媛 on 2/3/26.
//

import SwiftUI

struct ContentView: View {
    @State private var selection: DemoItem? = .ssh

    var body: some View {
        NavigationSplitView {
            List(DemoItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.symbol)
                    .tag(item)
            }
            .navigationTitle("Demos")
            .listStyle(.sidebar)
        } detail: {
            switch selection {
            case .ssh:
                NavigationStack {
                    SwiftTermDemoView()
                }
            case .none:
                ContentUnavailableView("Select a Demo", systemImage: "sidebar.left")
            }
        }
    }
}

private enum DemoItem: String, CaseIterable, Identifiable {
    case ssh

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ssh:
            return "SwiftTerm SSH"
        }
    }

    var symbol: String {
        switch self {
        case .ssh:
            return "terminal"
        }
    }
}

#Preview {
    ContentView()
}
