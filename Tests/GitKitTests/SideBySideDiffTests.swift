//
//  SideBySideDiffTests.swift
//  GitKitTests
//
//  Tests for the side-by-side alignment of a unified diff.
//
//  Created by David Sherlock on 9/6/26.
//

import XCTest
@testable import GitKit

final class SideBySideDiffTests: XCTestCase {

    private let diff = """
    diff --git a/a.txt b/a.txt
    index 1111111..2222222 100644
    --- a/a.txt
    +++ b/a.txt
    @@ -1,4 +1,5 @@
     keep
    -old one
    -old two
    +new one
    +new two
    +new three
     tail
    \\ No newline at end of file

    """

    func testPairsChangedRunsAndFillsTheOverflow() {
        let (left, right) = SideBySideDiff.rows(from: diff)
        XCTAssertEqual(left.count, right.count)
        XCTAssertEqual(left.map(\.kind), [.header, .context, .modified, .modified, .filler, .context])
        XCTAssertEqual(right.map(\.kind), [.header, .context, .modified, .modified, .added, .context])
        XCTAssertEqual(left[2].text, "old one"); XCTAssertEqual(right[2].text, "new one")
        XCTAssertEqual(right[4].text, "new three"); XCTAssertEqual(left[4].text, "")
        XCTAssertNil(left[4].number, "a filler has no line number")
    }

    func testLineNumbersFollowTheHunkHeader() {
        let (left, right) = SideBySideDiff.rows(from: diff)
        XCTAssertEqual(left.map(\.number), [nil, 1, 2, 3, nil, 4])
        XCTAssertEqual(right.map(\.number), [nil, 1, 2, 3, 4, 5])
        XCTAssertEqual(left.last?.text, "tail", "the no-newline marker made no row")
    }

    func testASecondFileRestartsTheWalk() {
        let two = diff + "diff --git a/b.txt b/b.txt\nindex 3..4 100644\n--- a/b.txt\n+++ b/b.txt\n@@ -10,1 +10,1 @@\n-x\n+y\n"
        let (left, right) = SideBySideDiff.rows(from: two)
        XCTAssertEqual(left.count, 8, "the second file's headers are not rows")
        XCTAssertEqual(left[6].kind, .header); XCTAssertEqual(left[7].number, 10); XCTAssertEqual(right[7].number, 10)
        XCTAssertEqual(left[7].kind, .modified)
    }

    func testABlankContextLineWithoutItsLeadingSpaceStillCounts() {
        let d = "@@ -1,3 +1,3 @@\n a\n\n c\n"
        let (left, _) = SideBySideDiff.rows(from: d)
        XCTAssertEqual(left.map(\.number), [nil, 1, 2, 3])
        XCTAssertEqual(left[2].kind, .context)
    }

    func testAPureAdditionAndAPureRemoval() {
        let (l1, r1) = SideBySideDiff.rows(from: "@@ -0,0 +1,2 @@\n+a\n+b\n")
        XCTAssertEqual(l1.map(\.kind), [.header, .filler, .filler]); XCTAssertEqual(r1.map(\.kind), [.header, .added, .added])
        let (l2, r2) = SideBySideDiff.rows(from: "@@ -1,2 +0,0 @@\n-a\n-b\n")
        XCTAssertEqual(l2.map(\.kind), [.header, .removed, .removed]); XCTAssertEqual(r2.map(\.kind), [.header, .filler, .filler])
    }
}
