//
//  AnisetteTests.swift
//  XiguaTests
//

import XCTest
import AltStoreCore

/// 2026-11-20 起苹果拒绝 `macOS;` 写法的身份(登录时直接 503),Android 方案的
/// Anisette 服务器在设备注册最后一步被拒(-29003)。应对办法是:身份串由我们自己
/// 发(内置一份,网站上可以远程替换),服务器只用能完成注册的那几台。
///
/// 这几组钉住它赖以成立的前提。
final class AnisetteIdentityTests: XCTestCase
{
    private let suiteName = "XiguaTests.AnisetteIdentity"
    private var defaults: UserDefaults!

    private let newerClientInfo = "<Mac1,1> <Mac OS X;28.0;27A1> <com.apple.AuthKit/1 (com.apple.akd/1.0)>"
    private var newerIdentityJSON: String {
        #"{"clientInfo":"\#(newerClientInfo)","userAgent":"akd/1.0 CFNetwork/4000 Darwin/28.0.0"}"#
    }

    override func setUp()
    {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown()
    {
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func serverList(identity: String?) -> Data
    {
        Data(#"{"servers":[]\#(identity.map { #","identity":\#($0)"# } ?? "")}"#.utf8)
    }

    /// 苹果现在认的写法:`Mac OS X;` 加 akd。`macOS;` 从 11-20 起被 503,
    /// Xcode 身份从 9 月起被 503。
    func testBuiltInUsesTheSpellingAppleAccepts()
    {
        let clientInfo = AnisetteIdentity.builtIn.clientInfo
        XCTAssertTrue(clientInfo.contains("<Mac OS X;"))
        XCTAssertFalse(clientInfo.contains("macOS;"))
        XCTAssertTrue(clientInfo.hasSuffix("(com.apple.akd/1.0)>"))
    }

    func testBuiltInPassesItsOwnValidation()
    {
        let builtIn = AnisetteIdentity.builtIn
        XCTAssertEqual(AnisetteIdentity.validated(clientInfo: builtIn.clientInfo, userAgent: builtIn.userAgent), builtIn)
    }

    /// 这串要原样进 HTTP 头:换行(头注入)、非 ASCII、形状不对的一律不收。
    func testValidationRejectsMalformedValues()
    {
        let userAgent = AnisetteIdentity.builtIn.userAgent
        for bad in ["", "<a> <b>", "<a> <b> <c> <d>", "<a>  <b> <c>", "<a> <b> <c> ", "<> <b> <c>",
                    "<a<b> <c> <d>", "<a> <b> <c>\r\nX-Injected: 1", "<a> <b> <c>é"]
        {
            XCTAssertNil(AnisetteIdentity.validated(clientInfo: bad, userAgent: userAgent), bad)
        }

        let clientInfo = AnisetteIdentity.builtIn.clientInfo
        XCTAssertNil(AnisetteIdentity.validated(clientInfo: clientInfo, userAgent: ""))
        XCTAssertNil(AnisetteIdentity.validated(clientInfo: clientInfo, userAgent: "akd\n"))
        XCTAssertNil(AnisetteIdentity.validated(clientInfo: "<\(String(repeating: "a", count: 300))> <b> <c>", userAgent: userAgent))
    }

    func testFreshInstallUsesBuiltIn()
    {
        XCTAssertEqual(AnisetteIdentity.current(in: defaults), .builtIn)
    }

    /// 苹果下次再改规则时,改网站上的文件就能让手机换身份,不用发版。
    func testPublishedIdentityIsAdopted()
    {
        XCTAssertTrue(AnisetteIdentity.applyPublished(serverList: serverList(identity: newerIdentityJSON), to: defaults))
        XCTAssertEqual(AnisetteIdentity.current(in: defaults).clientInfo, newerClientInfo)
        XCTAssertEqual(AnisetteIdentity.current(in: defaults).userAgent, "akd/1.0 CFNetwork/4000 Darwin/28.0.0")
    }

    /// 从文件里删掉 identity 就是撤回覆盖,回到内置的。
    func testRemovingThePublishedIdentityRevertsToBuiltIn()
    {
        AnisetteIdentity.applyPublished(serverList: serverList(identity: newerIdentityJSON), to: defaults)

        XCTAssertTrue(AnisetteIdentity.applyPublished(serverList: serverList(identity: nil), to: defaults))
        XCTAssertEqual(AnisetteIdentity.current(in: defaults), .builtIn)
    }

    /// 文件写错了不能把所有手机都锁在外面:不合法的值直接忽略,保留原来那个。
    func testInvalidPublishedIdentityIsIgnored()
    {
        AnisetteIdentity.applyPublished(serverList: serverList(identity: newerIdentityJSON), to: defaults)

        for invalid in [#"{"clientInfo":"oops","userAgent":"x"}"#, #""<a> <b> <c>""#, #"{"clientInfo":"<a> <b> <c>"}"#]
        {
            XCTAssertFalse(AnisetteIdentity.applyPublished(serverList: serverList(identity: invalid), to: defaults), invalid)
            XCTAssertEqual(AnisetteIdentity.current(in: defaults).clientInfo, newerClientInfo, invalid)
        }

        XCTAssertFalse(AnisetteIdentity.applyPublished(serverList: Data("<html>502</html>".utf8), to: defaults))
        XCTAssertEqual(AnisetteIdentity.current(in: defaults).clientInfo, newerClientInfo)
    }

    /// 发布的就是内置那份时不留痕迹,以后内置的更新了能直接生效。
    func testPublishingTheBuiltInIdentityStoresNothing()
    {
        let builtIn = AnisetteIdentity.builtIn
        let json = #"{"clientInfo":"\#(builtIn.clientInfo)","userAgent":"\#(builtIn.userAgent)"}"#
        AnisetteIdentity.applyPublished(serverList: serverList(identity: json), to: defaults)

        XCTAssertNil(defaults.string(forKey: "XiguaAnisetteIdentity.clientInfo"))
        XCTAssertEqual(AnisetteIdentity.current(in: defaults), builtIn)
    }
}

final class AnisetteProvisionerTests: XCTestCase
{
    /// 和原来 FetchAnisetteDataOperation 的算法一致(CC_SHA256 加 "%02hhX",16 字节
    /// 按 UUID 读)。算法变了,已经注册过的设备在苹果那边就对不上号了。
    func testDeviceIdentifiersMatchTheOriginalDerivation()
    {
        let identifier = Data(0..<16)
        XCTAssertEqual(AnisetteProvisioner.localUserID(for: identifier),
                       "BE45CB2605BF36BEBDE684841A28F0FD43C69850A3DCE5FEDBA69928EE3A8991")
        XCTAssertEqual(AnisetteProvisioner.deviceID(for: identifier), "00010203-0405-0607-0809-0A0B0C0D0E0F")
        XCTAssertNil(AnisetteProvisioner.deviceID(for: Data(0..<8)))
    }

    /// 只有"苹果的查询接口没给地址"跟服务器无关,换服务器没用;其余失败都换下一台。
    func testOnlyLookupFailureIsNotServerSpecific()
    {
        XCTAssertFalse(AnisetteProvisioner.Failure.lookupFailed.isServerSpecific)
        XCTAssertTrue(AnisetteProvisioner.Failure.appleRejected(step: .finish, code: -29003, message: nil).isServerSpecific)
        XCTAssertTrue(AnisetteProvisioner.Failure.server("x").isServerSpecific)
        XCTAssertTrue(AnisetteProvisioner.Failure.timedOut.isServerSpecific)
    }

    /// 截图里那条报错的新说法。苹果的原文末尾带英文句号,拼进中文里会变成".。"。
    func testRejectionReadsCleanly()
    {
        let failure = AnisetteProvisioner.Failure.appleRejected(step: .finish, code: -29003,
                                                                message: "This action could not be completed due to possible environment mismatch.")
        XCTAssertEqual(failure.localizedDescription,
                       "苹果拒绝了这台 Anisette 服务器的设备注册(-29003):This action could not be completed due to possible environment mismatch")
    }

    // MARK: - 联网(默认跳过)

    private func skipUnlessNetworkTestsEnabled() throws
    {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["XIGUA_NETWORK_TESTS"] == "1",
                          "联网测试:设置 TEST_RUNNER_XIGUA_NETWORK_TESTS=1 才跑")
    }

    private func randomIdentifier() -> Data
    {
        Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
    }

    /// 默认服务器能用我们的身份完成注册。走的是真实的苹果接口,但不涉及 Apple ID。
    func testProvisioningSucceedsAtTheDefaultServer() async throws
    {
        try skipUnlessNetworkTestsEnabled()

        let server = try XCTUnwrap(URL(string: XiguaAnisetteServers.defaultServer))
        let adiPb = try await AnisetteProvisioner(server: server, identity: .builtIn, identifier: randomIdentifier()).provision()
        XCTAssertFalse(adiPb.isEmpty)
    }

    /// 截图里的报错就是这么来的:Android 方案的服务器在最后一步被苹果拒绝(-29003)。
    /// 这必须被认成"换一台再试",而不是让整个操作失败。
    func testAndroidADIServerIsRejectedAsServerSpecific() async throws
    {
        try skipUnlessNetworkTestsEnabled()

        do
        {
            _ = try await AnisetteProvisioner(server: URL(string: "https://ani.sidestore.zip")!, identity: .builtIn,
                                              identifier: randomIdentifier()).provision()
            XCTFail("ani.sidestore.zip 注册成功了:苹果可能又改了规则,该重新检查服务器列表")
        }
        catch let failure as AnisetteProvisioner.Failure
        {
            guard case .appleRejected(.finish, .some(-29003), _) = failure else { return XCTFail("意外的失败:\(failure)") }
            XCTAssertTrue(failure.isServerSpecific)
        }
    }

    /// 网站上发布的列表能解析,内容和内置的一致。不一致的话,手机拿到的服务器、
    /// 身份串会和电脑助手的不一样。
    func testPublishedListMatchesBuiltIn() async throws
    {
        try skipUnlessNetworkTestsEnabled()

        let (data, response) = try await URLSession.shared.data(from: try XCTUnwrap(URL(string: XiguaAnisetteServers.listURL)))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)

        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let addresses = try XCTUnwrap(root["servers"] as? [[String: Any]]).compactMap { $0["address"] as? String }
        XCTAssertEqual(addresses, XiguaAnisetteServers.builtIn.map(\.address))

        let suiteName = "XiguaTests.PublishedList"
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        AnisetteIdentity.applyPublished(serverList: data, to: defaults)
        XCTAssertEqual(AnisetteIdentity.current(in: defaults), .builtIn)
    }
}

final class XiguaAnisetteServersTests: XCTestCase
{
    func testNormalize()
    {
        XCTAssertEqual(XiguaAnisetteServers.normalize("ani.stikstore.app"), "https://ani.stikstore.app")
        XCTAssertEqual(XiguaAnisetteServers.normalize(" https://ani.stikstore.app/ "), "https://ani.stikstore.app")
        XCTAssertEqual(XiguaAnisetteServers.normalize("http://5.249.163.88:6969"), "http://5.249.163.88:6969")
        XCTAssertEqual(XiguaAnisetteServers.normalize(""), "")
    }

    /// 截图里那台(ani.sidestore.zip)和排在它前面的两台都在淘汰名单里;
    /// 大小写、末尾斜杠、没写 https 都认得出来。
    func testRetiredServersAreRecognisedHoweverWritten()
    {
        for address in ["https://ani.sidestore.io", "ani.sidestore.app", "HTTPS://ANI.SIDESTORE.ZIP/", "https://ani.846969.xyz"]
        {
            XCTAssertTrue(XiguaAnisetteServers.isRetired(address), address)
        }
    }

    /// 内置列表本身:地址是规范形式、没有重复、一台都不在淘汰名单里,默认就是第一台。
    func testBuiltInListIsUsable()
    {
        let addresses = XiguaAnisetteServers.builtIn.map(\.address)
        XCTAssertFalse(addresses.isEmpty)
        XCTAssertEqual(Set(addresses).count, addresses.count)
        for address in addresses
        {
            XCTAssertEqual(XiguaAnisetteServers.normalize(address), address)
            XCTAssertFalse(XiguaAnisetteServers.isRetired(address), address)
        }
        XCTAssertEqual(XiguaAnisetteServers.defaultServer, addresses[0])
        XCTAssertEqual(URL(string: XiguaAnisetteServers.listURL)?.host, "loveipa.com")
    }

    /// 老用户的本地列表:SideStore 公共列表那一套,加上从电脑导入时钉上去的 StikStore。
    /// 迁移后只剩我们的服务器、按我们的顺序,用户隐藏过的仍然隐藏。
    func testReseedKeepsOnlyOurServersInOurOrder()
    {
        let existing: [(address: String, isHidden: Bool)] = [
            ("https://ani.stikstore.app", false),
            ("https://ani.sidestore.io", false),
            ("https://ani.sidestore.zip", false),
            ("https://mac-ani.jkcoxson.com/", true),
            ("https://ani.npeg.us", false),
        ]

        let reseeded = XiguaAnisetteServers.reseed(existing: existing)
        XCTAssertEqual(reseeded.map(\.address), XiguaAnisetteServers.builtIn.map(\.address))
        XCTAssertEqual(reseeded.filter(\.isHidden).map(\.address), ["https://mac-ani.jkcoxson.com"])
    }

    func testReseedNeverHidesEverything()
    {
        let allHidden = XiguaAnisetteServers.builtIn.map { (address: $0.address, isHidden: true) }
        XCTAssertTrue(XiguaAnisetteServers.reseed(existing: allHidden).allSatisfy { !$0.isHidden })
    }
}
