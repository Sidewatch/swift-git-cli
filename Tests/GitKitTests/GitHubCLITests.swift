//
//  GitHubCLITests.swift
//  GitKitTests
//
//  Tests for `GitHubCLI` location: the candidate paths are probed before falling back to
//  `which`.
//
//  Created by David Sherlock on 9/5/26.
//

import XCTest
@testable import GitKit

/// Tests for `GitHubCLI` location: the candidate paths are probed before falling back to
/// `which`.
final class GitHubCLITests: XCTestCase {
    func testProbesTheCandidatePathsBeforeFallingBackToWhich() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = dir.appendingPathComponent("gh")
        try "#!/bin/sh\nexit 0\n".write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        var asked = 0
        XCTAssertEqual(GitHubCLI.executablePath(candidates: ["/nonexistent/gh", fake.path], which: { _ in asked += 1; return nil }), fake.path)
        XCTAssertEqual(asked, 0, "a candidate hit never consults which")
        XCTAssertEqual(GitHubCLI.executablePath(candidates: ["/nonexistent/gh"], which: { _ in asked += 1; return "/from/which/gh" }), "/from/which/gh")
        XCTAssertEqual(asked, 1)
        XCTAssertNil(GitHubCLI.executablePath(candidates: [], which: { _ in nil }))
    }
}
