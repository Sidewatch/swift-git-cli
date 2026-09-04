//
//  NestedRepoTests.swift
//  Tests for Git.nestedRepoRoots (discovery below a folder that is not itself a
//  repo — skip list, depth cap, the root's own .git excluded, worktree `.git`
//  files) and GitStatusMap.merge (later wins, dots propagate to the top).
//  Discovery only looks for `.git` entries, so no real repositories are needed.
//

import XCTest
@testable import GitKit

final class NestedRepoTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nested-repo-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func mkdir(_ rel: String) throws {
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent(rel), withIntermediateDirectories: true)
    }

    private func found(skipping: Set<String> = ["node_modules", "vendor"], maxDepth: Int = 6) -> Set<String> {
        Set(Git.nestedRepoRoots(under: tmp, skipping: skipping, maxDepth: maxDepth)
            .map { $0.standardizedFileURL.path.replacingOccurrences(of: tmp.standardizedFileURL.path + "/", with: "") })
    }

    /// The WordPress shape: plugins and libraries are checkouts inside a folder that is
    /// not one. A worktree's `.git` is a FILE and counts; a checkout under a skipped
    /// directory does not; the root's own `.git` is not "nested".
    func testFindsCheckoutsBelowTheRoot() throws {
        try mkdir("wp-content/plugins/edd/.git")
        try mkdir("libraries/field-kit")
        try "gitdir: /elsewhere/.git/worktrees/fk\n".write(to: tmp.appendingPathComponent("libraries/field-kit/.git"),
                                                        atomically: true, encoding: .utf8)
        try mkdir("node_modules/dep/.git")
        try mkdir("wp-content/plugins/edd/vendor/lib/.git")
        try mkdir(".git")
        XCTAssertEqual(found(), ["wp-content/plugins/edd", "libraries/field-kit"])
    }

    /// A checkout inside a checkout is still returned: git treats it as an opaque
    /// untracked directory, and its own status is the truth for its files.
    func testRepoInsideRepoIsReturned() throws {
        try mkdir("app/.git")
        try mkdir("app/libs/shared/.git")
        XCTAssertEqual(found(), ["app", "app/libs/shared"])
    }

    /// The depth cap bounds the walk of a big tree; a checkout past it is not found.
    func testDepthCapIsEnforced() throws {
        try mkdir("a/b/c/.git")                 // level 3
        try mkdir("d/e/f/g/h/i/j/.git")         // level 7
        XCTAssertEqual(found(maxDepth: 6), ["a/b/c"])
        XCTAssertEqual(found(maxDepth: 8), ["a/b/c", "d/e/f/g/h/i/j"])
    }

    /// Merge: the nested repo's kinds win over the outer repo's view of the same
    /// path, dots union, and — with a top folder — dots climb to it.
    func testMergeLaysNestedOverOuterAndPropagatesDots() {
        let site = URL(fileURLWithPath: "/site")
        // The outer repo sees the whole plugin as untracked — every file in it "??" —
        // while the plugin's own repo knows edd.php is a tracked, MODIFIED file.
        let outer = GitStatusMap.build(status: [("wp-content/plugins/edd/", .untracked),
                                                ("wp-content/plugins/edd/edd.php", .untracked),
                                                ("index.php", .modified)],
                                       repoRoot: site)
        let plugin = URL(fileURLWithPath: "/site/wp-content/plugins/edd")
        let inner = GitStatusMap.build(status: [("edd.php", .modified), ("new.php", .untracked)], repoRoot: plugin)
        let merged = GitStatusMap.merge([outer, inner], propagatingTo: site)

        XCTAssertEqual(merged.kind(for: URL(fileURLWithPath: "/site/index.php")), .modified)
        XCTAssertEqual(merged.kind(for: URL(fileURLWithPath: "/site/wp-content/plugins/edd/edd.php")), .modified,
                       "the nested repo's own kind wins over the outer repo's blanket untracked")
        XCTAssertEqual(merged.kind(for: URL(fileURLWithPath: "/site/wp-content/plugins/edd/new.php")), .untracked)
        XCTAssertTrue(merged.directoryContainsChanges(URL(fileURLWithPath: "/site/wp-content/plugins/edd")))
        XCTAssertTrue(merged.directoryContainsChanges(URL(fileURLWithPath: "/site/wp-content/plugins")), "dots climb to the top")
        XCTAssertTrue(merged.directoryContainsChanges(URL(fileURLWithPath: "/site/wp-content")))
        XCTAssertTrue(merged.directoryContainsChanges(site))
        XCTAssertEqual(merged.changedFilePaths,
                       ["/site/index.php", "/site/wp-content/plugins/edd/edd.php", "/site/wp-content/plugins/edd/new.php"])
    }

    /// A nested repo alone (the opened folder is no repo) still dots its ancestors up
    /// to the opened folder, and without a top nothing climbs past its own root.
    func testMergePropagationStopsAtTheTop() {
        let plugin = URL(fileURLWithPath: "/site/wp-content/plugins/edd")
        let inner = GitStatusMap.build(status: [("edd.php", .modified)], repoRoot: plugin)
        let alone = GitStatusMap.merge([inner])
        XCTAssertFalse(alone.directoryContainsChanges(URL(fileURLWithPath: "/site/wp-content")), "no top, no climb")
        let topped = GitStatusMap.merge([inner], propagatingTo: URL(fileURLWithPath: "/site"))
        XCTAssertTrue(topped.directoryContainsChanges(URL(fileURLWithPath: "/site/wp-content")))
        XCTAssertFalse(topped.directoryContainsChanges(URL(fileURLWithPath: "/")), "never past the top")
    }
}
