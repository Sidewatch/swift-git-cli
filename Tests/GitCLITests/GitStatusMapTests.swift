//
//  GitStatusMapTests.swift
//  Tests for GitStatusMap.build (path keying, ancestor-dir marking, deleted
//  exclusion, untracked-directory entries) and GitChangeKind.letter. Pure —
//  build only touches disk to resolve the repo root's symlink aliases.
//

import XCTest
@testable import GitCLI

final class GitStatusMapTests: XCTestCase {

    private let root = URL(fileURLWithPath: "/repo")

    // MARK: - letter

    func testChangeKindLetters() {
        XCTAssertEqual(GitChangeKind.added.letter, "A")
        XCTAssertEqual(GitChangeKind.modified.letter, "M")
        XCTAssertEqual(GitChangeKind.deleted.letter, "D")
        XCTAssertEqual(GitChangeKind.renamed.letter, "R")
        XCTAssertEqual(GitChangeKind.untracked.letter, "U")
    }

    // MARK: - build: lookups

    /// The changed-file LIST must be canonical: `kinds` keys each file under
    /// every root alias (/tmp + /private/tmp) for O(1) lookups, but a list with
    /// one entry per alias doubled search rows and made targeted replace report
    /// phantom failures.
    func testChangedFilePathsAreDeduplicatedAcrossRootAliases() {
        let map = GitStatusMap.build(status: [("src/a.swift", .modified), ("b.swift", .added)],
                                     repoRoot: root)
        XCTAssertEqual(map.changedFilePaths.count, 2,
                       "one entry per FILE, not per root alias: \(map.changedFilePaths)")
        // Every listed path still resolves through the aliased lookup table.
        for p in map.changedFilePaths {
            XCTAssertNotNil(map.kind(for: URL(fileURLWithPath: p)), p)
        }
    }

    func testKindLookupByAbsolutePath() {
        let map = GitStatusMap.build(status: [("src/main.swift", .modified)], repoRoot: root)
        XCTAssertEqual(map.kind(for: root.appendingPathComponent("src/main.swift")), .modified)
        XCTAssertNil(map.kind(for: root.appendingPathComponent("src/other.swift")))
    }

    func testAncestorDirectoriesMarked() {
        let map = GitStatusMap.build(status: [("a/b/c/file.swift", .added)], repoRoot: root)
        XCTAssertTrue(map.directoryContainsChanges(root.appendingPathComponent("a")))
        XCTAssertTrue(map.directoryContainsChanges(root.appendingPathComponent("a/b")))
        XCTAssertTrue(map.directoryContainsChanges(root.appendingPathComponent("a/b/c")))
        XCTAssertTrue(map.directoryContainsChanges(root))          // root itself
        XCTAssertFalse(map.directoryContainsChanges(root.appendingPathComponent("z")))
    }

    func testDeletedFilesExcluded() {
        let map = GitStatusMap.build(status: [("gone.swift", .deleted)], repoRoot: root)
        XCTAssertEqual(map, .empty)                                 // only deletion → empty
        XCTAssertNil(map.kind(for: root.appendingPathComponent("gone.swift")))
    }

    func testDeletedMixedWithLiveKeepsLiveOnly() {
        let map = GitStatusMap.build(
            status: [("keep.swift", .modified), ("gone.swift", .deleted)], repoRoot: root)
        XCTAssertEqual(map.kind(for: root.appendingPathComponent("keep.swift")), .modified)
        XCTAssertNil(map.kind(for: root.appendingPathComponent("gone.swift")))
    }

    func testUntrackedDirectoryEntryMarksFolderNotFile() {
        // The collapsed "?? NewFeature/" form: the folder gets a dot, but there's
        // no file kind to look up.
        let map = GitStatusMap.build(status: [("NewFeature/", .untracked)], repoRoot: root)
        XCTAssertTrue(map.directoryContainsChanges(root.appendingPathComponent("NewFeature")))
        XCTAssertNil(map.kind(for: root.appendingPathComponent("NewFeature")))
    }

    func testEmptyStatusYieldsEmptyMap() {
        XCTAssertEqual(GitStatusMap.build(status: [], repoRoot: root), .empty)
    }

    func testPrivateVarAliasingResolvesUnderTempDir() throws {
        // A real temp dir lives under /var → /private/var (a macOS symlink). A
        // lookup keyed via the /private side must still hit an entry built from
        // the /var side (and vice-versa).
        let realRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GitStatusMapTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: realRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: realRoot) }

        let map = GitStatusMap.build(status: [("f.swift", .modified)], repoRoot: realRoot)
        let stripped = URL(fileURLWithPath:
            (realRoot.path as NSString).resolvingSymlinksInPath).appendingPathComponent("f.swift")
        XCTAssertEqual(map.kind(for: stripped), .modified)
    }
}
