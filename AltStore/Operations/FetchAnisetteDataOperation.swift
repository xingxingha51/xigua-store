//
//  FetchAnisetteDataOperation.swift
//  AltStore
//
//  Created by Riley Testut on 1/7/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import UIKit
import Foundation
import AltStoreCore
import AltSign

class ANISETTE_VERBOSITY: Operation {} // dummy tag iface

@objc(FetchAnisetteDataOperation)
final class FetchAnisetteDataOperation: ResultOperation<ALTAnisetteData>, OperationLogging {

    let context: OperationContext

    /// The anisette server in use.
    var url: URL?

    /// What we present to Apple instead of the server's own client info.
    /// See AnisetteIdentity for why.
    private let identity = AnisetteIdentity.current

    init(context: OperationContext) {
        self.context = context
    }

    override func main() {
        super.main()

        Task {
            do {
                try await self.execute()
            } catch {
                self.finish(.failure(error))
            }
        }
    }

    /// Works down the server list from the preferred one. A server that can't
    /// register a device for us (Apple has refused every Android-ADI server
    /// since Nov 2026) hands over to the next one instead of failing the
    /// operation; any other error still ends it.
    private nonisolated func execute() async throws {
        if let error = self.context.error {
            throw error
        }

        // TODO: Pass in proper view context to show the Toast messages
        let viewContext = self.context.presentingViewController
        self.verboseLog("Client-Info: \(self.identity.clientInfo)")

        let servers = await AnisetteServersManager.shared.getActiveServerURLs()
        guard !servers.isEmpty else {
            throw NSError(domain: "AnisetteError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No anisette servers configured."])
        }

        let startIndex = servers.firstIndex(of: UserDefaults.standard.menuAnisetteURL) ?? 0
        let ordered = Array(servers[startIndex...] + servers[..<startIndex])

        var lastFailure: AnisetteProvisioner.Failure?

        for (triedCount, address) in ordered.enumerated() {
            guard let url = URL(string: address) else {
                self.verboseLog("Skipping invalid URL: \(address)")
                continue
            }
            let name = url.host ?? address

            do {
                guard try await self.pingServer(url) else {
                    self.verboseLog("Failed to reach server: \(address), trying next server.")
                    self.showToast(viewContext, "连不上 Anisette 服务器 \(name),换下一台试试…")
                    continue
                }
            } catch {
                self.verboseLog("Error reaching server: \(address) (\(error.localizedDescription)), trying next server.")
                self.showToast(viewContext, "连不上 Anisette 服务器 \(name),换下一台试试…")
                continue
            }

            self.url = url
            UserDefaults.standard.menuAnisetteURL = address
            self.verboseLog("Anisette URL: \(address)")
            if triedCount > 0 {
                self.showToast(viewContext, "改用 Anisette 服务器 \(name)")
            }

            do {
                let anisetteData = try await self.fetchAnisetteData(from: address)
                self.finish(.success(anisetteData))
                return
            } catch let failure as AnisetteProvisioner.Failure where failure.isServerSpecific {
                self.debugLog("Anisette server \(address) failed: \(failure.localizedDescription). Trying the next server.")
                lastFailure = failure
                self.showToast(viewContext, "\(name) 用不了(\(failure.localizedDescription)),换下一台试试…")
            }
        }

        // A corrected list, or identity, may already be published.
        Task {
            await AnisetteServersManager.shared.syncOnFailureIfNeeded()
        }

        if let lastFailure {
            throw OperationError.provisioningError(result: "试过的 Anisette 服务器都不能用", message: "(最后一台:\(lastFailure.localizedDescription))")
        }

