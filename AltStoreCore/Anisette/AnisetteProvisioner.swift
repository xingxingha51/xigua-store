//
//  AnisetteProvisioner.swift
//  AltStoreCore
//
//  Xigua fork.
//

import Foundation
import CryptoKit

/// Anisette v3 provisioning: registering a new device with Apple through an
/// anisette server.
///
/// The server runs Apple's ADI. We relay its messages to GrandSlam's
/// provisioning endpoints and back, and come away with the adi.pb the server
/// then uses to generate anisette headers for us. No Apple ID is involved.
///
/// This replaces the Starscream-delegate version that lived in
/// FetchAnisetteDataOperation. That one could only fail the whole operation,
/// not let it try another server, and it hung when the socket errored, because
/// those events were only logged.
public struct AnisetteProvisioner
{
    public enum Failure: LocalizedError, Equatable
    {
        public enum Step: String { case start, finish }

        /// GrandSlam's lookup didn't list the provisioning endpoints. That has
        /// nothing to do with the anisette server, so another one won't help.
        case lookupFailed
        /// Apple refused a provisioning step. Since Nov 2026 it answers every
        /// Android-ADI server with -29003 ("possible environment mismatch").
        case appleRejected(step: Step, code: Int?, message: String?)
        /// The anisette server reported an error or broke the protocol.
        case server(String)
        case timedOut

        /// Whether another anisette server might succeed where this one failed.
        public var isServerSpecific: Bool {
            if case .lookupFailed = self { return false }
            return true
        }

        public var errorDescription: String? {
            switch self
            {
            case .lookupFailed: return "苹果没有返回设备注册地址,请稍后再试"
            case .appleRejected(_, let code, let message):
                var text = "苹果拒绝了这台 Anisette 服务器的设备注册"
                if let code { text += "(\(code))" }
                // Apple's messages end in a full stop, which reads oddly mid-sentence.
                let message = message?.trimmingCharacters(in: CharacterSet(charactersIn: " .。"))
                if let message, !message.isEmpty { text += ":\(message)" }
                return text
            case .server(let detail): return "Anisette 服务器出错:\(detail)"
            case .timedOut: return "设备注册超时"
            }
        }
    }

    public let server: URL
    public let identity: AnisetteIdentity
    /// The 16 random bytes behind `Keychain.identifier`.
    public let identifier: Data
    /// For the exchange with the server, after the lookup.
    public var timeout: TimeInterval = 30

    private let session: URLSession

    public init(server: URL, identity: AnisetteIdentity, identifier: Data, session: URLSession = .shared)
    {
        self.server = server
        self.identity = identity
        self.identifier = identifier
        self.session = session
    }

    /// Runs the whole exchange and returns the adi.pb (base64) the server issues.
    ///
    /// Throws `Failure` for anything the anisette server or Apple's answers are
    /// to blame for; network errors reaching Apple come through as they are.
    public func provision() async throws -> String
    {
        let endpoints = try await self.lookup()
        let timeout = self.timeout

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await self.runSession(start: endpoints.start, finish: endpoints.finish)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw Failure.timedOut
            }
            defer { group.cancelAll() }

            guard let adiPb = try await group.next() else { throw Failure.timedOut }
            return adiPb
        }
    }
}

// MARK: - Device identifiers

public extension AnisetteProvisioner
{
    /// `X-Apple-I-MD-LU`: SHA-256 of the identifier, uppercase hex.
    static func localUserID(for identifier: Data) -> String
    {
        SHA256.hash(data: identifier).map { String(format: "%02X", $0) }.joined()
    }

    /// `X-Mme-Device-Id`: the identifier's 16 bytes read as a UUID.
    static func deviceID(for identifier: Data) -> String?
    {
        guard identifier.count >= 16 else { return nil }

        let b = Array(identifier.prefix(16))
        let uuid = UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                               b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
        return uuid.uuidString.uppercased()
    }
}

// MARK: - Exchange

private extension AnisetteProvisioner
{
    func lookup() async throws -> (start: URL, finish: URL)
    {
        var request = self.appleRequest(URL(string: "https://gsa.apple.com/grandslam/GsService2/lookup")!)
        request.httpMethod = "GET"

        let (data, _) = try await self.session.data(for: request)
        guard let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let urls = plist["urls"] as? [String: Any],
              let start = (urls["midStartProvisioning"] as? String).flatMap(URL.init(string:)),
              let finish = (urls["midFinishProvisioning"] as? String).flatMap(URL.init(string:))
        else { throw Failure.lookupFailed }

        return (start, finish)
    }

