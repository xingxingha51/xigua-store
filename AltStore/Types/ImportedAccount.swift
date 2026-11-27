//
//  ImportedAccount.swift
//  AltStore
//
//  Created by ny on 9/7/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import Foundation
import AltStoreCore

struct ImportedAccount: Codable {
    let email: String
    let password: String
    let cert: Data
    let certpass: String
    let local_user: String
    let adiPB: String

    /// Which anisette server issued `adiPB`. Optional so files written before
    /// the helper started emitting it still decode.
    ///
    /// adi.pb is provisioned against one specific server's ADI instance —
    /// replaying it elsewhere produces anisette Apple rejects, and the sign-in
    /// just fails. Without this the store picks the first reachable entry from
    /// a ten-server public list, which is usually not the one that issued it.
    let anisetteServer: String?

    /// The `X-Mme-Client-Info` `adiPB` was provisioned under (helper 1.0.6+).
    ///
    /// Apple refuses adi.pb presented with any other identity (-22410), so it is
    /// only reused while this matches `AnisetteIdentity.current`. Older files
    /// don't say; their adi.pb was provisioned under the server's own identity,
    /// which Apple no longer accepts, and gets replaced on first use.
    let anisetteClientInfo: String?
}

extension ImportedAccount
{
    /// Writes the anisette half of the account — identifier and adi.pb, tagged
    /// with the server and identity the adi.pb was provisioned for — and makes
    /// that server the preferred one.
    ///
    /// - Returns: The server to add to the list if it isn't there yet, or nil
    ///   when there is none worth pinning.
    func storeAnisetteState() -> String?
    {
        let keychain = Keychain.shared
        keychain.identifier = self.local_user
        keychain.adiPb = self.adiPB
        keychain.adiPbServer = self.anisetteServer.map(XiguaAnisetteServers.normalize)
        keychain.adiPbClientInfo = self.anisetteClientInfo

        // FetchAnisetteDataOperation starts from menuAnisetteURL, so this puts
        // the issuing server first in line while still falling through to
        // another if it's down. A retired one can't serve us; its adi.pb gets
        // replaced at whichever server does.
        guard let server = keychain.adiPbServer, !server.isEmpty, !XiguaAnisetteServers.isRetired(server) else { return nil }

        UserDefaults.standard.menuAnisetteURL = server
        return server
    }

    /// For logs: never the password, certificate or adi.pb.
    var logDescription: String {
        "\(self.email) (anisette server: \(self.anisetteServer ?? "none"), client info: \(self.anisetteClientInfo ?? "none"))"
    }
}
