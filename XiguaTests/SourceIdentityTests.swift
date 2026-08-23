//
//  SourceIdentityTests.swift
//  XiguaTests
//

import XCTest
import AltStoreCore

/// 内置源的身份是由 URL 推出来的(Source.sourceID(from:))。换域名等于换身份 ——
/// 2026 年把源从 sideloadstore.pages.dev 换到 loveipa.com 时就是这样,已装用户
/// 会多出一条重复的源,得靠迁移把老那条改过去。
///
/// 这几条钉住迁移赖以成立的前提。任何一条挂了,迁移逻辑就是错的。
final class SourceIdentityTests: XCTestCase
{
    func testBuiltInSourceURLIsOurOwnDomain()
    {
        // 国内连不上 *.pages.dev,内置源必须走自己的域名。
        XCTAssertEqual(Source.altStoreSourceURL.host, "loveipa.com")
    }
    
    /// 迁移的前提:新老身份不同。要是相同,迁移代码会白跑,而且说明换域名
    /// 根本没改变身份 —— 那反过来说明 sourceID 没在用 URL。
    func testNewAndLegacyIdentifiersDiffer()
    {
        XCTAssertNotEqual(Source.altStoreIdentifier, Source.legacyAltStoreIdentifier)
    }
    
    /// 身份必须只由 URL 决定且稳定。要是每次算出来不一样,老用户永远匹配不上
    /// 那条要迁移的记录。
    func testIdentifierIsDerivedFromURLAndStable()
    {
        let again = try? Source.sourceID(from: Source.altStoreSourceURL)
        XCTAssertEqual(again, Source.altStoreIdentifier)
        
        let legacyAgain = try? Source.sourceID(from: Source.legacyAltStoreSourceURL)
        XCTAssertEqual(legacyAgain, Source.legacyAltStoreIdentifier)
    }
    
    func testLegacyURLIsTheOneWeActuallyShipped()
    {
        XCTAssertEqual(Source.legacyAltStoreSourceURL.absoluteString,
                       "https://sideloadstore.pages.dev/apps.json")
    }
}
