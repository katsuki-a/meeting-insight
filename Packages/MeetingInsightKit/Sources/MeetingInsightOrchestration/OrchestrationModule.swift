import MeetingInsightDomain
import MeetingInsightRepository
import MeetingInsightResearch
import MeetingInsightTranscription

public enum OrchestrationModule: Sendable {
    public static let initialStatus = SessionStatus.idle
}
