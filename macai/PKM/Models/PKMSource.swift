//
//  PKMSource.swift
//  macai-pkm
//
//  Personal Knowledge Management source definitions
//

import Foundation
import SwiftUI

/// Represents a PKM data source (Notion, Obsidian, Neo4j, etc.)
enum PKMSourceType: String, Codable, CaseIterable {
    case notion
    case obsidian
    case neo4j
    case googleDrive
    case github

    var displayName: String {
        switch self {
        case .notion: return "Notion"
        case .obsidian: return "Obsidian"
        case .neo4j: return "Neo4j"
        case .googleDrive: return "Google Drive"
        case .github: return "GitHub"
        }
    }

    var iconName: String {
        switch self {
        case .notion: return "doc.text"
        case .obsidian: return "note.text"
        case .neo4j: return "circle.hexagongrid"
        case .googleDrive: return "externaldrive"
        case .github: return "chevron.left.forwardslash.chevron.right"
        }
    }

    var color: Color {
        switch self {
        case .notion: return .black
        case .obsidian: return .purple
        case .neo4j: return .green
        case .googleDrive: return .blue
        case .github: return .gray
        }
    }
}

/// Configuration for a PKM source connection
struct PKMSourceConfig: Codable, Identifiable {
    var id: UUID = UUID()
    var type: PKMSourceType
    var enabled: Bool
    var name: String
    var mcpServerCommand: String?
    var mcpServerArgs: [String]?
    var environment: [String: String]?
    var lastSyncDate: Date?

    /// Default configurations for each source type
    static func defaultConfig(for type: PKMSourceType) -> PKMSourceConfig {
        switch type {
        case .notion:
            return PKMSourceConfig(
                type: .notion,
                enabled: false,
                name: "Notion",
                mcpServerCommand: "npx",
                mcpServerArgs: ["-y", "@modelcontextprotocol/server-notion"],
                environment: ["NOTION_API_KEY": ""]
            )
        case .obsidian:
            return PKMSourceConfig(
                type: .obsidian,
                enabled: false,
                name: "Obsidian",
                mcpServerCommand: "npx",
                mcpServerArgs: ["-y", "claudesidian-mcp"],
                environment: ["OBSIDIAN_VAULT_PATH": ""]
            )
        case .neo4j:
            return PKMSourceConfig(
                type: .neo4j,
                enabled: false,
                name: "Neo4j",
                mcpServerCommand: "npx",
                mcpServerArgs: ["-y", "@modelcontextprotocol/server-neo4j"],
                environment: [
                    "NEO4J_URI": "",
                    "NEO4J_USER": "neo4j",
                    "NEO4J_PASSWORD": ""
                ]
            )
        case .googleDrive:
            return PKMSourceConfig(
                type: .googleDrive,
                enabled: false,
                name: "Google Drive",
                mcpServerCommand: "npx",
                mcpServerArgs: ["-y", "@modelcontextprotocol/server-gdrive"],
                environment: ["GOOGLE_CREDENTIALS_PATH": ""]
            )
        case .github:
            return PKMSourceConfig(
                type: .github,
                enabled: false,
                name: "GitHub",
                mcpServerCommand: "npx",
                mcpServerArgs: ["-y", "@modelcontextprotocol/server-github"],
                environment: ["GITHUB_TOKEN": ""]
            )
        }
    }
}

/// Result from searching PKM sources
struct PKMSearchResult: Identifiable {
    let id: UUID = UUID()
    let source: PKMSourceType
    let title: String
    let snippet: String
    let url: URL?
    let relevance: Double
    let metadata: [String: String]

    init(source: PKMSourceType, title: String, snippet: String, url: URL? = nil, relevance: Double = 0.5, metadata: [String: String] = [:]) {
        self.source = source
        self.title = title
        self.snippet = snippet
        self.url = url
        self.relevance = relevance
        self.metadata = metadata
    }
}

/// An item from a PKM source
struct PKMItem: Identifiable {
    let id: UUID = UUID()
    let source: PKMSourceType
    let title: String
    let content: String?
    let url: URL?
    let createdAt: Date?
    let modifiedAt: Date?
    let metadata: [String: String]
}
