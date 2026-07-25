//
//  GitCheckpointTests.swift
//  Tests for SwiftGitCLI
//
//  Created by David Sherlock on 7/25/26.
//

import XCTest
@testable import GitCLI

final class GitCheckpointTests: XCTestCase {

    // MARK: - Temp-repo scaffolding

    private var scratchDirs: [URL] = []

    override func tearDownWithError() throws {
        for dir in scratchDirs { try? FileManager.default.removeItem(at: dir) }
        scratchDirs.removeAll()
    }

    private func makeRepo(file: StaticString = #filePath, line: UInt = #line) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gitcli-ckpt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        scratchDirs.append(dir)
        XCTAssertNotNil(Git.run(["init", "-q"], in: dir), "git init failed", file: file, line: line)
        _ = Git.run(["config", "user.email", "test@example.com"], in: dir)
        _ = Git.run(["config", "user.name", "Test Author"], in: dir)
        _ = Git.run(["config", "commit.gpgsign", "false"], in: dir)
        return try XCTUnwrap(Git.repoRoot(for: dir), "repoRoot returned nil", file: file, line: line)
    }

    private func write(_ contents: String, to name: String, in root: URL) throws {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// A repo with one commit containing `tracked.txt`.
    private func seededRepo() throws -> URL {
        let root = try makeRepo()
        try write("orig\n", to: "tracked.txt", in: root)
        _ = Git.run(["add", "-A"], in: root)
        _ = Git.run(["commit", "-q", "-m", "base"], in: root)
        return root
    }

    // MARK: - Capture

    func testCheckpointCapturesModificationsAdditionsAndDeletions() throws {
        let root = try seededRepo()
        // Commit the file that will be deleted FIRST, so the deletion is a working-tree
        // change at snapshot time rather than something already in HEAD.
        try write("x\n", to: "gone.txt", in: root)
        _ = Git.run(["add", "-A"], in: root)
        _ = Git.run(["commit", "-q", "-m", "add gone"], in: root)

        try write("changed\n", to: "tracked.txt", in: root)
        try write("brand new\n", to: "untracked.txt", in: root)
        try FileManager.default.removeItem(at: root.appendingPathComponent("gone.txt"))

        let sha = try XCTUnwrap(Git.createCheckpoint(repoRoot: root))
        let changed = Git.checkpointChangedFiles(from: "HEAD", to: sha, repoRoot: root)
        let byPath = Dictionary(uniqueKeysWithValues: changed.map { ($0.path, $0.kind) })

        // The untracked file is the whole point: `git stash create` omits it, and an agent
        // creating new files is the common case.
        XCTAssertEqual(byPath["untracked.txt"], .added)
        XCTAssertEqual(byPath["tracked.txt"], .modified)
        XCTAssertEqual(byPath["gone.txt"], .deleted)
    }

    func testCheckpointLeavesWorkingTreeIndexAndStashUntouched() throws {
        let root = try seededRepo()
        try write("changed\n", to: "tracked.txt", in: root)
        try write("new\n", to: "untracked.txt", in: root)

        let before = Git.run(["status", "--porcelain"], in: root)
        XCTAssertNotNil(Git.createCheckpoint(repoRoot: root))

        XCTAssertEqual(Git.run(["status", "--porcelain"], in: root), before)
        XCTAssertEqual(Git.run(["stash", "list"], in: root), "")
        // The scratch index must not have been left inside the repo.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasPrefix("sidewatch-checkpoint-index") }
        XCTAssertTrue(leftovers.isEmpty, "scratch index leaked into the repo: \(leftovers)")
    }

    func testCheckpointRespectsGitignore() throws {
        let root = try seededRepo()
        try write("*.log\n", to: ".gitignore", in: root)
        _ = Git.run(["add", "-A"], in: root)
        _ = Git.run(["commit", "-q", "-m", "ignore"], in: root)
        try write("noise\n", to: "build.log", in: root)

        let sha = try XCTUnwrap(Git.createCheckpoint(repoRoot: root))
        let paths = Git.checkpointChangedFiles(from: "HEAD", to: sha, repoRoot: root).map(\.path)
        XCTAssertFalse(paths.contains("build.log"))
    }

    func testCheckpointInRepoWithNoCommitsYet() throws {
        // A fresh repo has no HEAD, so commit-tree must be called without a parent.
        let root = try makeRepo()
        try write("first\n", to: "a.txt", in: root)
        XCTAssertNotNil(Git.createCheckpoint(repoRoot: root))
    }

    func testTwoCheckpointsDiffToExactlyWhatChangedBetween() throws {
        let root = try seededRepo()
        try write("one\n", to: "a.txt", in: root)
        let first = try XCTUnwrap(Git.createCheckpoint(repoRoot: root))

        try write("two\n", to: "b.txt", in: root)
        let second = try XCTUnwrap(Git.createCheckpoint(repoRoot: root))

        // a.txt existed at `first`, so only b.txt is new in the span — this is the property
        // that makes a turn diff exact instead of inferred.
        let changed = Git.checkpointChangedFiles(from: first, to: second, repoRoot: root)
        XCTAssertEqual(changed.map(\.path), ["b.txt"])
        XCTAssertEqual(changed.first?.kind, .added)

        let diff = try XCTUnwrap(Git.checkpointDiff(from: first, to: second, repoRoot: root))
        XCTAssertTrue(diff.contains("+two"))
        XCTAssertFalse(diff.contains("+one"))
    }

    func testCheckpointDiffCanNarrowToOnePath() throws {
        let root = try seededRepo()
        let first = try XCTUnwrap(Git.createCheckpoint(repoRoot: root))
        try write("a\n", to: "a.txt", in: root)
        try write("b\n", to: "b.txt", in: root)
        let second = try XCTUnwrap(Git.createCheckpoint(repoRoot: root))

        let diff = try XCTUnwrap(Git.checkpointDiff(from: first, to: second, path: "a.txt", repoRoot: root))
        XCTAssertTrue(diff.contains("a.txt"))
        XCTAssertFalse(diff.contains("b.txt"))
    }

    func testCheckpointDiffAgainstLiveWorkingTree() throws {
        // The turn in progress has an opening snapshot but no closing one, so its diff runs
        // against the working tree as it stands right now.
        let root = try seededRepo()
        let start = try XCTUnwrap(Git.createCheckpoint(repoRoot: root))
        try write("edited by the agent\n", to: "tracked.txt", in: root)
        try write("created by the agent\n", to: "fresh.txt", in: root)

        let changed = Git.checkpointChangedFiles(from: start, to: nil, repoRoot: root)
        let byPath = Dictionary(uniqueKeysWithValues: changed.map { ($0.path, $0.kind) })
        XCTAssertEqual(byPath["tracked.txt"], .modified)
        // An untracked file is invisible to a bare `git diff <commit>`, so this is the case
        // that would silently under-report a turn's work if it regressed.
        XCTAssertEqual(byPath["fresh.txt"], .added)

        let diff = try XCTUnwrap(Git.checkpointDiff(from: start, to: nil, repoRoot: root))
        XCTAssertTrue(diff.contains("edited by the agent"))
    }

    // MARK: - Anchoring

    func testAnchoredCheckpointSurvivesAggressiveGC() throws {
        let root = try seededRepo()
        try write("changed\n", to: "tracked.txt", in: root)
        let sha = try XCTUnwrap(Git.createCheckpoint(repoRoot: root))
        XCTAssertTrue(Git.anchorCheckpoint(sha, id: "turn-1", repoRoot: root))

        _ = Git.run(["reflog", "expire", "--expire=now", "--all"], in: root)
        _ = Git.run(["gc", "--prune=now", "-q"], in: root)

        // Unanchored, this commit would be unreachable and collected — losing the turn.
        XCTAssertEqual(Git.run(["cat-file", "-t", sha], in: root)?
            .trimmingCharacters(in: .whitespacesAndNewlines), "commit")
        XCTAssertEqual(Git.checkpoints(repoRoot: root).map(\.id), ["turn-1"])
    }

    func testCheckpointsAreInvisibleToBranchesAndTags() throws {
        let root = try seededRepo()
        let sha = try XCTUnwrap(Git.createCheckpoint(repoRoot: root))
        Git.anchorCheckpoint(sha, id: "turn-1", repoRoot: root)
        XCTAssertEqual(Git.run(["tag"], in: root), "")
        XCTAssertFalse(Git.run(["branch", "--list"], in: root)?.contains("turn-1") ?? false)
    }

    func testRemoveCheckpointDropsTheAnchor() throws {
        let root = try seededRepo()
        let sha = try XCTUnwrap(Git.createCheckpoint(repoRoot: root))
        Git.anchorCheckpoint(sha, id: "turn-1", repoRoot: root)
        XCTAssertTrue(Git.removeCheckpoint(id: "turn-1", repoRoot: root))
        XCTAssertTrue(Git.checkpoints(repoRoot: root).isEmpty)
    }

    func testUnsafeCheckpointIDIsSanitizedAndCannotEscapeTheNamespace() throws {
        let root = try seededRepo()
        let sha = try XCTUnwrap(Git.createCheckpoint(repoRoot: root))
        // Spaces and `..` are outright illegal in a ref; `../../heads/main` would otherwise
        // aim an update-ref at a real branch.
        XCTAssertTrue(Git.anchorCheckpoint(sha, id: "../../heads/main", repoRoot: root))

        let ids = Git.checkpoints(repoRoot: root).map(\.id)
        XCTAssertEqual(ids.count, 1)
        XCTAssertFalse(ids[0].contains(".."))
        // The real branch must be untouched.
        XCTAssertNotEqual(Git.run(["rev-parse", "HEAD"], in: root)?
            .trimmingCharacters(in: .whitespacesAndNewlines), sha)
    }

    func testAnchorRejectsAnIDWithNothingSafeInIt() throws {
        let root = try seededRepo()
        let sha = try XCTUnwrap(Git.createCheckpoint(repoRoot: root))
        XCTAssertFalse(Git.anchorCheckpoint(sha, id: "///", repoRoot: root))
    }

    // MARK: - Pruning

    func testPruneKeepsTheNewestAndDropsTheRest() throws {
        let root = try seededRepo()
        for i in 1...4 {
            try write("v\(i)\n", to: "tracked.txt", in: root)
            let sha = try XCTUnwrap(Git.createCheckpoint(repoRoot: root))
            Git.anchorCheckpoint(sha, id: "turn-\(i)", repoRoot: root)
            // Commit timestamps have 1s resolution, so nudge the clock to keep the sort stable.
            _ = Git.run(["update-ref", Git.checkpointRefPrefix + "turn-\(i)", sha], in: root)
        }
        XCTAssertEqual(Git.checkpoints(repoRoot: root).count, 4)

        let dropped = Git.pruneCheckpoints(keeping: 2, repoRoot: root)
        XCTAssertEqual(dropped.count, 2)
        XCTAssertEqual(Git.checkpoints(repoRoot: root).count, 2)
    }

    func testPruneKeepingZeroDropsEverythingAndIsIdempotent() throws {
        let root = try seededRepo()
        let sha = try XCTUnwrap(Git.createCheckpoint(repoRoot: root))
        Git.anchorCheckpoint(sha, id: "turn-1", repoRoot: root)
        XCTAssertEqual(Git.pruneCheckpoints(keeping: 0, repoRoot: root).count, 1)
        XCTAssertTrue(Git.checkpoints(repoRoot: root).isEmpty)
        XCTAssertTrue(Git.pruneCheckpoints(keeping: 0, repoRoot: root).isEmpty)
    }

    func testPruneOnRepoWithNoCheckpointsIsANoOp() throws {
        let root = try seededRepo()
        XCTAssertTrue(Git.pruneCheckpoints(keeping: 5, repoRoot: root).isEmpty)
    }
}
