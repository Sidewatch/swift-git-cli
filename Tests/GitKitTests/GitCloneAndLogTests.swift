//
//  GitCloneAndLogTests.swift
//  GitKitTests
//
//  GitCloneAndLogTests.
//
//  Created by David Sherlock on 7/21/26.
//

import XCTest
@testable import GitKit

final class GitCloneAndLogTests: XCTestCase {
    private var scratch: [URL] = []

    override func tearDownWithError() throws {
        for u in scratch { try? FileManager.default.removeItem(at: u) }
        scratch = []
    }

    private func tempDir(_ prefix: String) throws -> URL {
        let u = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        scratch.append(u)
        return u
    }

    private func seedRepo(_ root: URL, commits: [String]) {
        _ = Git.run(["init", "-q"], in: root)
        _ = Git.run(["config", "user.email", "t@e.com"], in: root)
        _ = Git.run(["config", "user.name", "T"], in: root)
        _ = Git.run(["config", "commit.gpgsign", "false"], in: root)
        for (i, msg) in commits.enumerated() {
            try? "\(i)".write(to: root.appendingPathComponent("f\(i).txt"), atomically: true, encoding: .utf8)
            _ = Git.run(["add", "-A"], in: root)
            _ = Git.run(["commit", "-q", "-m", msg], in: root)
        }
    }

    // MARK: - defaultCloneDirectoryName (pure)

    func testDefaultCloneDirectoryName() {
        XCTAssertEqual(Git.defaultCloneDirectoryName(for: "https://github.com/arraypress/sidewatch.git"), "sidewatch")
        XCTAssertEqual(Git.defaultCloneDirectoryName(for: "https://github.com/owner/Repo"), "Repo")
        XCTAssertEqual(Git.defaultCloneDirectoryName(for: "git@github.com:owner/my-repo.git"), "my-repo")
        XCTAssertEqual(Git.defaultCloneDirectoryName(for: "git@host:repo.git"), "repo")
        XCTAssertEqual(Git.defaultCloneDirectoryName(for: "https://example.com/a/b/c.git/"), "c")
        XCTAssertEqual(Git.defaultCloneDirectoryName(for: ""), "repository")
    }

    // MARK: - log (integration)

    func testLogReturnsCommitsNewestFirst() throws {
        let root = try tempDir("gitlog")
        seedRepo(root, commits: ["first", "second", "third"])
        let commits = Git.log(repoRoot: root, limit: 10)
        XCTAssertEqual(commits.count, 3)
        XCTAssertEqual(commits.map(\.subject), ["third", "second", "first"])   // newest first
        XCTAssertEqual(commits.first?.author, "T")
        XCTAssertEqual(commits.first?.shortHash.count ?? 0 >= 7, true)
        XCTAssertFalse(commits.first?.hash.isEmpty ?? true)
    }

    func testLogRespectsLimit() throws {
        let root = try tempDir("gitloglimit")
        seedRepo(root, commits: ["a", "b", "c", "d"])
        XCTAssertEqual(Git.log(repoRoot: root, limit: 2).count, 2)
    }

    func testShowCommitContainsThePatch() throws {
        let root = try tempDir("gitshow")
        seedRepo(root, commits: ["only"])
        let hash = Git.log(repoRoot: root, limit: 1).first!.hash
        let patch = Git.showCommit(hash, repoRoot: root)
        XCTAssertNotNil(patch)
        XCTAssertTrue(patch!.contains("only"))       // the commit subject
        XCTAssertTrue(patch!.contains("f0.txt"))     // the changed file
    }

    // MARK: - clone (integration, local — no network)

    func testCloneLocalRepoSucceeds() throws {
        let src = try tempDir("clone-src")
        seedRepo(src, commits: ["seed"])
        let parent = try tempDir("clone-dest")

        let result = Git.clone(from: src.path, into: parent, name: "checkout")
        XCTAssertTrue(result.succeeded, "clone error: \(result.error ?? "nil")")
        XCTAssertEqual(result.path?.lastPathComponent, "checkout")
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path!.appendingPathComponent("f0.txt").path,
                                                     isDirectory: &isDir))
        // The clone has the source's history.
        XCTAssertEqual(Git.log(repoRoot: result.path!, limit: 5).map(\.subject), ["seed"])
    }

    func testCloneBadPathReturnsError() throws {
        let parent = try tempDir("clone-bad")
        let result = Git.clone(from: "/nonexistent/does-not-exist.git", into: parent)
        XCTAssertFalse(result.succeeded)
        XCTAssertNotNil(result.error)
    }

    // MARK: - Info (integration)

    func testBranchAndCleanInfo() throws {
        let root = try tempDir("gitinfo")
        seedRepo(root, commits: ["seed"])
        let branch = Git.currentBranch(repoRoot: root)
        XCTAssertTrue(branch == "main" || branch == "master", "got \(branch ?? "nil")")
        XCTAssertTrue(Git.isClean(repoRoot: root))
        // Dirty it.
        try "x".write(to: root.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        XCTAssertFalse(Git.isClean(repoRoot: root))
    }

    func testLocalBranchesFlagsCurrent() throws {
        let root = try tempDir("gitbranches")
        seedRepo(root, commits: ["seed"])
        _ = Git.run(["branch", "feature"], in: root)
        let branches = Git.localBranches(repoRoot: root)
        XCTAssertEqual(Set(branches.map(\.name)).isSuperset(of: ["feature"]), true)
        XCTAssertEqual(branches.filter(\.isCurrent).count, 1)          // exactly one current
        XCTAssertFalse(branches.first(where: { $0.name == "feature" })?.isCurrent ?? true)
    }

    func testAheadBehindWithNoUpstreamIsZero() throws {
        let root = try tempDir("gitab")
        seedRepo(root, commits: ["seed"])
        XCTAssertEqual(Git.aheadBehind(repoRoot: root).ahead, 0)
        XCTAssertEqual(Git.aheadBehind(repoRoot: root).behind, 0)
    }

    func testFileLogFollowsOneFile() throws {
        let root = try tempDir("gitfilelog")
        seedRepo(root, commits: ["c0"])   // creates f0.txt
        // Touch f0.txt again in a new commit.
        try "changed".write(to: root.appendingPathComponent("f0.txt"), atomically: true, encoding: .utf8)
        _ = Git.run(["add", "-A"], in: root)
        _ = Git.run(["commit", "-q", "-m", "touch f0"], in: root)
        let hist = Git.fileLog(path: "f0.txt", repoRoot: root, limit: 10)
        XCTAssertEqual(hist.map(\.subject), ["touch f0", "c0"])       // both commits touched f0.txt
    }

    func testShowFileAtRevision() throws {
        let root = try tempDir("gitshowfile")
        seedRepo(root, commits: ["seed"])   // f0.txt content "0"
        let content = Git.showFile(revision: "HEAD", path: "f0.txt", repoRoot: root)
        XCTAssertEqual(content?.trimmingCharacters(in: .whitespacesAndNewlines), "0")
    }
}
