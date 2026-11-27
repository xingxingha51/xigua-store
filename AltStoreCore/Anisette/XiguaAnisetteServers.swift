//
//  XiguaAnisetteServers.swift
//  AltStoreCore
//
//  Xigua fork.
//

import Foundation

/// The anisette server list we maintain, instead of SideStore's public one.
///
/// SideStore's list leads with Android-ADI servers (`ani.sidestore.io`, `.app`,
/// `.zip`, …). Since Nov 2026 Apple refuses those at the last provisioning step
/// with -29003 ("possible environment mismatch"), whatever identity the client
/// presents, so a phone working down that list fails before it ever reaches a
/// server that works. Ours holds only servers that passed provisioning, and is
/// published where we can fix it without an app release.
public enum XiguaAnisetteServers
{
    /// Where the list is published, together with the identity override read by
    /// `AnisetteIdentity`. The helper reads the same file.
    public static let listURL = "https://loveipa.com/anisette-servers.json"

    /// What we used to fetch: SideStore's public list.
    public static let legacyListURL = "https://servers.sidestore.io/servers.json"

    /// Used until the published list has been fetched, and when it can't be.
    /// Same servers, same order, as the published file and the helper's presets.
    /// Each passed provisioning with `AnisetteIdentity.builtIn` on 2026-11-27.
    public static let builtIn: [(name: String, address: String)] = [
        ("SideStore (New)", "https://new.ani.sidestore.io"),
        ("StikStore", "https://ani.stikstore.app"),
        ("jkcoxson", "https://mac-ani.jkcoxson.com"),
        ("jkcoxson (Windows ADI)", "https://ani.jkcoxson.com"),
        ("Lill q", "https://anisette.lillq.me"),
    ]

    public static var defaultServer: String { builtIn[0].address }

    /// Servers that can't register a device for us any more. An imported account
    /// pinned to one isn't pinned (its adi.pb is replaced on first use anyway).
    private static let retiredHosts: Set<String> = [
        // Android-ADI: refused at provisioning (-29003) since Nov 2026.
        "ani.sidestore.io", "ani.sidestore.app", "ani.sidestore.zip", "ani.846969.xyz",
        "ani.xu30.top", "anisette.wedotstud.io", "ani.npeg.us", "ani.uwucloud.fun",
        "ani.sjwon0368.dpdns.org", "ani.idevicehacked.com", "ani3server.fly.dev",
        "ani.jaydenha.uk", "anisette.crystall1ne.dev", "omni.ethxn.xyz",
        // Gone.
        "ani.neoarz.xyz", "ani.neoarz.com", "ani.owoellen.rocks", "win.ani.sidestore.io",
    ]

    public static func isRetired(_ address: String) -> Bool
    {
        guard let host = URL(string: self.normalize(address))?.host?.lowercased() else { return false }
        return self.retiredHosts.contains(host)
    }

    /// `ani.example.com`, `https://ani.example.com/` → `https://ani.example.com`,
    /// the form the server list uses. The helper may export either.
    public static func normalize(_ address: String) -> String
    {
        var trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }

        let lowercased = trimmed.lowercased()
        guard !trimmed.isEmpty, !lowercased.hasPrefix("http://"), !lowercased.hasPrefix("https://") else { return trimmed }
        return "https://" + trimmed
    }

    /// For the one-time move onto our list: our servers in our order, carrying
    /// over whether the user had hidden one, and dropping everything else.
    public static func reseed(existing: [(address: String, isHidden: Bool)]) -> [(name: String, address: String, isHidden: Bool)]
    {
        var reseeded = self.builtIn.map { server in
            let hidden = existing.first { self.normalize($0.address) == server.address }?.isHidden ?? false
            return (name: server.name, address: server.address, isHidden: hidden)
        }

        // Hiding every one of them would leave nothing to sign in with.
        if reseeded.allSatisfy(\.isHidden)
        {
            reseeded = reseeded.map { (name: $0.name, address: $0.address, isHidden: false) }
        }

        return reseeded
    }
}
