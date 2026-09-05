//
//  HunkHeaderTests.swift
//  SwiftGitCLI
//
//  Covers ``HunkHeader``, the unified-diff hunk header parser that replaced three hand-rolled
//  copies.
//
//  Created by David Sherlock on 8/6/26.
//

import XCTest
@testable import GitKit

/// Covers ``HunkHeader``, the unified-diff hunk header parser that replaced three
/// hand-rolled copies. The cases that matter most are the ones the weakest copy got wrong:
/// it read only the two start lines, so counts — and therefore added-vs-modified-vs-deleted —
/// were invisible to it.
final class HunkHeaderTests: XCTestCase {

    // MARK: - Shape

    func testParsesBothCounts() {
        let h = HunkHeader.parse("@@ -12,3 +40,5 @@")
        XCTAssertEqual(h, HunkHeader(oldStart: 12, oldCount: 3, newStart: 40, newCount: 5))
    }

    /// The unified-diff shorthand: a field with no comma means a count of exactly 1.
    /// Defaulting this to 0 would make every single-line hunk look like a pure insert/delete.
    func testMissingCountMeansOne() {
        let h = HunkHeader.parse("@@ -5 +9 @@")
        XCTAssertEqual(h, HunkHeader(oldStart: 5, oldCount: 1, newStart: 9, newCount: 1))
    }

    func testMixedShorthandAndExplicitCount() {
        XCTAssertEqual(HunkHeader.parse("@@ -5 +9,4 @@"),
                       HunkHeader(oldStart: 5, oldCount: 1, newStart: 9, newCount: 4))
        XCTAssertEqual(HunkHeader.parse("@@ -5,2 +9 @@"),
                       HunkHeader(oldStart: 5, oldCount: 2, newStart: 9, newCount: 1))
    }

    /// `git diff` appends the enclosing function/section after the closing `@@`. It is
    /// free-form text and must not disturb the parse — including when it contains spaces
    /// or its own `@@`.
    func testIgnoresTrailingSectionHeading() {
        XCTAssertEqual(HunkHeader.parse("@@ -1,2 +3,4 @@ func doThing(a: Int) -> String {"),
                       HunkHeader(oldStart: 1, oldCount: 2, newStart: 3, newCount: 4))
        XCTAssertEqual(HunkHeader.parse("@@ -1,2 +3,4 @@ weird @@ heading"),
                       HunkHeader(oldStart: 1, oldCount: 2, newStart: 3, newCount: 4))
    }

    // MARK: - Rejection

    func testRejectsNonHeaderLines() {
        for line in ["", " ", "+added", "-removed", " context",
                     "diff --git a/x b/x", "--- a/x", "+++ b/x", "@@", "@@ -1,2 @@"] {
            XCTAssertNil(HunkHeader.parse(line), "should reject \(line.debugDescription)")
        }
    }

    /// A header whose signs are the wrong way round is malformed, not silently swappable.
    func testRejectsSwappedSigns() {
        XCTAssertNil(HunkHeader.parse("@@ +1,2 -3,4 @@"))
    }

    /// A non-numeric start must fail the whole parse rather than degrade to 0 — a 0 start
    /// would silently mark line 0, which does not exist, instead of reporting a bad header.
    func testRejectsNonNumericStart() {
        XCTAssertNil(HunkHeader.parse("@@ -x,2 +3,4 @@"))
        XCTAssertNil(HunkHeader.parse("@@ -1,2 +y,4 @@"))
    }

    // MARK: - Change classification

    func testPureInsertionIsAdded() {
        XCTAssertEqual(HunkHeader.parse("@@ -0,0 +1,5 @@")?.changeKind, .added)
    }

    func testPureDeletionIsDeleted() {
        XCTAssertEqual(HunkHeader.parse("@@ -7,3 +6,0 @@")?.changeKind, .deleted)
    }

    func testReplacementIsModified() {
        XCTAssertEqual(HunkHeader.parse("@@ -7,3 +7,2 @@")?.changeKind, .modified)
    }

    /// Deletion is checked before addition, so a degenerate `-0,0 +0,0` reports `.deleted`
    /// and produces no line marks, rather than claiming a zero-length addition.
    func testDegenerateZeroZeroIsDeletedAndMarksNothing() {
        let h = HunkHeader.parse("@@ -0,0 +0,0 @@")
        XCTAssertEqual(h?.changeKind, .deleted)
        XCTAssertEqual(h?.newLineRange.isEmpty, true)
    }

    // MARK: - New-side range

    func testNewLineRangeCoversExactlyTheNewLines() {
        XCTAssertEqual(HunkHeader.parse("@@ -1,1 +40,3 @@")?.newLineRange, 40..<43)
    }

    func testNewLineRangeEmptyForPureDeletion() {
        XCTAssertEqual(HunkHeader.parse("@@ -7,3 +6,0 @@")?.newLineRange.isEmpty, true)
    }

    /// Removing a file's first line makes git report `+0,0`. There is no line 0, so callers
    /// clamp to 1 — the range itself must stay empty so nothing is marked twice.
    func testDeletionAtStartOfFileYieldsEmptyRange() {
        let h = HunkHeader.parse("@@ -1,2 +0,0 @@")
        XCTAssertEqual(h?.newStart, 0)
        XCTAssertEqual(h?.newLineRange.isEmpty, true)
        XCTAssertEqual(h?.changeKind, .deleted)
    }

    // MARK: - Accepts slices as well as strings

    /// The library parses lines produced by `split(separator:)`, so the entry point has to
    /// take a `Substring` as readily as a `String`.
    func testAcceptsSubstring() {
        let diff = "@@ -1,2 +3,4 @@\n+added\n"
        let first = diff.split(separator: "\n", omittingEmptySubsequences: false)[0]
        XCTAssertEqual(HunkHeader.parse(first),
                       HunkHeader(oldStart: 1, oldCount: 2, newStart: 3, newCount: 4))
    }
}
