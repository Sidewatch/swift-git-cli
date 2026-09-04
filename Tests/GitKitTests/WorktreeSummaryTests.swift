//
//  WorktreeSummaryTests.swift
//  Tests for WorktreeSummary.make (pure per-kind tally) and the
//  Git.worktreeSummaries integration convenience against a throwaway repo.
//

import XCTest
@testable import GitKit

final class WorktreeSummaryTests: XCTestCase {

    private var scratchDirs: [URL] = []

    override func tearDownWithError() throws {
        for dir in scratchDirs { try? FileManager.default.removeItem(at: dir) }
        scratchDirs.removeAll()
    }

    private func fixtureWorktree(_ name: String = "feature", isMain: Bool = false) -> GitWorktree {
        GitWorktree(path: URL(fileURLWithPath: "/wt/\(name)"), branch: name, isMain: isMain)
    }

    // MARK: - make (pure)

    func testMakeTalliesEachKind() {
        let summary = WorktreeSummary.make(worktree: fixtureWorktree(), status: [
            ("a.swift", .added), ("b.swift", .added),
            ("c.swift", .modified),
            ("d.swift", .deleted),
            ("e.swift", .untracked),
            ("f.swift", .renamed),
        ])
        XCTAssertEqual(summary.added, 2)
        XCTAssertEqual(summary.modified, 1)
        XCTAssertEqual(summary.deleted, 1)
        XCTAssertEqual(summary.untracked, 1)
        XCTAssertEqual(summary.renamed, 1)
        XCTAssertEqual(summary.changeCount, 6)
        XCTAssertTrue(summary.isDirty)
    }

    func testMakeCleanWorktree() {
        let summary = WorktreeSummary.make(worktree: fixtureWorktree(), status: [])
        XCTAssertEqual(summary.changeCount, 0)
        XCTAssertFalse(summary.isDirty)
    }

    func testMakePreservesWorktreeIdentity() {
        let wt = fixtureWorktree("main-tree", isMain: true)
        let summary = WorktreeSummary.make(worktree: wt, status: [("x", .modified)])
        XCTAssertEqual(summary.worktree, wt)
        XCTAssertTrue(summary.worktree.isMain)
    }

    func testMakeCarriesLineStats() {
        let summary = WorktreeSummary.make(worktree: fixtureWorktree(),
                                           status: [("x", .modified)], insertions: 12, deletions: 5)
        XCTAssertEqual(summary.insertions, 12)
        XCTAssertEqual(summary.deletions, 5)
    }

    // MARK: - parseNumstat (pure)

    func testParseNumstatSumsColumns() {
        let out = "3\t1\tsrc/a.swift\n10\t4\tsrc/b.swift\n0\t7\tsrc/c.swift\n"
        let (ins, del) = Git.parseNumstat(out)
        XCTAssertEqual(ins, 13)
        XCTAssertEqual(del, 12)
    }

    func testParseNumstatSkipsBinaryDashRows() {
        // Binary files report "-\t-\t<path>".
        let out = "5\t2\tsrc/a.swift\n-\t-\tassets/logo.png\n"
        let (ins, del) = Git.parseNumstat(out)
        XCTAssertEqual(ins, 5)
        XCTAssertEqual(del, 2)
    }

    func testParseNumstatEmpty() {
        let (ins, del) = Git.parseNumstat("")
        XCTAssertEqual(ins, 0)
        XCTAssertEqual(del, 0)
    }

    // MARK: - Git.worktreeSummaries (integration)

