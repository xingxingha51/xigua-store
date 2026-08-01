//
//  FileManager+SharedDirectories.swift
//  AltStore
//
//  Created by Riley Testut on 5/14/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

public extension FileManager
{
    /// Where this app keeps its own persistent state.
    ///
    /// Deliberately *not* the app group container. The group identifier depends
    /// on who signed the app — the store appends the team ID when it re-signs
    /// (FetchProvisioningProfilesOperation), the desktop helper does not — so a
    /// group-backed path silently points at a different container depending on
    /// which installer was used last. That is how the database and the saved
    /// Apple ID appeared to vanish after updating in-store.
    ///
    /// The app's own container only depends on the bundle identifier, which both
    /// installers produce identically.
    var altstoreDataDirectory: URL {
        return self.applicationSupportDirectory
    }

    /// The app group container, or nil when the entitlement isn't present.
    ///
    /// Only for handing files to SideBackup, which is a separate app and can't
    /// see our container. Both are always installed by the store, so they agree
    /// on the identifier. Never use this for state we need to keep.
    var altstoreSharedDirectory: URL? {
        guard let appGroup = Bundle.main.altstoreAppGroup else {
            return nil
        }
        
        let sharedDirectoryURL = self.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        return sharedDirectoryURL
    }
    
    var appBackupsDirectory: URL? {
        let appBackupsDirectory = self.altstoreSharedDirectory?.appendingPathComponent("Backups", isDirectory: true)
        return appBackupsDirectory
    }
    
    func backupDirectoryURL(for app: InstalledApp) -> URL?
    {
        let backupDirectoryURL = self.appBackupsDirectory?.appendingPathComponent(app.bundleIdentifier, isDirectory: true)
        return backupDirectoryURL
    }
}
