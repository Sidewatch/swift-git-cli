//
//  GitKitTests.swift
//  Tests for SwiftGitCLI
//
//  Created by David Sherlock on 7/9/26.
//

import XCTest
@testable import GitKit

final class GitKitTests: XCTestCase {

    // MARK: - Temp-repo scaffolding

    /// Temp directories created during a test, removed in `tearDown`.
    private var scratchDirs: [URL] = []

    override func tearDownWithError() throws {
        for dir in scratchDirs { try? FileManager.default.removeItem(at: dir) }
        scratchDirs.removeAll()
    }

    /// Creates a fresh git repo in a throwaway temp dir and returns its canonical
    /// root (git-reported, so it survives the `/var` → `/private/var` symlink on macOS).
    private func makeRepo(file: StaticString = #filePath, line: UInt = #line) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gitcli-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        scratchDirs.append(dir)
        XCTAssertNotNil(Git.run(["init", "-q"], in: dir), "git init failed", file: file, line: line)
        _ = Git.run(["config", "user.email", "test@example.com"], in: dir)
        _ = Git.run(["config", "user.name", "Test Author"], in: dir)
        _ = Git.run(["config", "commit.gpgsign", "false"], in: dir)
        let root = try XCTUnwrap(Git.repoRoot(for: dir), "repoRoot returned nil", file: file, line: line)
        return root
    }

