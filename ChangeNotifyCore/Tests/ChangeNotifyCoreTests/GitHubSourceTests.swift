import Foundation
import Testing
@testable import ChangeNotifyCore

@Suite struct GitHubSourceTests {
    @Test func htmlURLMapping() {
        let pr = URL(string: "https://api.github.com/repos/JimGBritt/claude-usage-widget/pulls/6")!
        #expect(GitHubSource.htmlURL(fromAPIURL: pr)?.absoluteString
                == "https://github.com/JimGBritt/claude-usage-widget/pull/6")
        let issue = URL(string: "https://api.github.com/repos/o/r/issues/12")!
        #expect(GitHubSource.htmlURL(fromAPIURL: issue)?.absoluteString == "https://github.com/o/r/issues/12")
        let commit = URL(string: "https://api.github.com/repos/o/r/commits/abc")!
        #expect(GitHubSource.htmlURL(fromAPIURL: commit)?.absoluteString == "https://github.com/o/r/commit/abc")
    }

    @Test func nextStepLabels() {
        func pr(state: String = "open", merged: Bool = false, draft: Bool = false, ms: String? = nil)
            -> GitHubSource.PullRequestState {
            .init(state: state, merged: merged, draft: draft, mergeableState: ms)
        }
        #expect(GitHubSource.nextStep(for: .mention, pr: pr(merged: true)) == "Merged")
        #expect(GitHubSource.nextStep(for: .mention, pr: pr(state: "closed")) == "Closed")
        #expect(GitHubSource.nextStep(for: .reviewRequested, pr: pr(ms: "clean")) == "Your review is requested")
        #expect(GitHubSource.nextStep(for: .mention, pr: pr(ms: "clean")) == "Ready to merge")
        #expect(GitHubSource.nextStep(for: .mention, pr: pr(ms: "dirty")) == "Merge conflicts to resolve")
        #expect(GitHubSource.nextStep(for: .mention, pr: pr(ms: "blocked")) == "Waiting on a review or checks")
        #expect(GitHubSource.nextStep(for: .mention, pr: nil) == "You were mentioned – reply?")
    }

    @Test func trackerIsSilentFirstThenReportsOnlyNew() async {
        func ev(_ id: String) -> ChangeEvent {
            ChangeEvent(id: id, source: "github", project: "o/r", title: "t",
                        url: URL(string: "https://github.com/o/r")!, reason: .mention,
                        updatedAt: .now, nextStep: nil)
        }
        let tracker = EventTracker()
        #expect(await tracker.ingest([ev("a")]).isEmpty)
        #expect(await tracker.ingest([ev("a"), ev("b")]).map(\.id) == ["b"])
        #expect(await tracker.ingest([ev("a"), ev("b")]).isEmpty)
    }

    @Test func fetchFiltersReasonsAndEnrichesPRs() async throws {
        let session = StubProtocol.session { url in
            if url.path == "/notifications" {
                return Data("""
                [
                 {"id":"1","reason":"mention","updated_at":"2026-11-05T17:55:00Z",
                  "subject":{"title":"Add widget","url":"https://api.github.com/repos/o/r/pulls/6","type":"PullRequest"},
                  "repository":{"full_name":"o/r"}},
                 {"id":"2","reason":"subscribed","updated_at":"2026-11-05T17:56:00Z",
                  "subject":{"title":"Noise","url":"https://api.github.com/repos/o/r/issues/9","type":"Issue"},
                  "repository":{"full_name":"o/r"}}
                ]
                """.utf8)
            }
            return Data(#"{"state":"open","merged":false,"draft":false,"mergeable_state":"clean"}"#.utf8)
        }
        let events = try await GitHubSource(token: "x", session: session).fetchEvents()
        #expect(events.count == 1)
        #expect(events[0].url.absoluteString == "https://github.com/o/r/pull/6")
        #expect(events[0].nextStep == "Ready to merge")
        #expect(events[0].reason == .mention)
    }
}

/// URLProtocol stub so tests never touch the network.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URL) -> Data)?

    static func session(_ handler: @escaping @Sendable (URL) -> Data) -> URLSession {
        Self.handler = handler
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: cfg)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Self.handler?(request.url!) ?? Data()
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
