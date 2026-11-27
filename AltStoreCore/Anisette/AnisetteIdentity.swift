//
//  AnisetteIdentity.swift
//  AltStoreCore
//
//  Xigua fork.
//

import Foundation

/// The device identity we present to Apple: `X-Mme-Client-Info` everywhere,
/// plus the `User-Agent` of the provisioning requests.
///
/// Until Nov 2026 this was whatever the anisette server reported from
/// `/v3/client_info`. Apple has been refusing those identities one by one:
///
/// - Sept 2026: `com.apple.dt.Xcode` → HTTP 503 at sign-in.
/// - 2026-11-20: anything spelled `<macOS;…>` → HTTP 503 at sign-in. That is
///   what every Android-ADI server reports (`ani.sidestore.io`, `.app`, `.zip`…).
/// - The `<Mac OS X;10.12.6;…>` of the Mac-based servers gets past that, but
///   many accounts are then refused with -22410, or -23782 ("A Mac with macOS
///   version 10.13 or later is required"). See nab138/iloader#1205.
///
/// A current macOS release in the old `Mac OS X;` spelling works, so we send our
/// own identity whatever the server says. A copy published with our server list
/// takes precedence over the built-in one, so the next time Apple moves the
/// goalposts the fix doesn't need an app release. That matters here: a phone
/// that can't sign in can't refresh this app either.
///
/// adi.pb has to be used with the identity it was provisioned under (Apple
/// answers -22410 otherwise), so a change here makes the device provision again.
/// See `Keychain.adiPbClientInfo`.
public struct AnisetteIdentity: Equatable, Sendable
{
    public let clientInfo: String
    public let userAgent: String

    /// macOS 27.2.1 (26B131), the build this was verified against on 2026-11-27.
    ///
    /// Keep identical to the helper's built-in copy (sideload-helper,
    /// `src-tauri/src/anisette_identity.rs`) and to the file published at
    /// `XiguaAnisetteServers.listURL`. Accounts exported from the helper carry
    /// adi.pb provisioned under it; a phone on a different identity has to
    /// provision again, which costs the user another 2FA prompt.
    public static let builtIn = AnisetteIdentity(
        clientInfo: "<MacBookPro18,3> <Mac OS X;27.2.1;26B131> <com.apple.AuthKit/1 (com.apple.akd/1.0)>",
        userAgent: "akd/1.0 CFNetwork/3896.200.61 Darwin/27.2.0"
    )

    private init(clientInfo: String, userAgent: String)
    {
        self.clientInfo = clientInfo
        self.userAgent = userAgent
    }

    /// Builds an identity from untrusted input, or returns nil unless both values
    /// can go into an HTTP header and the client info has the
    /// `<model> <os;version;build> <framework (app)>` shape.
    ///
    /// Deliberately says nothing about *which* OS spelling or version: that is
    /// exactly what Apple keeps changing, and the remote copy exists to follow it.
    public static func validated(clientInfo: String, userAgent: String) -> AnisetteIdentity?
    {
        guard isHeaderSafe(clientInfo, maxLength: 256),
              isHeaderSafe(userAgent, maxLength: 256),
              clientInfo.range(of: #"^<[^<>]+> <[^<>]+> <[^<>]+>$"#, options: .regularExpression) != nil
        else { return nil }

        return AnisetteIdentity(clientInfo: clientInfo, userAgent: userAgent)
    }

    private static func isHeaderSafe(_ value: String, maxLength: Int) -> Bool
    {
        guard !value.isEmpty, value.count <= maxLength else { return false }
        // Printable ASCII only: no control characters, so no header injection.
        return value.unicodeScalars.allSatisfy { (0x20..<0x7F).contains($0.value) }
    }
}

// MARK: - Published copy

public extension AnisetteIdentity
{
    private static let publishedClientInfoKey = "XiguaAnisetteIdentity.clientInfo"
    private static let publishedUserAgentKey = "XiguaAnisetteIdentity.userAgent"

    /// The identity to use now: the published one when we hold a valid copy,
    /// otherwise `builtIn`.
    static var current: AnisetteIdentity { self.current(in: .standard) }

    static func current(in defaults: UserDefaults) -> AnisetteIdentity
    {
        guard let clientInfo = defaults.string(forKey: publishedClientInfoKey),
              let userAgent = defaults.string(forKey: publishedUserAgentKey),
              let identity = validated(clientInfo: clientInfo, userAgent: userAgent)
        else { return .builtIn }

        return identity
    }

    /// Applies the `identity` object of our published server list.
    ///
    /// A valid one is adopted. A missing one goes back to `builtIn`, so
    /// deleting it from the file is how an override is withdrawn. An invalid
    /// one is ignored, so a typo in the file can't lock every phone out.
    ///
    /// - Returns: Whether `current` changed.
    @discardableResult
    static func applyPublished(serverList data: Data, to defaults: UserDefaults = .standard) -> Bool
    {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }

        let before = self.current(in: defaults)

        if let published = root["identity"]
        {
            guard let object = published as? [String: Any],
                  let clientInfo = object["clientInfo"] as? String,
                  let userAgent = object["userAgent"] as? String,
                  let identity = validated(clientInfo: clientInfo, userAgent: userAgent)
            else { return false }

            self.store(identity, in: defaults)
        }
        else
        {
            self.store(nil, in: defaults)
        }

        return self.current(in: defaults) != before
    }

    private static func store(_ identity: AnisetteIdentity?, in defaults: UserDefaults)
    {
        if let identity, identity != .builtIn
        {
            defaults.set(identity.clientInfo, forKey: publishedClientInfoKey)
            defaults.set(identity.userAgent, forKey: publishedUserAgentKey)
        }
        else
        {
            defaults.removeObject(forKey: publishedClientInfoKey)
            defaults.removeObject(forKey: publishedUserAgentKey)
        }
    }
}
