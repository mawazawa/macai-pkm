//
//  PKMSettingsView.swift
//  macai-pkm
//
//  Settings view for PKM source configuration
//

import SwiftUI

/// Settings view for configuring PKM sources
struct PKMSettingsView: View {
    @EnvironmentObject var mcpManager: MCPServerManager
    @State private var selectedSource: PKMSourceType?
    @State private var configs: [PKMSourceType: PKMSourceConfig] = [:]

    var body: some View {
        HSplitView {
            // Source list
            VStack(alignment: .leading, spacing: 0) {
                Text("PKM Sources")
                    .font(.headline)
                    .padding()

                List(PKMSourceType.allCases, id: \.self, selection: $selectedSource) { source in
                    HStack {
                        Image(systemName: source.iconName)
                            .foregroundColor(source.color)
                            .frame(width: 20)

                        Text(source.displayName)

                        Spacer()

                        Circle()
                            .fill(statusColor(for: source))
                            .frame(width: 8, height: 8)
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(minWidth: 200)

            // Detail view
            if let source = selectedSource {
                SourceConfigView(
                    source: source,
                    config: binding(for: source),
                    status: mcpManager.serverStatuses[source] ?? .disconnected
                )
            } else {
                VStack {
                    Text("Select a source to configure")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            loadConfigs()
        }
    }

    private func statusColor(for source: PKMSourceType) -> Color {
        switch mcpManager.serverStatuses[source] {
        case .connected: return .green
        case .connecting: return .yellow
        case .error: return .red
        case .disconnected, .none: return .gray
        }
    }

    private func loadConfigs() {
        for type in PKMSourceType.allCases {
            configs[type] = PKMSourceConfig.defaultConfig(for: type)
        }
    }

    private func binding(for source: PKMSourceType) -> Binding<PKMSourceConfig> {
        Binding(
            get: { configs[source] ?? PKMSourceConfig.defaultConfig(for: source) },
            set: { configs[source] = $0 }
        )
    }
}

/// Configuration view for a single source
struct SourceConfigView: View {
    let source: PKMSourceType
    @Binding var config: PKMSourceConfig
    let status: MCPServerStatus
    @EnvironmentObject var mcpManager: MCPServerManager
    @State private var isConnecting = false

    var body: some View {
        Form {
            Section {
                Toggle("Enabled", isOn: $config.enabled)

                HStack {
                    Text("Status:")
                    Spacer()
                    StatusBadge(status: status)
                }
            } header: {
                Label(source.displayName, systemImage: source.iconName)
                    .font(.headline)
            }

            Section("Environment Variables") {
                ForEach(Array((config.environment ?? [:]).keys.sorted()), id: \.self) { key in
                    HStack {
                        Text(key)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("Value", text: environmentBinding(for: key))
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            Section("MCP Server") {
                LabeledContent("Command") {
                    Text(config.mcpServerCommand ?? "Not configured")
                        .foregroundColor(.secondary)
                }

                LabeledContent("Arguments") {
                    Text(config.mcpServerArgs?.joined(separator: " ") ?? "None")
                        .foregroundColor(.secondary)
                }
            }

            Section {
                HStack {
                    Button(status.isConnected ? "Disconnect" : "Connect") {
                        toggleConnection()
                    }
                    .disabled(isConnecting || !config.enabled)

                    if isConnecting {
                        ProgressView()
                            .scaleEffect(0.7)
                    }

                    Spacer()

                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(!config.enabled)
                }
            }

            if case .connected(let toolCount) = status {
                Section("Available Tools (\(toolCount))") {
                    if let tools = mcpManager.tools[source] {
                        ForEach(tools) { tool in
                            VStack(alignment: .leading) {
                                Text(tool.name)
                                    .font(.caption)
                                    .fontWeight(.medium)

                                if let description = tool.description {
                                    Text(description)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func environmentBinding(for key: String) -> Binding<String> {
        Binding(
            get: { config.environment?[key] ?? "" },
            set: { newValue in
                if config.environment == nil {
                    config.environment = [:]
                }
                config.environment?[key] = newValue
            }
        )
    }

    private func toggleConnection() {
        isConnecting = true
        Task {
            if status.isConnected {
                await mcpManager.stopServer(for: source)
            } else {
                mcpManager.updateConfig(config)
                await mcpManager.startServer(for: source)
            }
            await MainActor.run {
                isConnecting = false
            }
        }
    }

    private func testConnection() {
        // TODO: Implement connection test
    }
}

/// Status badge component
struct StatusBadge: View {
    let status: MCPServerStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(text)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(4)
    }

    private var color: Color {
        switch status {
        case .connected: return .green
        case .connecting: return .yellow
        case .error: return .red
        case .disconnected: return .gray
        }
    }

    private var text: String {
        switch status {
        case .connected(let count): return "Connected (\(count) tools)"
        case .connecting: return "Connecting..."
        case .error(let msg): return "Error: \(msg)"
        case .disconnected: return "Disconnected"
        }
    }
}

#Preview {
    PKMSettingsView()
        .environmentObject(MCPServerManager())
        .frame(width: 700, height: 500)
}
