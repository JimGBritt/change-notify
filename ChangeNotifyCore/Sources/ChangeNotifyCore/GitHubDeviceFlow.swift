import Foundation

public struct DeviceCode: Sendable, Equatable {
    public let deviceCode: String
    public let userCode: String
    public let verificationURI: URL
    public let expiresIn: Int
    public let interval: Int
}

public enum DeviceFlowError: LocalizedError, Sendable, Equatable {
    case expired
    case denied
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .expired: "The code expired. Please try again."
        case .denied: "Sign-in was cancelled on GitHub."
        case .failed(let message): "GitHub sign-in failed: \(message)"
        }
    }
}

/// GitHub OAuth device flow: the user types a short code at github.com/login/device.
/// No client secret and no redirect handling are needed, which suits iOS and macOS alike.
public struct GitHubDeviceFlow: Sendable {
    private let clientID: String
    private let session: URLSession
    private let baseURL: URL

    public init(clientID: String, session: URLSession = .shared,
                baseURL: URL = URL(string: "https://github.com")!) {
        self.clientID = clientID
        self.session = session
        self.baseURL = baseURL
    }

    public func requestCode(scope: String) async throws -> DeviceCode {
        let data = try await post("login/device/code", ["client_id": clientID, "scope": scope])
        return try Self.parseCode(data)
    }

    /// Polls until the user approves, denies, or the code expires. Honors Task cancellation.
    public func pollForToken(_ code: DeviceCode) async throws -> String {
        var interval = max(code.interval, 1)
        let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))
        while Date() < deadline {
            try await Task.sleep(for: .seconds(interval))
            let data = try await post("login/oauth/access_token", [
                "client_id": clientID,
                "device_code": code.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
            switch try Self.parsePoll(data) {
            case .token(let token): return token
            case .pending: continue
            case .slowDown(let newInterval): interval = newInterval ?? interval + 5
            }
        }
        throw DeviceFlowError.expired
    }

    // MARK: - Pure parsing (unit tested)

    enum PollResult: Equatable {
        case token(String)
        case pending
        case slowDown(Int?)
    }

    static func parseCode(_ data: Data) throws -> DeviceCode {
        struct Raw: Decodable {
            let deviceCode: String?, userCode: String?, verificationUri: URL?
            let expiresIn: Int?, interval: Int?
            let error: String?, errorDescription: String?
        }
        let raw = try decoder.decode(Raw.self, from: data)
        if let error = raw.error { throw DeviceFlowError.failed(raw.errorDescription ?? error) }
        guard let dc = raw.deviceCode, let uc = raw.userCode, let uri = raw.verificationUri else {
            throw DeviceFlowError.failed("unexpected response")
        }
        return DeviceCode(deviceCode: dc, userCode: uc, verificationURI: uri,
                          expiresIn: raw.expiresIn ?? 900, interval: raw.interval ?? 5)
    }

    static func parsePoll(_ data: Data) throws -> PollResult {
        struct Raw: Decodable {
            let accessToken: String?
            let error: String?, errorDescription: String?
            let interval: Int?
        }
        let raw = try decoder.decode(Raw.self, from: data)
        if let token = raw.accessToken { return .token(token) }
        switch raw.error {
        case "authorization_pending": return .pending
        case "slow_down": return .slowDown(raw.interval)
        case "expired_token": throw DeviceFlowError.expired
        case "access_denied": throw DeviceFlowError.denied
        case let other?: throw DeviceFlowError.failed(raw.errorDescription ?? other)
        case nil: throw DeviceFlowError.failed("unexpected response")
        }
    }

    // MARK: - Networking

    private func post(_ path: String, _ form: [String: String]) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        req.httpBody = form.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&").data(using: .utf8)
        let (data, _) = try await session.data(for: req)
        return data
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}
