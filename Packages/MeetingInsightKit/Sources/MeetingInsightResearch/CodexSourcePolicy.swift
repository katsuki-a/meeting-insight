import Foundation

public enum CodexSourcePolicyViolation: Error, Equatable, Sendable {
    case forbiddenItem(CodexItemKind)
}

public struct CodexSourcePolicy: Sendable {
    public init() {}

    public func violation(for event: CodexEvent) -> CodexSourcePolicyViolation? {
        let item: CodexItem? = switch event {
        case .itemStarted(let item), .itemUpdated(let item), .itemCompleted(let item): item
        default: nil
        }
        guard let item else { return nil }
        switch item.kind {
        case .webSearch, .mcpToolCall, .fileChange:
            return .forbiddenItem(item.kind)
        default:
            return nil
        }
    }
}
