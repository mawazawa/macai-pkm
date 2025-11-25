//
//  PKMDashboardView.swift
//  macai-pkm
//
//  Main PKM Dashboard sidebar view
//

import SwiftUI

/// Main PKM Dashboard view for the sidebar
struct PKMDashboardView: View {
    @EnvironmentObject var mcpManager: MCPServerManager
    @State private var searchQuery: String = ""
    @State private var searchResults: [PKMSearchResult] = []
    @State private var isSearching: Bool = false
    @State private var showQuickCapture: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("PKM Dashboard")
                    .font(.headline)

                Spacer()

                Button {
                    showQuickCapture = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
                .help("Quick Capture")
            }

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search all sources...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        performSearch()
                    }

                if isSearching {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .padding(8)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)

            // Source status cards
            VStack(alignment: .leading, spacing: 8) {
                Text("Sources")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(PKMSourceType.allCases, id: \.self) { source in
                        SourceStatusCard(
                            source: source,
                            status: mcpManager.serverStatuses[source] ?? .disconnected
                        )
                    }
                }
            }

            // Search results or recent items
            if !searchResults.isEmpty {
                SearchResultsView(results: searchResults)
            } else {
                RecentItemsView()
            }

            Spacer()
        }
        .padding()
        .sheet(isPresented: $showQuickCapture) {
            QuickCaptureView()
        }
    }

    private func performSearch() {
        guard !searchQuery.isEmpty else { return }

        isSearching = true
        Task {
            let results = await mcpManager.searchAcrossSources(query: searchQuery)
            await MainActor.run {
                searchResults = results
                isSearching = false
            }
        }
    }
}

/// Card showing status of a PKM source
struct SourceStatusCard: View {
    let source: PKMSourceType
    let status: MCPServerStatus

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: source.iconName)
                    .foregroundColor(source.color)

                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }

            Text(source.displayName)
                .font(.caption)

            Text(statusText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var statusColor: Color {
        switch status {
        case .connected: return .green
        case .connecting: return .yellow
        case .error: return .red
        case .disconnected: return .gray
        }
    }

    private var statusText: String {
        switch status {
        case .connected(let count): return "\(count) tools"
        case .connecting: return "Connecting..."
        case .error(let msg): return msg
        case .disconnected: return "Off"
        }
    }
}

/// View showing search results
struct SearchResultsView: View {
    let results: [PKMSearchResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Results")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(results) { result in
                        SearchResultRow(result: result)
                    }
                }
            }
        }
    }
}

/// Single search result row
struct SearchResultRow: View {
    let result: PKMSearchResult

    var body: some View {
        Button {
            // Insert into chat or open URL
            if let url = result.url {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: result.source.iconName)
                    .foregroundColor(result.source.color)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Text(result.snippet)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

/// View showing recent PKM items
struct RecentItemsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("Connect sources to see recent items")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
        }
    }
}

/// Quick capture sheet
struct QuickCaptureView: View {
    @Environment(\.dismiss) var dismiss
    @State private var content: String = ""
    @State private var captureType: CaptureType = .note
    @State private var destination: PKMSourceType = .obsidian

    enum CaptureType: String, CaseIterable {
        case note = "Note"
        case task = "Task"
        case idea = "Idea"
        case contact = "Contact"
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Quick Capture")
                .font(.headline)

            Picker("Type", selection: $captureType) {
                ForEach(CaptureType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)

            TextEditor(text: $content)
                .frame(minHeight: 100)
                .border(Color.secondary.opacity(0.3))

            Picker("Save to", selection: $destination) {
                Text("Obsidian").tag(PKMSourceType.obsidian)
                Text("Notion").tag(PKMSourceType.notion)
            }
            .pickerStyle(.segmented)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Save") {
                    saveCapture()
                    dismiss()
                }
                .keyboardShortcut(.return)
                .disabled(content.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func saveCapture() {
        // TODO: Implement actual capture via MCP
        print("Capturing \(captureType.rawValue) to \(destination.displayName): \(content)")
    }
}

#Preview {
    PKMDashboardView()
        .environmentObject(MCPServerManager())
        .frame(width: 300, height: 600)
}