    func testWorktreeSummariesReflectsEachTreesChanges() throws {
        // Main repo with one commit.
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wtsum-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        scratchDirs.append(root)
        XCTAssertNotNil(Git.run(["init", "-q"], in: root))
        _ = Git.run(["config", "user.email", "t@e.com"], in: root)
        _ = Git.run(["config", "user.name", "T"], in: root)
        _ = Git.run(["config", "commit.gpgsign", "false"], in: root)
        try "seed".write(to: root.appendingPathComponent("seed.txt"), atomically: true, encoding: .utf8)
        _ = Git.run(["add", "-A"], in: root)
        _ = Git.run(["commit", "-q", "-m", "seed"], in: root)

        // A linked worktree on a new branch.
        let linked = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wtsum-linked-\(UUID().uuidString)", isDirectory: true)
        scratchDirs.append(linked)
        XCTAssertNotNil(Git.run(["worktree", "add", "-q", "-b", "feature", linked.path], in: root),
                        "worktree add failed")

        // Dirty each tree differently: main gets an untracked file; the linked
        // tree modifies the tracked seed file.
        try "new".write(to: root.appendingPathComponent("untracked.txt"), atomically: true, encoding: .utf8)
        try "changed".write(to: linked.appendingPathComponent("seed.txt"), atomically: true, encoding: .utf8)

        let summaries = Git.worktreeSummaries(repoRoot: root)
        XCTAssertEqual(summaries.count, 2)

        let main = try XCTUnwrap(summaries.first { $0.worktree.isMain })
        let feature = try XCTUnwrap(summaries.first { $0.worktree.branch == "feature" })
        XCTAssertEqual(main.untracked, 1)
        XCTAssertEqual(feature.modified, 1)
        XCTAssertTrue(main.isDirty)
        XCTAssertTrue(feature.isDirty)
    }

    func testRemoveWorktreeDropsALinkedTree() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wtrm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        scratchDirs.append(root)
        XCTAssertNotNil(Git.run(["init", "-q"], in: root))
        _ = Git.run(["config", "user.email", "t@e.com"], in: root)
        _ = Git.run(["config", "user.name", "T"], in: root)
        _ = Git.run(["config", "commit.gpgsign", "false"], in: root)
        try "seed".write(to: root.appendingPathComponent("seed.txt"), atomically: true, encoding: .utf8)
        _ = Git.run(["add", "-A"], in: root)
        _ = Git.run(["commit", "-q", "-m", "seed"], in: root)

        let linked = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wtrm-linked-\(UUID().uuidString)", isDirectory: true)
        scratchDirs.append(linked)
        XCTAssertNotNil(Git.run(["worktree", "add", "-q", "-b", "feature", linked.path], in: root))
        XCTAssertEqual(Git.worktrees(repoRoot: root).count, 2)

        // Clean linked tree removes without force.
        XCTAssertTrue(Git.removeWorktree(linked, repoRoot: root))
        XCTAssertEqual(Git.worktrees(repoRoot: root).count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: linked.path))
    }

    func testForceRemoveOverridesALock() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wtlock-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        scratchDirs.append(root)
        XCTAssertNotNil(Git.run(["init", "-q"], in: root))
        _ = Git.run(["config", "user.email", "t@e.com"], in: root)
        _ = Git.run(["config", "user.name", "T"], in: root)
        _ = Git.run(["config", "commit.gpgsign", "false"], in: root)
        try "seed".write(to: root.appendingPathComponent("seed.txt"), atomically: true, encoding: .utf8)
        _ = Git.run(["add", "-A"], in: root)
        _ = Git.run(["commit", "-q", "-m", "seed"], in: root)

        let linked = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wtlock-linked-\(UUID().uuidString)", isDirectory: true)
        scratchDirs.append(linked)
        XCTAssertNotNil(Git.run(["worktree", "add", "-q", "-b", "feature", linked.path], in: root))
        // Lock the (clean) worktree: a plain remove and a single --force both refuse;
        // only --force --force (what force: true now passes) can override a lock.
        XCTAssertNotNil(Git.run(["worktree", "lock", linked.path], in: root))

        XCTAssertFalse(Git.removeWorktree(linked, repoRoot: root))              // locked → refused
        XCTAssertTrue(Git.removeWorktree(linked, repoRoot: root, force: true))  // -f -f overrides
        XCTAssertEqual(Git.worktrees(repoRoot: root).count, 1)
    }
}
