import Foundation

public struct CodexTokenUsage: Equatable, Sendable {
    public let inputTokens: Int
    public let cachedInputTokens: Int
    public let outputTokens: Int
    public let reasoningOutputTokens: Int

    public init(
        inputTokens: Int,
        cachedInputTokens: Int,
        outputTokens: Int,
        reasoningOutputTokens: Int
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
    }
}

public enum CodexItemKind: Equatable, Sendable {
    case agentMessage
    case reasoning
    case commandExecution
    case fileChange
    case mcpToolCall
    case webSearch
    case planUpdate
    case unknown(String)
}

public struct CodexItem: Equatable, Sendable {
    public let id: String?
    public let kind: CodexItemKind
    public let text: String?

    public init(id: String?, kind: CodexItemKind, text: String?) {
        self.id = id
        self.kind = kind
        self.text = text
    }
}

public enum CodexEvent: Equatable, Sendable {
    case threadStarted(String?)
    case turnStarted
    case itemStarted(CodexItem)
    case itemUpdated(CodexItem)
    case itemCompleted(CodexItem)
    case turnCompleted(CodexTokenUsage)
    case turnFailed
    case error
    case unknown(String)
}

public enum CodexEventDecodingError: Error, Equatable, Sendable {
    case malformed
}

public struct CodexEventDecoder: Sendable {
    public init() {}

    public func decode(_ data: Data) throws -> CodexEvent {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any],
            let type = dictionary["type"] as? String
        else {
            throw CodexEventDecodingError.malformed
        }

        switch type {
        case "thread.started":
            return .threadStarted(dictionary["thread_id"] as? String)
        case "turn.started":
            return .turnStarted
        case "item.started":
            return .itemStarted(try decodeItem(dictionary["item"]))
        case "item.updated":
            return .itemUpdated(try decodeItem(dictionary["item"]))
        case "item.completed":
            return .itemCompleted(try decodeItem(dictionary["item"]))
        case "turn.completed":
            guard let usage = dictionary["usage"] as? [String: Any] else {
                throw CodexEventDecodingError.malformed
            }
            return .turnCompleted(
                CodexTokenUsage(
                    inputTokens: integer(usage["input_tokens"]),
                    cachedInputTokens: integer(usage["cached_input_tokens"]),
                    outputTokens: integer(usage["output_tokens"]),
                    reasoningOutputTokens: integer(usage["reasoning_output_tokens"])
                )
            )
        case "turn.failed":
            return .turnFailed
        case "error":
            return .error
        default:
            return .unknown(type)
        }
    }

    private func decodeItem(_ value: Any?) throws -> CodexItem {
        guard let item = value as? [String: Any], let type = item["type"] as? String else {
            throw CodexEventDecodingError.malformed
        }
        let kind: CodexItemKind = switch type {
        case "agent_message": .agentMessage
        case "reasoning": .reasoning
        case "command_execution": .commandExecution
        case "file_change": .fileChange
        case "mcp_tool_call": .mcpToolCall
        case "web_search": .webSearch
        case "plan": .planUpdate
        default: .unknown(type)
        }
        return CodexItem(id: item["id"] as? String, kind: kind, text: item["text"] as? String)
    }

    private func integer(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }
}
