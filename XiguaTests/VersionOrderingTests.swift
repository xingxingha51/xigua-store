//
//  VersionOrderingTests.swift
//  XiguaTests
//

import XCTest
import SemanticVersion

/// 我们的发版号是「上游版本 + -xigua.N」。更新提示、自升级全靠 SemVer 比较,
/// 而这套比较有两条反直觉的规则,我们各踩过一次:
///
///   1. 预发布版永远小于同号的正式版 —— 3.8.3-xigua.2 < 3.8.3
///   2. 预发布标识里的数字段按数值比,不是按字典序 —— xigua.10 > xigua.9
///
/// 第 1 条导致过一次真实事故:西瓜多开基于上游 3.8.3 打包,版本写成
/// 3.8.3-xigua.2,结果在商店里"永远比上游旧",更新提示不出来。之后改成
/// 「比上游高一个 patch」:3.8.4-xigua.1。
final class VersionOrderingTests: XCTestCase
{
    private func version(_ s: String, file: StaticString = #filePath, line: UInt = #line) -> SemanticVersion
    {
        guard let v = SemanticVersion(s) else {
            XCTFail("解析不了版本号 '\(s)'", file: file, line: line)
            return SemanticVersion(0, 0, 0)
        }
        return v
    }
    
    /// 当年那个 bug 本身。留着是为了说明为什么不能直接用上游版本号。
    func testPrereleaseLosesToTheSameStableVersion()
    {
        XCTAssertLessThan(version("3.8.3-xigua.2"), version("3.8.3"),
                          "预发布版小于同号正式版 —— 这正是不能写 X.Y.Z-xigua.N 的原因")
    }
    
    /// 现在这套「比上游高一个 patch」的方案必须真的赢过上游。
    func testOnePatchAheadBeatsUpstream()
    {
        XCTAssertGreaterThan(version("3.8.4-xigua.1"), version("3.8.3"))
        XCTAssertGreaterThan(version("3.8.7-xigua.1"), version("3.8.6"))
    }
    
    /// 连续两次自己发版,新的要赢。
    func testConsecutiveForkReleasesAscend()
    {
        XCTAssertGreaterThan(version("0.6.4-xigua.26"), version("0.6.4-xigua.25"))
    }
    
    /// 数字段按数值比。按字典序的话 "10" < "9",跨过 9 的那次发版所有人都收不到
    /// 更新 —— 我们已经过了 .9,这条现在是活的。
    func testNumericIdentifiersCompareNumericallyNotLexically()
    {
        XCTAssertGreaterThan(version("0.6.4-xigua.10"), version("0.6.4-xigua.9"))
        XCTAssertGreaterThan(version("0.6.4-xigua.26"), version("0.6.4-xigua.9"))
    }
    
    /// 上游要是哪天发了正式的 3.8.4,它会赢过我们的 3.8.4-xigua.N。这是对的
    /// (该跟进上游了),但得知道会这样,别当成 bug。
    func testUpstreamStableWinsOverOurPrereleaseOfTheSameNumber()
    {
        XCTAssertGreaterThan(version("3.8.4"), version("3.8.4-xigua.9"))
    }
}