    private func write(_ contents: String, to name: String, in root: URL) throws {
        try contents.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    @discardableResult
    private func commit(_ message: String, in root: URL) -> Bool {
        Git.run(["commit", "-q", "-m", message], in: root) != nil
    }

    // MARK: - repoRoot / relativePath

    func testRepoRootFromNestedDirectory() throws {
        let root = try makeRepo()
        let nested = root.appendingPathComponent("a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        XCTAssertEqual(Git.repoRoot(for: nested)?.standardizedFileURL, root.standardizedFileURL)
    }

    func testRepoRootNilOutsideRepo() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gitcli-norepo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        scratchDirs.append(dir)
        XCTAssertNil(Git.repoRoot(for: dir))
    }

    func testRelativePath() throws {
        let root = try makeRepo()
        // Create the file for real: `relativePath` standardizes paths, and on macOS
        // the `/private/var`↔`/var` temp-dir symlink only reconciles for paths that
        // exist on disk — which mirrors real callers (open files, `git status` entries).
        let dir = root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("main.swift")
        try write("x", to: "src/main.swift", in: root)
        XCTAssertEqual(Git.relativePath(file, root: root), "src/main.swift")
    }

    func testRelativePathFallsBackForUnrelatedFile() throws {
        let root = try makeRepo()
        let outside = URL(fileURLWithPath: "/elsewhere/thing.txt")
        XCTAssertEqual(Git.relativePath(outside, root: root), "thing.txt")
    }

    func testRelativePathIfUnderRootNilForUnrelatedFile() throws {
        let root = try makeRepo()
        let outside = URL(fileURLWithPath: "/elsewhere/thing.txt")
        XCTAssertNil(Git.relativePathIfUnderRoot(outside, root: root))
    }

    /// THE SIBLING-PREFIX TRAP. A `hasPrefix(root)` test with no trailing separator accepts
    /// any sibling whose name merely STARTS with the root's name — and this app creates
    /// exactly those: linked worktrees live at `<root>-<branch>`. Two hand-rolled copies in
    /// the app had this bug, one of them keying review notes, so `/proj-feature/src/a.swift`
    /// against `/proj` produced `-feature/src/a.swift` instead of refusing the path.
    func testSiblingDirectorySharingTheRootsNamePrefixIsNotUnderRoot() {
        let root = URL(fileURLWithPath: "/tmp/sw-proj")
        let sibling = URL(fileURLWithPath: "/tmp/sw-proj-feature/src/a.swift")
        XCTAssertNil(Git.relativePathIfUnderRoot(sibling, root: root),
                     "a sibling worktree must not be treated as inside the root")
        XCTAssertEqual(Git.relativePath(sibling, root: root), "a.swift",
                       "and it must fall back to the basename, not a garbled relative path")
    }

    /// The root itself is not "a path under the root" — there is no relative path to give,
    /// and returning "" would read as a valid empty filename downstream.
    func testRootItselfIsNotUnderRoot() {
        let root = URL(fileURLWithPath: "/tmp/sw-proj")
        XCTAssertNil(Git.relativePathIfUnderRoot(root, root: root))
    }

    /// A trailing slash on either side is cosmetic and must not change the answer.
    func testTrailingSlashesAreIrrelevant() {
        let root = URL(fileURLWithPath: "/tmp/sw-proj/")
        let file = URL(fileURLWithPath: "/tmp/sw-proj/src/a.swift")
        XCTAssertEqual(Git.relativePathIfUnderRoot(file, root: root), "src/a.swift")
    }

    func testRelativePathReconcilesPrivateVarSymlinkForDeletedFile() throws {
        // Regression: git reports roots in the resolved `/private/var/...` form,
        // but `standardizedFileURL` only strips `/private` for paths that EXIST —
        // so a deleted file expressed via the `/private` form used to fail the
        // prefix check and fall back to a bare (wrong) filename.
        let root = try makeRepo()   // git-reported, i.e. `/private/var/...` on macOS
        try XCTSkipUnless(root.path.hasPrefix("/private/var/"),
                          "requires the macOS /private/var temp symlink")
        let sub = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try write("x", to: "sub/config.json", in: root)
        _ = Git.stage(root.appendingPathComponent("sub/config.json"), repoRoot: root)
        commit("add sub/config", in: root)
        try FileManager.default.removeItem(at: sub.appendingPathComponent("config.json"))
        // Deleted file in /private form vs the same root — must still resolve fully.
        let deleted = URL(fileURLWithPath: root.path + "/sub/config.json")
        XCTAssertEqual(Git.relativePathIfUnderRoot(deleted, root: root), "sub/config.json")
        XCTAssertEqual(Git.relativePath(deleted, root: root), "sub/config.json")
    }

    // MARK: - status

    func testStatusUntracked() throws {
        let root = try makeRepo()
        try write("hello", to: "new.txt", in: root)
        let status = Git.status(repoRoot: root)
        XCTAssertEqual(status.count, 1)
        XCTAssertEqual(status.first?.path, "new.txt")
        XCTAssertEqual(status.first?.kind, .untracked)
    }

    func testStatusUntrackedDirectoryListsFilesIndividually() throws {
        // Regression: without `-uall`, porcelain v1 collapses a brand-new
        // untracked directory to a single trailing-slash entry
        // (`?? NewFeature/`), so the files inside never reached callers that
        // decorate per file (sidebar badges, tab tints).
        let root = try makeRepo()
        let dir = root.appendingPathComponent("NewFeature", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try write("a", to: "NewFeature/a.swift", in: root)
        try write("b", to: "NewFeature/b.swift", in: root)
        let status = Git.status(repoRoot: root)
        XCTAssertEqual(Set(status.map(\.path)), ["NewFeature/a.swift", "NewFeature/b.swift"])
        XCTAssertTrue(status.allSatisfy { $0.kind == .untracked })
        XCTAssertFalse(status.contains { $0.path.hasSuffix("/") })   // no directory entries
    }

    func testStatusModified() throws {
        let root = try makeRepo()
        try write("one\n", to: "f.txt", in: root)
        _ = Git.stage(root.appendingPathComponent("f.txt"), repoRoot: root)
        commit("add f", in: root)
        try write("one\ntwo\n", to: "f.txt", in: root)
        XCTAssertEqual(Git.status(repoRoot: root).first?.kind, .modified)
    }

    func testStatusStagedAddition() throws {
        let root = try makeRepo()
        try write("x", to: "seed.txt", in: root)
        _ = Git.stage(root.appendingPathComponent("seed.txt"), repoRoot: root)
        commit("seed", in: root)
        try write("brand new", to: "added.txt", in: root)
        _ = Git.stage(root.appendingPathComponent("added.txt"), repoRoot: root)
        let added = Git.status(repoRoot: root).first { $0.path == "added.txt" }
        XCTAssertEqual(added?.kind, .added)
    }

    func testStatusDeleted() throws {
        let root = try makeRepo()
        try write("gone soon", to: "d.txt", in: root)
        _ = Git.stage(root.appendingPathComponent("d.txt"), repoRoot: root)
        commit("add d", in: root)
        try FileManager.default.removeItem(at: root.appendingPathComponent("d.txt"))
        XCTAssertEqual(Git.status(repoRoot: root).first?.kind, .deleted)
    }

    func testStatusRenamed() throws {
        let root = try makeRepo()
        try write("stable contents that git can match on rename\n", to: "old.txt", in: root)
        _ = Git.stage(root.appendingPathComponent("old.txt"), repoRoot: root)
        commit("add old", in: root)
        _ = Git.run(["mv", "old.txt", "new.txt"], in: root)   // git mv stages the rename
        let renamed = Git.status(repoRoot: root).first
        XCTAssertEqual(renamed?.kind, .renamed)
        XCTAssertEqual(renamed?.path, "new.txt")   // new path, not "old.txt -> new.txt"
    }

    func testStatusPathWithSpacesIsNotQuoted() throws {
        // Regression: porcelain v1 C-quotes any path containing a space
        // (`?? "My File.txt"`); the parser used to return the quotes verbatim.
        let root = try makeRepo()
        try write("hello", to: "My File.txt", in: root)
        let status = Git.status(repoRoot: root)
        XCTAssertEqual(status.count, 1)
        XCTAssertEqual(status.first?.path, "My File.txt")
        XCTAssertEqual(status.first?.kind, .untracked)
    }

    func testStatusNonASCIIPathIsNotOctalEscaped() throws {
        // Regression: with core.quotepath=true (the default), porcelain v1 emits
        // non-ASCII names as literal octal escapes (`"caf\303\251.txt"`).
        let root = try makeRepo()
        try write("hello", to: "café.txt", in: root)
        let status = Git.status(repoRoot: root)
        XCTAssertEqual(status.count, 1)
        XCTAssertEqual(status.first?.path.precomposedStringWithCanonicalMapping,
                       "café.txt".precomposedStringWithCanonicalMapping)
        XCTAssertEqual(status.first?.kind, .untracked)
    }

    func testStatusArrowInFilenameIsNotSplitAsRename() throws {
        // Regression: the " -> " rename split was applied to every line, so an
        // untracked file literally named `notes -> final.txt` was truncated.
        let root = try makeRepo()
        try write("hello", to: "notes -> final.txt", in: root)
        let status = Git.status(repoRoot: root)
        XCTAssertEqual(status.count, 1)
        XCTAssertEqual(status.first?.path, "notes -> final.txt")
        XCTAssertEqual(status.first?.kind, .untracked)
    }

    func testStatusRenamedPathsWithSpaces() throws {
        // Renames of C-quotable paths: `-z` emits `XY new\0old\0`, so the new
        // path must come back verbatim and the old-path field must be skipped.
        let root = try makeRepo()
        try write("stable contents that git can match on rename\n", to: "old name.txt", in: root)
        _ = Git.stage(root.appendingPathComponent("old name.txt"), repoRoot: root)
        commit("add old name", in: root)
        _ = Git.run(["mv", "old name.txt", "new name.txt"], in: root)
        let status = Git.status(repoRoot: root)
        XCTAssertEqual(status.count, 1)
        XCTAssertEqual(status.first?.path, "new name.txt")
        XCTAssertEqual(status.first?.kind, .renamed)
    }

    // MARK: - stage / unstage / discard

    func testStageThenUnstage() throws {
        let root = try makeRepo()
        // Seed an initial commit so HEAD exists — `git restore --staged` needs it,
        // as it does for any real repository under review.
        try write("seed", to: "seed.txt", in: root)
        _ = Git.stage(root.appendingPathComponent("seed.txt"), repoRoot: root)
        commit("seed", in: root)

        try write("body", to: "s.txt", in: root)
        XCTAssertTrue(Git.stage(root.appendingPathComponent("s.txt"), repoRoot: root))
        XCTAssertEqual(Git.status(repoRoot: root).first { $0.path == "s.txt" }?.kind, .added)
        XCTAssertTrue(Git.unstage(root.appendingPathComponent("s.txt"), repoRoot: root))
        XCTAssertEqual(Git.status(repoRoot: root).first { $0.path == "s.txt" }?.kind, .untracked)
    }

    func testDiscardUntrackedDeletesFile() throws {
        let root = try makeRepo()
        let file = root.appendingPathComponent("junk.txt")
        try write("junk", to: "junk.txt", in: root)
        XCTAssertTrue(Git.discard(file, kind: .untracked, repoRoot: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testDiscardModifiedRevertsToHead() throws {
        let root = try makeRepo()
        let file = root.appendingPathComponent("c.txt")
        try write("original\n", to: "c.txt", in: root)
        _ = Git.stage(file, repoRoot: root)
        commit("add c", in: root)
        try write("tampered\n", to: "c.txt", in: root)
        XCTAssertTrue(Git.discard(file, kind: .modified, repoRoot: root))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "original\n")
        XCTAssertTrue(Git.status(repoRoot: root).isEmpty)
    }

    func testDiscardStagedAdditionRemovesFromIndexAndDisk() throws {
        // Regression: `checkout HEAD -- <path>` exits 1 for a staged-new file
        // (the pathspec doesn't exist in HEAD), so the confirmed discard was a
        // silent no-op. Reverting to HEAD means the file goes away entirely.
        let root = try makeRepo()
        try write("seed\n", to: "seed.txt", in: root)
        _ = Git.stage(root.appendingPathComponent("seed.txt"), repoRoot: root)
        commit("seed", in: root)

        let file = root.appendingPathComponent("new.txt")
        try write("brand new\n", to: "new.txt", in: root)
        _ = Git.stage(file, repoRoot: root)
        XCTAssertEqual(Git.status(repoRoot: root).first { $0.path == "new.txt" }?.kind, .added)

        XCTAssertTrue(Git.discard(file, kind: .added, repoRoot: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(Git.status(repoRoot: root).isEmpty)
    }

    func testDiscardRenameRestoresOldNameAndRemovesNew() throws {
        // Regression: status reports a rename under its NEW path, which doesn't
        // exist in HEAD — `checkout HEAD -- <new>` exited 1 and nothing reverted.
        let root = try makeRepo()
        try write("contents\n", to: "old.txt", in: root)
        _ = Git.stage(root.appendingPathComponent("old.txt"), repoRoot: root)
        commit("seed", in: root)
        _ = Git.run(["mv", "old.txt", "renamed.txt"], in: root)
        XCTAssertEqual(Git.status(repoRoot: root).first?.kind, .renamed)

        XCTAssertTrue(Git.discard(root.appendingPathComponent("renamed.txt"),
                                  kind: .renamed, repoRoot: root))
        XCTAssertTrue(Git.status(repoRoot: root).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("renamed.txt").path))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("old.txt"),
                                  encoding: .utf8), "contents\n")
    }

    func testDiscardRenameWithSpacedPaths() throws {
        let root = try makeRepo()
        try write("contents\n", to: "old name.txt", in: root)
        _ = Git.stage(root.appendingPathComponent("old name.txt"), repoRoot: root)
        commit("seed", in: root)
        _ = Git.run(["mv", "old name.txt", "new name.txt"], in: root)

        XCTAssertTrue(Git.discard(root.appendingPathComponent("new name.txt"),
                                  kind: .renamed, repoRoot: root))
        XCTAssertTrue(Git.status(repoRoot: root).isEmpty)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("old name.txt"),
                                  encoding: .utf8), "contents\n")
    }

    func testDiscardRefusesFileOutsideRepoAndDoesNotClobberSameNamedRootFile() throws {
        // Regression: `relativePath` used to fall back to the bare filename for a
        // file it couldn't place under root, so `discard` ran
        // `git checkout HEAD -- config.json` and wiped an UNRELATED root-level
        // file's local edits. Mutating actions must refuse instead.
        let root = try makeRepo()
        try write("original\n", to: "config.json", in: root)
        _ = Git.stage(root.appendingPathComponent("config.json"), repoRoot: root)
        commit("add config", in: root)
        try write("precious local edits\n", to: "config.json", in: root)

        let outside = URL(fileURLWithPath: "/elsewhere/sub/config.json")
        XCTAssertFalse(Git.discard(outside, kind: .modified, repoRoot: root))
        XCTAssertFalse(Git.stage(outside, repoRoot: root))
        XCTAssertFalse(Git.unstage(outside, repoRoot: root))
        // The unrelated root-level file's edits must survive.
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("config.json"),
                                  encoding: .utf8), "precious local edits\n")
    }

    func testDiscardDeletedFileViaUnresolvedSymlinkFormRestoresRightFile() throws {
        // Regression (end-to-end form of the /private/var finding): discarding a
        // DELETED sub/config.json used to fall back to the "config.json" pathspec,
        // reverting the root-level config.json instead of restoring the deletion.
        let root = try makeRepo()
        try XCTSkipUnless(root.path.hasPrefix("/private/var/"),
                          "requires the macOS /private/var temp symlink")
        let sub = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try write("root original\n", to: "config.json", in: root)
        try write("sub original\n", to: "sub/config.json", in: root)
        _ = Git.stage(root.appendingPathComponent("config.json"), repoRoot: root)
        _ = Git.stage(root.appendingPathComponent("sub/config.json"), repoRoot: root)
        commit("seed both", in: root)
        try write("root local edits\n", to: "config.json", in: root)
        try FileManager.default.removeItem(at: sub.appendingPathComponent("config.json"))

        let deleted = URL(fileURLWithPath: root.path + "/sub/config.json")
        XCTAssertTrue(Git.discard(deleted, kind: .deleted, repoRoot: root))
        XCTAssertEqual(try String(contentsOf: sub.appendingPathComponent("config.json"),
                                  encoding: .utf8), "sub original\n")   // restored
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("config.json"),
                                  encoding: .utf8), "root local edits\n")   // untouched
    }

    // MARK: - lineChanges

    func testLineChangesMarksModifiedLine() throws {
        let root = try makeRepo()
        let file = root.appendingPathComponent("code.txt")
        try write("line1\nline2\nline3\n", to: "code.txt", in: root)
        _ = Git.stage(file, repoRoot: root)
        commit("seed code", in: root)
        try write("line1\nCHANGED\nline3\n", to: "code.txt", in: root)
        let marks = Git.lineChanges(for: file, repoRoot: root)
        XCTAssertEqual(marks[2], .modified)
        XCTAssertNil(marks[1])
        XCTAssertNil(marks[3])
    }

    func testLineChangesMarksAddedLines() throws {
        let root = try makeRepo()
        let file = root.appendingPathComponent("code.txt")
        try write("a\nb\n", to: "code.txt", in: root)
        _ = Git.stage(file, repoRoot: root)
        commit("seed", in: root)
        try write("a\nb\nc\nd\n", to: "code.txt", in: root)
        let marks = Git.lineChanges(for: file, repoRoot: root)
        XCTAssertEqual(marks[3], .added)
        XCTAssertEqual(marks[4], .added)
    }

    func testLineChangesAllMatchesPerFileCalls() throws {
        // One `git diff --unified=0 HEAD` spawn must report the same per-file maps
        // as N per-file lineChanges calls — including content lines the diff
        // renders as "+++ b/…" / "--- a/…" (an added "++ b/decoy" line), which
        // must not be mistaken for file headers mid-hunk.
        let root = try makeRepo()
        try write("line1\nline2\nline3\n", to: "one.txt", in: root)
        try write("a\nb\nc\nd\ne\n", to: "two.txt", in: root)
        try write("keep\n", to: "gone.txt", in: root)
        for f in ["one.txt", "two.txt", "gone.txt"] {
            _ = Git.stage(root.appendingPathComponent(f), repoRoot: root)
        }
        commit("seed", in: root)
        try write("line1\nCHANGED\nline3\nadded\n", to: "one.txt", in: root)
        try write("++ b/decoy\na\nb\nc\nd\nCHANGED\n", to: "two.txt", in: root)
        try FileManager.default.removeItem(at: root.appendingPathComponent("gone.txt"))
        try write("untracked\n", to: "new.txt", in: root)

        let all = Git.lineChangesAll(repoRoot: root)
        XCTAssertNil(all["decoy"])
        for f in ["one.txt", "two.txt", "gone.txt"] {
            XCTAssertEqual(all[f], Git.lineChanges(for: root.appendingPathComponent(f), repoRoot: root), f)
        }
        XCTAssertNil(all["new.txt"])   // untracked: absent, like the per-file call's [:]
        XCTAssertEqual(all["one.txt"]?[2], .modified)
        XCTAssertEqual(all["one.txt"]?[4], .added)
    }

    // MARK: - removedLines

    func testRemovedLinesGhostsDeletedRowAboveSurvivingLine() throws {
        let root = try makeRepo()
        let file = root.appendingPathComponent("code.txt")
        try write("a\nb\nc\n", to: "code.txt", in: root)
        _ = Git.stage(file, repoRoot: root)
        commit("seed", in: root)
        try write("a\nc\n", to: "code.txt", in: root)   // delete "b"
        let removed = Git.removedLines(for: file, repoRoot: root)
        XCTAssertEqual(removed[2], ["b"])   // "b" ghosts above new line 2 ("c")
    }

    // MARK: - blame

    func testBlameReportsAuthorAndSummary() throws {
        let root = try makeRepo()
        let file = root.appendingPathComponent("b.txt")
        try write("first line\n", to: "b.txt", in: root)
        _ = Git.stage(file, repoRoot: root)
        commit("initial import", in: root)
        let info = try XCTUnwrap(Git.blame(for: file, line: 1, repoRoot: root))
        XCTAssertEqual(info.author, "Test Author")
        XCTAssertEqual(info.summary, "initial import")
        XCTAssertFalse(info.timeAgo.isEmpty)
    }

    func testBlameNilForNonPositiveLine() throws {
        let root = try makeRepo()
        try write("x\n", to: "b.txt", in: root)
        _ = Git.stage(root.appendingPathComponent("b.txt"), repoRoot: root)
        commit("c", in: root)
        XCTAssertNil(Git.blame(for: root.appendingPathComponent("b.txt"), line: 0, repoRoot: root))
    }

    // MARK: - currentBranch / worktrees

    /// Fresh temp directory path (not created) for `git worktree add`, cleaned up in tearDown.
    private func worktreeScratchPath(_ label: String) -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gitcli-wt-\(label)-\(UUID().uuidString)", isDirectory: true)
        scratchDirs.append(dir)
        return dir
    }

    func testCurrentBranchReportsCheckedOutBranch() throws {
        let root = try makeRepo()
        try write("x\n", to: "f.txt", in: root)
        _ = Git.stage(root.appendingPathComponent("f.txt"), repoRoot: root)
        commit("seed", in: root)
        XCTAssertNotNil(Git.run(["checkout", "-q", "-b", "feature-x"], in: root))
        XCTAssertEqual(Git.currentBranch(repoRoot: root), "feature-x")
    }

    func testCurrentBranchDetachedHeadFallsBackToShortSHA() throws {
        let root = try makeRepo()
        try write("x\n", to: "f.txt", in: root)
        _ = Git.stage(root.appendingPathComponent("f.txt"), repoRoot: root)
        commit("seed", in: root)
        let sha = try XCTUnwrap(Git.run(["rev-parse", "--short", "HEAD"], in: root))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertNotNil(Git.run(["checkout", "-q", "--detach", "HEAD"], in: root))
        let branch = Git.currentBranch(repoRoot: root)
        XCTAssertEqual(branch, sha)
        XCTAssertNotEqual(branch, "HEAD")   // the literal detached marker must never leak out
    }

    func testCurrentBranchNilForUnbornHead() throws {
        let root = try makeRepo()   // no commits yet — HEAD is unborn, rev-parse fails
        XCTAssertNil(Git.currentBranch(repoRoot: root))
    }

    func testWorktreesListsMainAndLinkedWorktree() throws {
        let root = try makeRepo()
        try write("x\n", to: "f.txt", in: root)
        _ = Git.stage(root.appendingPathComponent("f.txt"), repoRoot: root)
        commit("seed", in: root)
        XCTAssertNotNil(Git.run(["checkout", "-q", "-b", "main-branch"], in: root))
        let linkedPath = worktreeScratchPath("linked")
        XCTAssertNotNil(Git.run(["worktree", "add", "-q", linkedPath.path, "-b", "wt-branch"],
                                in: root))

        let trees = Git.worktrees(repoRoot: root)
        XCTAssertEqual(trees.count, 2)

        let main = try XCTUnwrap(trees.first)
        XCTAssertTrue(main.isMain)
        XCTAssertEqual(main.branch, "main-branch")   // refs/heads/ prefix stripped
        XCTAssertTrue(main.isCurrent(relativeTo: root))

        let linked = try XCTUnwrap(trees.last)
        XCTAssertFalse(linked.isMain)
        XCTAssertEqual(linked.branch, "wt-branch")
        XCTAssertFalse(linked.isCurrent(relativeTo: root))
        // Canonical comparison must reconcile git's /private/var form with the
        // /var form the test created the directory under.
        XCTAssertTrue(linked.isCurrent(relativeTo: linkedPath))
    }

    func testWorktreesFromInsideLinkedWorktree() throws {
        let root = try makeRepo()
        try write("x\n", to: "f.txt", in: root)
        _ = Git.stage(root.appendingPathComponent("f.txt"), repoRoot: root)
        commit("seed", in: root)
        let linkedPath = worktreeScratchPath("inside")
        XCTAssertNotNil(Git.run(["worktree", "add", "-q", linkedPath.path, "-b", "wt-inside"],
                                in: root))

        // repoRoot from inside the linked worktree reports the LINKED root.
        let linkedRoot = try XCTUnwrap(Git.repoRoot(for: linkedPath))
        let trees = Git.worktrees(repoRoot: linkedRoot)
        XCTAssertEqual(trees.count, 2)
        XCTAssertTrue(trees[0].isMain)                              // main still listed first
        XCTAssertFalse(trees[0].isCurrent(relativeTo: linkedRoot))
        XCTAssertTrue(trees[1].isCurrent(relativeTo: linkedRoot))
        XCTAssertEqual(Git.currentBranch(repoRoot: linkedRoot), "wt-inside")
    }

    func testWorktreesDetachedLinkedWorktreeHasNilBranch() throws {
        let root = try makeRepo()
        try write("x\n", to: "f.txt", in: root)
        _ = Git.stage(root.appendingPathComponent("f.txt"), repoRoot: root)
        commit("seed", in: root)
        let linkedPath = worktreeScratchPath("detached")
        XCTAssertNotNil(Git.run(["worktree", "add", "-q", "--detach", linkedPath.path],
                                in: root))

        let trees = Git.worktrees(repoRoot: root)
        XCTAssertEqual(trees.count, 2)
        XCTAssertNotNil(trees[0].branch)   // main is on a real branch
        XCTAssertNil(trees[1].branch)      // detached entry has no branch line
    }

    // MARK: - run

    func testRunReturnsNilOnFailure() throws {
        let root = try makeRepo()
        XCTAssertNil(Git.run(["definitely-not-a-git-subcommand"], in: root))
    }

    func testRunDoesNotDeadlockOnLargeStderr() throws {
        // Regression: `run` attached a stderr Pipe it never drained, so a child
        // writing >= ~64KB (one kernel pipe buffer) to stderr blocked in write(2)
        // while we blocked reading stdout to EOF — a permanent mutual deadlock.
        // Exercise the exact pipe wiring via the swappable `executable` hook.
        let saved = Git.executable
        defer { Git.executable = saved }
        Git.executable = "/bin/sh"
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        let out = Git.run(["-c", "i=0; while [ $i -lt 4096 ]; do echo 'stderr noise stderr noise stderr noise' 1>&2; i=$((i+1)); done; echo ok"], in: dir)
        XCTAssertEqual(out, "ok\n")
    }

    // MARK: - counts (pure hunk-field parser)

    func testCountsParsesStartAndCount() {
        XCTAssertEqual(Git.counts(Substring("+12,3")).0, 12)
        XCTAssertEqual(Git.counts(Substring("+12,3")).1, 3)
        XCTAssertEqual(Git.counts(Substring("-40,7")).0, 40)
        XCTAssertEqual(Git.counts(Substring("-40,7")).1, 7)
    }

    func testCountsDefaultsMissingCountToOne() {
        XCTAssertEqual(Git.counts(Substring("+5")).1, 1)
        XCTAssertEqual(Git.counts(Substring("-1")).1, 1)
    }

    func testCountsHandlesZeroCount() {
        let (start, count) = Git.counts(Substring("+1,0"))
        XCTAssertEqual(start, 1)
        XCTAssertEqual(count, 0)
    }

    // MARK: - relativeTime (pure, deterministic via injected `now`)

    func testRelativeTimeBuckets() {
        let t: TimeInterval = 1_000_000
        XCTAssertEqual(Git.relativeTime(t, now: t + 30), "just now")
        XCTAssertEqual(Git.relativeTime(t, now: t + 120), "2m ago")
        XCTAssertEqual(Git.relativeTime(t, now: t + 2 * 3600), "2h ago")
        XCTAssertEqual(Git.relativeTime(t, now: t + 3 * 86400), "3d ago")
        XCTAssertEqual(Git.relativeTime(t, now: t + 40 * 86400), "1mo ago")
        XCTAssertEqual(Git.relativeTime(t, now: t + 400 * 86400), "1y ago")
    }
}
