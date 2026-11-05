import Foundation

/// Anything that can report changes relevant to the signed-in user.
public protocol ChangeSource: Sendable {
    var id: String { get }
    func fetchEvents() async throws -> [ChangeEvent]
}

/// Remembers which events were already announced so each toast fires once.
/// The first ingest after a fresh install is silent (it just records the backlog).
public actor EventTracker {
    private var seen: Set<String>
    private var primed: Bool

    public init(seen: Set<String> = [], primed: Bool = false) {
        self.seen = seen
        self.primed = primed
    }

    /// Returns events not seen before (empty on the very first call).
    public func ingest(_ events: [ChangeEvent]) -> [ChangeEvent] {
        let fresh = events.filter { !seen.contains($0.id) }
        seen.formUnion(events.map(\.id))
        defer { primed = true }
        return primed ? fresh : []
    }

    public func snapshot() -> (seen: Set<String>, primed: Bool) { (seen, primed) }
}