    func runSession(start: URL, finish: URL) async throws -> String
    {
        let task = self.session.webSocketTask(with: Self.provisioningSessionURL(for: self.server))
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        return try await withTaskCancellationHandler {
            while true
            {
                let message: URLSessionWebSocketTask.Message
                do
                {
                    message = try await task.receive()
                }
                catch
                {
                    try Task.checkCancellation()
                    throw Failure.server("连接断开(\(error.localizedDescription))")
                }

                let text: String
                switch message
                {
                case .string(let string): text = string
                case .data(let data): text = String(decoding: data, as: UTF8.self)
                @unknown default: continue
                }

                guard let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
                      let result = json["result"] as? String
                else { throw Failure.server("看不懂服务器发来的消息") }

                switch result
                {
                case "GiveIdentifier":
                    try await Self.send(["identifier": self.identifier.base64EncodedString()], on: task)

                case "GiveStartProvisioningData":
                    let (response, status) = try await self.post(to: start, request: [:])
                    guard let spim = response["spim"] as? String else {
                        throw Self.rejection(at: .start, response: response, httpStatus: status)
                    }
                    try await Self.send(["spim": spim], on: task)

                case "GiveEndProvisioningData":
                    guard let cpim = json["cpim"] as? String else { throw Failure.server("没有发来 cpim") }

                    let (response, status) = try await self.post(to: finish, request: ["cpim": cpim])
                    guard let ptm = response["ptm"] as? String, let tk = response["tk"] as? String else {
                        throw Self.rejection(at: .finish, response: response, httpStatus: status)
                    }
                    try await Self.send(["ptm": ptm, "tk": tk], on: task)

                case "ProvisioningSuccess":
                    guard let adiPb = json["adi_pb"] as? String, !adiPb.isEmpty else {
                        throw Failure.server("没有发来 adi.pb")
                    }
                    return adiPb

                default:
                    // Same rule as before: errors end the session, anything else
                    // is informational.
                    if result.contains("Error") || result.contains("Invalid") || ["ClosingPerRequest", "Timeout", "TextOnly"].contains(result)
                    {
                        let message = json["message"] as? String
                        throw Failure.server([result, message].compactMap { $0 }.joined(separator: ": "))
                    }
                }
            }
        } onCancel: {
            task.cancel(with: .goingAway, reason: nil)
        }
    }

    /// POSTs a GrandSlam plist and returns its `Response` dictionary (the whole
    /// plist when there is none) with the HTTP status.
    func post(to url: URL, request body: [String: Any]) async throws -> ([String: Any], Int)
    {
        var request = self.appleRequest(url)
        request.httpMethod = "POST"
        request.httpBody = try PropertyListSerialization.data(fromPropertyList: ["Header": [String: Any](), "Request": body],
                                                              format: .xml, options: 0)

        let (data, response) = try await self.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else {
            return ([:], status)
        }
        return (plist["Response"] as? [String: Any] ?? plist, status)
    }

    func appleRequest(_ url: URL) -> URLRequest
    {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(self.identity.clientInfo, forHTTPHeaderField: "X-Mme-Client-Info")
        request.setValue(self.identity.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/x-xml-plist", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(Self.localUserID(for: self.identifier), forHTTPHeaderField: "X-Apple-I-MD-LU")
        if let deviceID = Self.deviceID(for: self.identifier)
        {
            request.setValue(deviceID, forHTTPHeaderField: "X-Mme-Device-Id")
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        request.setValue(formatter.string(from: Date()), forHTTPHeaderField: "X-Apple-I-Client-Time")
        request.setValue(Locale.current.identifier, forHTTPHeaderField: "X-Apple-Locale")
        request.setValue(TimeZone.current.abbreviation() ?? "UTC", forHTTPHeaderField: "X-Apple-I-TimeZone")
        return request
    }

    static func provisioningSessionURL(for server: URL) -> URL
    {
        let url = server.appendingPathComponent("v3").appendingPathComponent("provisioning_session")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.scheme = components.scheme?.lowercased() == "http" ? "ws" : "wss"
        return components.url ?? url
    }

    static func send(_ object: [String: String], on task: URLSessionWebSocketTask) async throws
    {
        let data = try JSONSerialization.data(withJSONObject: object)
        do
        {
            try await task.send(.string(String(decoding: data, as: UTF8.self)))
        }
        catch
        {
            try Task.checkCancellation()
            throw Failure.server("发送失败(\(error.localizedDescription))")
        }
    }

    /// Apple puts `ec`/`em` in a `Status` dictionary; a page that isn't a
    /// plist at all (an HTML 503) leaves only the HTTP status.
    static func rejection(at step: Failure.Step, response: [String: Any], httpStatus: Int) -> Failure
    {
        let status = response["Status"] as? [String: Any] ?? response
        let code = (status["ec"] as? NSNumber)?.intValue
        let message = status["em"] as? String

        if code == nil, message == nil, httpStatus != 200
        {
            return .appleRejected(step: step, code: nil, message: "HTTP \(httpStatus)")
        }
        return .appleRejected(step: step, code: code, message: message)
    }
}
