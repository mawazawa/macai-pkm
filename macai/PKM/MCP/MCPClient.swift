//
//  MCPClient.swift
//  macai-pkm
//
//  MCP (Model Context Protocol) client implementation
//

import Foundation

/// JSON-RPC request structure
struct JSONRPCRequest: Codable {
    let jsonrpc: String = "2.0"
    let id: Int
    let method: String
    let params: [String: AnyCodableValue]?

    init(id: Int, method: String, params: [String: Any]? = nil) {
        self.id = id
        self.method = method
        self.params = params?.mapValues { AnyCodableValue($0) }
    }
}

/// JSON-RPC response structure
struct JSONRPCResponse: Codable {
    let jsonrpc: String
    let id: Int?
    let result: AnyCodableValue?
    let error: JSONRPCError?
}

/// JSON-RPC error
struct JSONRPCError: Codable, LocalizedError {
    let code: Int
    let message: String
    let data: AnyCodableValue?

    var errorDescription: String? { message }
}

/// MCP tool definition
struct MCPTool: Codable, Identifiable {
    var id: String { name }
    let name: String
    let description: String?
    let inputSchema: [String: AnyCodableValue]?
}

/// MCP tool call result
struct MCPToolResult {
    let content: String
    let isError: Bool

    init(content: String, isError: Bool = false) {
        self.content = content
        self.isError = isError
    }
}

/// MCP server capabilities
struct MCPCapabilities: Codable {
    let tools: ToolsCapability?
    let resources: ResourcesCapability?
    let prompts: PromptsCapability?

    struct ToolsCapability: Codable {
        let listChanged: Bool?
    }

    struct ResourcesCapability: Codable {
        let subscribe: Bool?
        let listChanged: Bool?
    }

    struct PromptsCapability: Codable {
        let listChanged: Bool?
    }
}

/// MCP client errors
enum MCPError: LocalizedError {
    case notConnected
    case serverNotFound(String)
    case invalidToolName
    case serverError(JSONRPCError)
    case processError(String)
    case connectionFailed(String)
    case responseParseError

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "MCP client not connected"
        case .serverNotFound(let name):
            return "MCP server '\(name)' not found"
        case .invalidToolName:
            return "Invalid MCP tool name format"
        case .serverError(let error):
            return "MCP server error: \(error.message)"
        case .processError(let msg):
            return "Process error: \(msg)"
        case .connectionFailed(let msg):
            return "Connection failed: \(msg)"
        case .responseParseError:
            return "Failed to parse MCP response"
        }
    }
}

/// MCP client actor for managing a single MCP server connection
actor MCPClient {
    private let process: Process
    private let stdin: FileHandle
    private let stdout: FileHandle
    private var requestId: Int = 0
    private var capabilities: MCPCapabilities?
    private var pendingResponses: [Int: CheckedContinuation<JSONRPCResponse, Error>] = [:]
    private var isInitialized: Bool = false

    init(command: String, args: [String], env: [String: String] = [:]) throws {
        process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + args

        var environment = ProcessInfo.processInfo.environment
        for (key, value) in env {
            environment[key] = value
        }
        process.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdin = stdinPipe.fileHandleForWriting
        stdout = stdoutPipe.fileHandleForReading

        try process.run()
    }

    deinit {
        if process.isRunning {
            process.terminate()
        }
    }

    /// Initialize the MCP connection
    func initialize() async throws -> MCPCapabilities {
        let response = try await sendRequest(
            method: "initialize",
            params: [
                "protocolVersion": "2024-11-05",
                "capabilities": [:] as [String: Any],
                "clientInfo": [
                    "name": "macai-pkm",
                    "version": "1.0.0"
                ]
            ]
        )

        // Send initialized notification
        try await sendNotification(method: "notifications/initialized")

        // Parse capabilities from response
        if let result = response.result {
            let data = try JSONEncoder().encode(result)
            let initResult = try JSONDecoder().decode(InitializeResult.self, from: data)
            capabilities = initResult.capabilities
            isInitialized = true
            return initResult.capabilities
        }

        throw MCPError.responseParseError
    }

    /// List available tools
    func listTools() async throws -> [MCPTool] {
        let response = try await sendRequest(method: "tools/list", params: nil)

        if let result = response.result {
            let data = try JSONEncoder().encode(result)
            let listResult = try JSONDecoder().decode(ToolsListResult.self, from: data)
            return listResult.tools
        }

        return []
    }

    /// Call a tool
    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        let response = try await sendRequest(
            method: "tools/call",
            params: [
                "name": name,
                "arguments": arguments
            ]
        )

        if let error = response.error {
            throw MCPError.serverError(error)
        }

        if let result = response.result {
            let data = try JSONEncoder().encode(result)
            let callResult = try JSONDecoder().decode(ToolCallResult.self, from: data)

            // Combine all text content
            let content = callResult.content
                .filter { $0.type == "text" }
                .compactMap { $0.text }
                .joined(separator: "\n")

            return MCPToolResult(content: content, isError: callResult.isError ?? false)
        }

        return MCPToolResult(content: "", isError: true)
    }

    /// Disconnect and terminate the MCP server process
    func disconnect() {
        if process.isRunning {
            process.terminate()
        }
    }

    // MARK: - Private Methods

    private func sendRequest(method: String, params: [String: Any]?) async throws -> JSONRPCResponse {
        requestId += 1
        let currentId = requestId

        let request = JSONRPCRequest(id: currentId, method: method, params: params)
        let data = try JSONEncoder().encode(request)
        let line = data + Data("\n".utf8)

        stdin.write(line)

        return try await readResponse(id: currentId)
    }

    private func sendNotification(method: String, params: [String: Any]? = nil) async throws {
        let notification: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params ?? [:]
        ]

        let data = try JSONSerialization.data(withJSONObject: notification)
        let line = data + Data("\n".utf8)
        stdin.write(line)
    }

    private func readResponse(id: Int) async throws -> JSONRPCResponse {
        // Simple synchronous read for now
        // In production, this should be async with proper buffering
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                while true {
                    if let line = readLine(from: stdout) {
                        do {
                            let response = try JSONDecoder().decode(JSONRPCResponse.self, from: line)
                            if response.id == id {
                                continuation.resume(returning: response)
                                return
                            }
                        } catch {
                            // Not our response, continue reading
                        }
                    }
                    try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                }
            }
        }
    }

    private func readLine(from handle: FileHandle) -> Data? {
        let data = handle.availableData
        if data.isEmpty { return nil }
        return data
    }
}

// MARK: - Response Types

private struct InitializeResult: Codable {
    let protocolVersion: String
    let capabilities: MCPCapabilities
    let serverInfo: ServerInfo?

    struct ServerInfo: Codable {
        let name: String
        let version: String?
    }
}

private struct ToolsListResult: Codable {
    let tools: [MCPTool]
}

private struct ToolCallResult: Codable {
    let content: [ContentItem]
    let isError: Bool?

    struct ContentItem: Codable {
        let type: String
        let text: String?
    }
}

// MARK: - AnyCodableValue

/// A type-erased Codable value for JSON-RPC
struct AnyCodableValue: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodableValue].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodableValue].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodableValue($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodableValue($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Cannot encode value"))
        }
    }
}
