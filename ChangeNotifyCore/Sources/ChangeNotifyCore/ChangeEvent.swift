import Foundation

/// A source-agnostic "something changed and it concerns you" event.
/// GitHub is the first producer; GitLab, Jira, etc. can emit the same type.
public struct ChangeEvent: Identifiable, Hashable, Codable, Sendable {
    public enum Reason: String, Codable, Sendable {
        case mention
        case teamMention
        case reviewRequested
        case assigned
        case authored
    }

    /// Unique per source item *and* update time, so a new comment on the same PR re-notifies.
    public let id: String
    public let source: String
    public let project: String        // e.g. "JimGBritt/claude-usage-widget"
    public let title: String
    public let url: URL
    public let reason: Reason
    public let updatedAt: Date
    /// Short human hint: "Your review requested", "Ready to merge", ...
    public let nextStep: String?

    public init(id: String, source: String, project: String, title: String, url: URL,
                reason: Reason, updatedAt: Date, nextStep: String?) {
        self.id = id
        self.source = source
        self.project = project
        self.title = title
        self.url = url
        self.reason = reason
        self.updatedAt = updatedAt
        self.nextStep = nextStep
    }
}

public extension ChangeEvent.Reason {
    var label: String {
        switch self {
        case .mention: "Mentioned you"
        case .teamMention: "Mentioned your team"
        case .reviewRequested: "Review requested"
        case .assigned: "Assigned to you"
        case .authored: "Activity on yours"
        }
    }
}
