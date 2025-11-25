//
//  MCPServerManager.swift
//  macai-pkm
//
//  Manages multiple MCP server connections
//

import Foundation
import SwiftUI

/// Status of an MCP server connection
enum MCPServerStatus: Equatable {
    case disconnected
    case connecting
    case connected(toolCount: Int)
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    static func == (lhs: MCPServerStatus, rhs: MCPServerStatus) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected): return true
        case (.connecting, .connecting): return true
        case (.connected(let a), .connected(let b)): return a == b
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

/// Manages all MCP server connections
@MainActor
class MCPServerManager: ObservableObject {
    @Published var serverStatuses: [PKMSourceType: MCPServerStatus] = [:]
    @Published var tools: [PKMSourceType: [MCPTool]] = [:]

    private var clients: [PKMSourceType: MCPClient] = [:]
    private var configs: [PKMSourceType: PKMSourceConfig] = [:]

    init() {
        // Initialize with default configs
        for type in PKMSourceType.allCases {
            configs[type] = PKMSourceConfig.defaultConfig(for: type)
            serverStatuses[type] = .disconnected
        }
    }

    /// Update configuration for a source
    func updateConfig(_ config: PKMSourceConfig) {
        configs[config.type] = config
    }

    /// Start an MCP server for a source
    func startServer(for sourceType: PKMSourceType) async {
        guard let config = configs[sourceType],
              config.enabled,
              let command = config.mcpServerCommand,
              let args = config.mcpServerArgs else {
            serverStatuses[sourceType] = .error("Not configured")
            return
        }

        serverStatuses[sourceType] = .connecting

        do {
            let client = try MCPClient(
                command: command,
                args: args,
                env: config.environment ?? [:]
            )

            let _ = try await client.initialize()
            let serverTools = try await client.listTools()

            clients[sourceType] = client
            tools[sourceType] = serverTools
            serverStatuses[sourceType] = .connected(toolCount: serverTools.count)

        } catch {
            serverStatuses[sourceType] = .error(error.localizedDescription)
        }
    }

    /// Stop an MCP server
    func stopServer(for sourceType: PKMSourceType) async {
        if let client = clients[sourceType] {
            await client.disconnect()
            clients.removeValue(forKey: sourceType)
        }
        tools[sourceType] = []
        serverStatuses[sourceType] = .disconnected
    }

    /// Start all enabled servers
    func startAllEnabled() async {
        for (type, config) in configs where config.enabled {
            await startServer(for: type)
        }
    }

    /// Stop all servers
    func stopAll() async {
        for type in PKMSourceType.allCases {
            await stopServer(for: type)
        }
    }

    /// Call a tool on a specific server
    func callTool(on sourceType: PKMSourceType, tool: String, arguments: [String: Any]) async throws -> MCPToolResult {
        guard let client = clients[sourceType] else {
            throw MCPError.serverNotFound(sourceType.displayName)
        }
        return try await client.callTool(name: tool, arguments: arguments)
    }

    /// Search across all connected sources
    func searchAcrossSources(query: String) async -> [PKMSearchResult] {
        var results: [PKMSearchResult] = []

        await withTaskGroup(of: [PKMSearchResult].self) { group in
            for (sourceType, client) in clients {
                group.addTask { [weak self] in
                    guard let self = self else { return [] }
                    return await self.searchSource(sourceType: sourceType, client: client, query: query)
                }
            }

            for await sourceResults in group {
                results.append(contentsOf: sourceResults)
            }
        }

        return results.sorted { $0.relevance > $1.relevance }
    }

    // MARK: - Private Search Methods

    private func searchSource(sourceType: PKMSourceType, client: MCPClient, query: String) async -> [PKMSearchResult] {
        do {
            switch sourceType {
            case .notion:
                return try await searchNotion(client: client, query: query)
            case .obsidian:
                return try await searchObsidian(client: client, query: query)
            case .neo4j:
                return try await searchNeo4j(client: client, query: query)
            case .googleDrive:
                return try await searchGoogleDrive(client: client, query: query)
            case .github:
                return try await searchGitHub(client: client, query: query)
            }
        } catch {
            print("Search error for \(sourceType.displayName): \(error)")
            return []
        }
    }

    private func searchNotion(client: MCPClient, query: String) async throws -> [PKMSearchResult] {
        let result = try await client.callTool(
            name: "notion-search",
            arguments: ["query": query]
        )
        return parseNotionResults(result.content, query: query)
    }

    private func searchObsidian(client: MCPClient, query: String) async throws -> [PKMSearchResult] {
        let result = try await client.callTool(
            name: "search",
            arguments: ["query": query]
        )
        return parseObsidianResults(result.content, query: query)
    }

    private func searchNeo4j(client: MCPClient, query: String) async throws -> [PKMSearchResult] {
        let cypherQuery = """
            MATCH (n)
            WHERE n.name CONTAINS $query OR n.description CONTAINS $query
            RETURN n LIMIT 10
        """
        let result = try await client.callTool(
            name: "execute_query",
            arguments: [
                "query": cypherQuery,
                "params": ["query": query]
            ]
        )
        return parseNeo4jResults(result.content, query: query)
    }

