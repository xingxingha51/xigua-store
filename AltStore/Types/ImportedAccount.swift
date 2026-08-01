//
//  ImportedAccount.swift
//  AltStore
//
//  Created by ny on 9/7/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import Foundation

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
}