        // Nothing was reachable. Start from the next server next time, so
        // retries cycle through the list.
        UserDefaults.standard.menuAnisetteURL = ordered[ordered.count > 1 ? 1 : 0]
        throw NSError(domain: "AnisetteError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No valid server found."])
    }

    private func showToast(_ viewContext: UIViewController?, _ message: String) {
        guard let viewContext else { return }
        Task { @MainActor in
            ToastView(text: message, detailText: nil).show(in: viewContext)
        }
    }

    private func pingServer(_ url: URL) async throws -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10 // Timeout after 10 seconds

        let (_, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode

        guard let statusCode = statusCode,
              (200...299).contains(statusCode) else {
            return false
        }

        return true
    }

    // MARK: - V3

    private struct DeviceIdentifier {
        let base64: String
        let data: Data
    }

    private enum AnisetteV3Error: Error {
        /// -45061: the server has no record of this adi.pb.
        case notProvisioned
    }

    /// Anisette from the server at `address`: straight from the stored adi.pb
    /// when this server issued it under the current identity, otherwise after
    /// provisioning anew.
    ///
    /// Throws `AnisetteProvisioner.Failure` when the server can't serve us, so
    /// the caller can move on to the next one.
    private func fetchAnisetteData(from address: String) async throws -> ALTAnisetteData {
        guard try await self.isV3Server() else {
            return try await self.handleV1()
        }

        let identifier = try self.deviceIdentifier()
        let keychain = Keychain.shared
        let server = XiguaAnisetteServers.normalize(address)

        if let adiPb = keychain.adiPb {
            let issuer = keychain.adiPbServer.map(XiguaAnisetteServers.normalize)
            if issuer == server && keychain.adiPbClientInfo == self.identity.clientInfo {
                do {
                    return try await self.fetchAnisetteV3(identifier: identifier, adiPb: adiPb)
                } catch AnisetteV3Error.notProvisioned {
                    self.verboseLog("The server has no record of our adi.pb (-45061); provisioning again")
                    keychain.adiPb = nil
                }
            } else {
                // Kept until a new one is issued: should provisioning fail
                // here, it still works at the server that issued it.
                self.verboseLog("adi.pb was issued by \(issuer ?? "an unrecorded server") under \(keychain.adiPbClientInfo ?? "an unrecorded identity"); provisioning again at \(server)")
            }
        }

        self.verboseLog("Provisioning at \(server)")
        let adiPb = try await AnisetteProvisioner(server: self.url!, identity: self.identity, identifier: identifier.data).provision()
        keychain.adiPb = adiPb
        keychain.adiPbServer = server
        keychain.adiPbClientInfo = self.identity.clientInfo
        keychain.adiPbIDCase = AnisetteIdentifierCase.ours.rawValue
        self.debugLog("Provisioning succeeded at \(server)")

        return try await self.fetchAnisetteV3(identifier: identifier, adiPb: adiPb)
    }

    /// The identifier anisette is generated for, created on first use.
    private func deviceIdentifier() throws -> DeviceIdentifier {
        if let stored = Keychain.shared.identifier,
           let data = Data(base64Encoded: stored), data.count >= 16 {
            return DeviceIdentifier(base64: stored, data: data)
        }

        self.verboseLog("Generating identifier")
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            self.debugLog("ERROR GENERATING IDENTIFIER!!! \(status)")
            throw OperationError.provisioningError(result: "Couldn't generate identifier", message: nil)
        }

        let data = Data(bytes)
        let base64 = data.base64EncodedString()
        Keychain.shared.identifier = base64
        // An adi.pb belongs to the identifier it was provisioned for.
        Keychain.shared.adiPb = nil
        return DeviceIdentifier(base64: base64, data: data)
    }

    /// V3 servers answer /v3/client_info. What they report there is no longer
    /// sent to Apple, but it is logged: it shows what kind of server this is.
    private func isV3Server() async throws -> Bool {
        var request = URLRequest(url: self.url!.appendingPathComponent("v3").appendingPathComponent("client_info"))
        request.timeoutInterval = 15

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code != .cancelled {
            throw AnisetteProvisioner.Failure.server(error.localizedDescription)
        }

        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            // An error page: the server is down even though its front page answered.
            throw AnisetteProvisioner.Failure.server("/v3/client_info 返回的不是 JSON")
        }

        guard let serverClientInfo = json["client_info"] as? String else { return false }

        self.verboseLog("Server is V3. It reports Client-Info: \(serverClientInfo), User-Agent: \(json["user_agent"] as? String ?? "none")")
        return true
    }

    private func fetchAnisetteV3(identifier: DeviceIdentifier, adiPb: String) async throws -> ALTAnisetteData {
        self.verboseLog("Fetching anisette V3")
        var request = URLRequest(url: self.url!.appendingPathComponent("v3").appendingPathComponent("get_headers"))
        request.timeoutInterval = 15
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "identifier": identifier.base64,
            "adi_pb": adiPb
        ], options: [])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        return try self.extractAnisetteData(data, response as? HTTPURLResponse, v3: true, identifier: identifier)
    }

    // MARK: - COMMON

    private func extractAnisetteData(_ data: Data, _ response: HTTPURLResponse?, v3: Bool, identifier: DeviceIdentifier? = nil) throws -> ALTAnisetteData {
        // make sure this JSON is in the format we expect
        guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: String] else {
            if v3 {
                throw OperationError.anisetteV3Error(message: "Invalid anisette (the returned data may not be in JSON)")
            } else {
                throw OperationError.anisetteV1Error(message: "Invalid anisette (the returned data may not be in JSON)")
            }
        }

        if v3, json["result"] == "GetHeadersError" {
            let message = json["message"]
            self.verboseLog("Error getting V3 headers: \(message ?? "no message")")
            if let message, message.contains("-45061") {
                throw AnisetteV3Error.notProvisioned
            }
            throw OperationError.anisetteV3Error(message: message ?? "Unknown error")
        }

        // for some reason serial number isn't needed but it doesn't work unless it has a value
        var formattedJSON: [String: String] = ["deviceSerialNumber": "0"]
        if let machineID = json["X-Apple-I-MD-M"] { formattedJSON["machineID"] = machineID }
        if let oneTimePassword = json["X-Apple-I-MD"] { formattedJSON["oneTimePassword"] = oneTimePassword }
        if let routingInfo = json["X-Apple-I-MD-RINFO"] { formattedJSON["routingInfo"] = routingInfo }

        if v3, let identifier {
            // Spelled as when the adi.pb was provisioned, or Apple answers -22410.
            let idCase = AnisetteIdentifierCase.ofStored(declared: Keychain.shared.adiPbIDCase,
                                                         hasClientInfoTag: Keychain.shared.adiPbClientInfo != nil)
            formattedJSON["deviceDescription"] = self.identity.clientInfo
            formattedJSON["localUserID"] = AnisetteProvisioner.localUserID(for: identifier.data, case: idCase)
            formattedJSON["deviceUniqueIdentifier"] = AnisetteProvisioner.deviceID(for: identifier.data, case: idCase)

            // Generate date stuff on client
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone.init(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            let dateString = formatter.string(from: Date())
            formattedJSON["date"] = dateString
            formattedJSON["locale"] = Locale.current.identifier
            formattedJSON["timeZone"] = TimeZone.current.abbreviation()
        } else {
            if let deviceDescription = json["X-MMe-Client-Info"] { formattedJSON["deviceDescription"] = deviceDescription }
            if let localUserID = json["X-Apple-I-MD-LU"] { formattedJSON["localUserID"] = localUserID }
            if let deviceUniqueIdentifier = json["X-Mme-Device-Id"] { formattedJSON["deviceUniqueIdentifier"] = deviceUniqueIdentifier }

            if let date = json["X-Apple-I-Client-Time"] { formattedJSON["date"] = date }
            if let locale = json["X-Apple-Locale"] { formattedJSON["locale"] = locale }
            if let timeZone = json["X-Apple-I-TimeZone"] { formattedJSON["timeZone"] = timeZone }
        }

        if let response = response,
           let version = response.value(forHTTPHeaderField: "Implementation-Version") {
            self.verboseLog("Implementation-Version: \(version)")
        } else { self.verboseLog("No Implementation-Version header") }

        self.verboseLog("Anisette used: \(formattedJSON)")
        self.verboseLog("Original JSON: \(json)")
        guard let anisette = ALTAnisetteData(json: formattedJSON) else {
            self.debugLog("Anisette is invalid!!!!")
            if v3 {
                throw OperationError.anisetteV3Error(message: "Invalid anisette (the returned data may not have all the required fields)")
            } else {
                throw OperationError.anisetteV1Error(message: "Invalid anisette (the returned data may not have all the required fields)")
            }
        }

        self.debugLog("Anisette is valid!")
        return anisette
    }

    // MARK: - V1

    private func handleV1() async throws -> ALTAnisetteData {
        self.verboseLog("Server is V1")

        if UserDefaults.shared.trustedServerURL == AnisetteManager.currentURLString {
            self.verboseLog("Server has already been trusted, fetching anisette")
            return try await self.fetchAnisetteV1()
        }

        self.debugLog("Alerting user about outdated server")

        let proceed: Bool = await withCheckedContinuation { continuation in
            Task { @MainActor in
                let alert = UIAlertController(title: "WARNING: Outdated anisette server", message: "We've detected you are using an older anisette server. Using this server has a higher likelihood of locking your account and causing other issues. Are you sure you want to continue?", preferredStyle: UIAlertController.Style.alert)
                alert.addAction(UIAlertAction(title: "Continue", style: UIAlertAction.Style.destructive, handler: { _ in
                    continuation.resume(returning: true)
                }))
                alert.addAction(UIAlertAction(title: "Cancel", style: UIAlertAction.Style.cancel, handler: { _ in
                    continuation.resume(returning: false)
                }))

                let keyWindow = UIApplication.shared.windows.filter { $0.isKeyWindow }.first
                if let presentingController = keyWindow?.rootViewController?.presentedViewController {
                    presentingController.present(alert, animated: true)
                } else {
                    keyWindow?.rootViewController?.present(alert, animated: true)
                }
            }
        }

        guard proceed else {
            self.debugLog("Cancelled anisette operation")
            throw OperationError.cancelled
        }

        self.verboseLog("Fetching anisette via V1")
        UserDefaults.shared.trustedServerURL = AnisetteManager.currentURLString
        return try await self.fetchAnisetteV1()
    }

    private func fetchAnisetteV1() async throws -> ALTAnisetteData {
        self.verboseLog("Fetching anisette V1")
        let (data, response) = try await URLSession.shared.data(from: self.url!)
        return try self.extractAnisetteData(data, response as? HTTPURLResponse, v3: false)
    }
}
