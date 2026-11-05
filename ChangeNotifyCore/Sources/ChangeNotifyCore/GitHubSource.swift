import Foundation

public enum GitHubError: LocalizedError, Sendable {
    case unauthorized
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .unauthorized: "GitHub rejected the token (needs the “notifications” scope)."
        case .http(let code): "GitHub returned HTTP \(code)."
        }
    }
}

/// Polls the signed-in user's GitHub notifications and keeps the ones that concern them.
public struct GitHubSource: ChangeSource {
    public let id = "github"
    private let token: String
    private let session: URLSession
    private let baseURL: URL
    private let reasons: Set<String>

    public init(token: String,
                session: URLSession = .shared,
                baseURL: URL = URL(string: "https://api.github.com")!,
                reasons: Set<String> = ["mention", "team_mention", "review_requested", "assign"]) {
        self.token = token
        self.session = session
        self.baseURL = baseURL
        self.reasons = reasons
    }

    public func fetchEvents() async throws -> [ChangeEvent] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("notifications"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "all", value: "false"), .init(name: "per_page", value: "50")]
        let data = try await get(comps.url!)
        let threads = try Self.decoder.decode([Thread].self, from: data)

        var events: [ChangeEvent] = []
        for thread in threads where reasons.contains(thread.reason) {
            guard let reason = Self.mapReason(thread.reason) else { continue }
            var pr: PullRequestState?
            if thread.subject.type == "PullRequest", let apiURL = thread.subject.url {
                // Enrichment is best-effort: a failure must not drop the notification.
                pr = try? Self.decoder.decode(PullRequestState.self, from: await get(apiURL))
            }
            let repoURL = URL(string: "https://github.com/\(thread.repository.fullName)")!
            events.append(ChangeEvent(
                id: "github:\(thread.id)@\(ISO8601DateFormatter().string(from: thread.updatedAt))",
                source: "github",
                project: thread.repository.fullName,
                title: thread.subject.title,
                url: thread.subject.url.flatMap(Self.htmlURL(fromAPIURL:)) ?? repoURL,
                reason: reason,
                updatedAt: thread.updatedAt,
                nextStep: thread.subject.type == "PullRequest"
                    ? Self.nextStep(for: reason, pr: pr) : nil
            ))
        }
        return events.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Pure helpers (unit tested)

    static func mapReason(_ raw: String) -> ChangeEvent.Reason? {
        switch raw {
        case "mention": .mention
        case "team_mention": .teamMention
        case "review_requested": .reviewRequested
        case "assign": .assigned
        case "author": .authored
        default: nil
        }
    }

    /// https://api.github.com/repos/o/r/pulls/6 -> https://github.com/o/r/pull/6
    static func htmlURL(fromAPIURL url: URL) -> URL? {
        let p = url.pathComponents.filter { $0 != "/" }
        guard p.count >= 5, p[0] == "repos" else { return nil }
        let kind: String
        switch p[3] {
        case "pulls": kind = "pull"
        case "issues": kind = "issues"
        case "commits": kind = "commit"
        default: return URL(string: "https://github.com/\(p[1])/\(p[2])")
        }
        return URL(string: "https://github.com/\(p[1])/\(p[2])/\(kind)/\(p[4])")
    }

    static func nextStep(for reason: ChangeEvent.Reason, pr: PullRequestState?) -> String? {
        if let pr {
            if pr.merged == true { return "Merged" }
            if pr.state == "closed" { return "Closed" }
            if pr.draft == true { return "Draft – not ready for review" }
            if reason == .reviewRequested { return "Your review is requested" }
            switch pr.mergeableState {
            case "dirty": return "Merge conflicts to resolve"
            case "unstable": return "Checks are failing"
            case "behind": return "Branch is behind – update it"
            case "blocked": return "Waiting on a review or checks"
            case "clean", "has_hooks": return "Ready to merge"
            default: break
            }
        }
        switch reason {
        case .reviewRequested: return "Your review is requested"
        case .mention, .teamMention: return "You were mentioned – reply?"
        case .assigned: return "Assigned to you"
        case .authored: return nil
        }
    }

    // MARK: - Networking

    private func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw GitHubError.http(-1) }
        switch http.statusCode {
        case 200..<300: return data
        case 401, 403: throw GitHubError.unauthorized
        default: throw GitHubError.http(http.statusCode)
        }
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    struct Thread: Decodable {
        struct Subject: Decodable { let title: String; let url: URL?; let type: String }
        struct Repository: Decodable { let fullName: String }
        let id: String
        let reason: String
        let updatedAt: Date
        let subject: Subject
        let repository: Repository
    }

    struct PullRequestState: Decodable, Equatable {
        let state: String
        let merged: Bool?
        let draft: Bool?
        let mergeableState: String?
    }
}