    private func searchGoogleDrive(client: MCPClient, query: String) async throws -> [PKMSearchResult] {
        let result = try await client.callTool(
            name: "search",
            arguments: ["query": query]
        )
        return parseGoogleDriveResults(result.content, query: query)
    }

    private func searchGitHub(client: MCPClient, query: String) async throws -> [PKMSearchResult] {
        let result = try await client.callTool(
            name: "search_code",
            arguments: ["q": query]
        )
        return parseGitHubResults(result.content, query: query)
    }

    // MARK: - Result Parsers

    private func parseNotionResults(_ content: String, query: String) -> [PKMSearchResult] {
        // Parse JSON response from Notion MCP
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }

        return results.compactMap { item -> PKMSearchResult? in
            guard let title = item["title"] as? String else { return nil }
            let snippet = item["content"] as? String ?? ""
            let urlString = item["url"] as? String
            let url = urlString.flatMap { URL(string: $0) }

            return PKMSearchResult(
                source: .notion,
                title: title,
                snippet: String(snippet.prefix(200)),
                url: url,
                relevance: calculateRelevance(query: query, title: title, content: snippet)
            )
        }
    }

    private func parseObsidianResults(_ content: String, query: String) -> [PKMSearchResult] {
        guard let data = content.data(using: .utf8),
              let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return results.compactMap { item -> PKMSearchResult? in
            guard let path = item["path"] as? String else { return nil }
            let content = item["content"] as? String ?? ""
            let title = (path as NSString).lastPathComponent

            return PKMSearchResult(
                source: .obsidian,
                title: title,
                snippet: String(content.prefix(200)),
                url: URL(fileURLWithPath: path),
                relevance: calculateRelevance(query: query, title: title, content: content),
                metadata: ["path": path]
            )
        }
    }

    private func parseNeo4jResults(_ content: String, query: String) -> [PKMSearchResult] {
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = json["records"] as? [[String: Any]] else {
            return []
        }

        return records.compactMap { record -> PKMSearchResult? in
            guard let node = record["n"] as? [String: Any],
                  let properties = node["properties"] as? [String: Any],
                  let name = properties["name"] as? String else {
                return nil
            }

            let description = properties["description"] as? String ?? ""
            let labels = (node["labels"] as? [String])?.joined(separator: ", ") ?? ""

            return PKMSearchResult(
                source: .neo4j,
                title: name,
                snippet: description.isEmpty ? "Labels: \(labels)" : String(description.prefix(200)),
                relevance: calculateRelevance(query: query, title: name, content: description),
                metadata: ["labels": labels]
            )
        }
    }

    private func parseGoogleDriveResults(_ content: String, query: String) -> [PKMSearchResult] {
        guard let data = content.data(using: .utf8),
              let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return results.compactMap { item -> PKMSearchResult? in
            guard let name = item["name"] as? String else { return nil }
            let mimeType = item["mimeType"] as? String ?? ""
            let urlString = item["webViewLink"] as? String
            let url = urlString.flatMap { URL(string: $0) }

            return PKMSearchResult(
                source: .googleDrive,
                title: name,
                snippet: "Type: \(mimeType)",
                url: url,
                relevance: calculateRelevance(query: query, title: name, content: ""),
                metadata: ["mimeType": mimeType]
            )
        }
    }

    private func parseGitHubResults(_ content: String, query: String) -> [PKMSearchResult] {
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            return []
        }

        return items.compactMap { item -> PKMSearchResult? in
            guard let name = item["name"] as? String,
                  let path = item["path"] as? String else {
                return nil
            }
            let repo = (item["repository"] as? [String: Any])?["full_name"] as? String ?? ""
            let urlString = item["html_url"] as? String
            let url = urlString.flatMap { URL(string: $0) }

            return PKMSearchResult(
                source: .github,
                title: name,
                snippet: "Repository: \(repo)\nPath: \(path)",
                url: url,
                relevance: calculateRelevance(query: query, title: name, content: path),
                metadata: ["repo": repo, "path": path]
            )
        }
    }

    private func calculateRelevance(query: String, title: String, content: String) -> Double {
        let queryLower = query.lowercased()
        let titleLower = title.lowercased()
        let contentLower = content.lowercased()

        var score = 0.0

        // Exact title match
        if titleLower == queryLower {
            score += 1.0
        }
        // Title contains query
        else if titleLower.contains(queryLower) {
            score += 0.7
        }

        // Content contains query
        if contentLower.contains(queryLower) {
            score += 0.3
        }

        // Word matches in title
        let queryWords = queryLower.split(separator: " ")
        let titleWords = Set(titleLower.split(separator: " "))
        let matchingWords = queryWords.filter { titleWords.contains($0) }
        score += Double(matchingWords.count) / Double(queryWords.count) * 0.5

        return min(score, 1.0)
    }
}
