//
//  HunkHeader.swift
//  SwiftGitCLI
//
//  The `@@ -old +new @@` line of a unified diff, parsed once.
//
//  Created by David Sherlock on 8/6/26.
//

import Foundation

/// A unified-diff hunk header: `@@ -oldStart[,oldCount] +newStart[,newCount] @@ [section]`.
///
/// This existed three times before it existed once — twice inside this package
/// (``Git/lineDiff(for:repoRoot:)`` and ``Git/lineChangesAll(repoRoot:)``) and once in
/// Sidewatch's side-by-side viewer, which had drifted into a weaker variant: it read only the
/// two start lines, ignored the counts entirely, and so could not tell an addition from a
/// modification or spot a pure deletion. Every consumer of a `git diff` needs this exact
/// parse, so it belongs with the git wrapper rather than being re-derived per view.
///
/// The counts are genuinely load-bearing, which is why the weaker variant was a latent bug and
/// not merely duplication: `oldCount == 0` means text was only added, `newCount == 0` means it
/// was only removed, and the difference decides whether a line is marked added, modified, or
/// deleted. See ``changeKind``.
public struct HunkHeader: Equatable, Sendable {

    /// 1-based first line of the hunk on the OLD side.
    public let oldStart: Int

    /// Number of old-side lines in the hunk. `0` means the hunk is a pure insertion.
    public let oldCount: Int

    /// 1-based first line of the hunk on the NEW side.
    public let newStart: Int

    /// Number of new-side lines in the hunk. `0` means the hunk is a pure deletion.
    public let newCount: Int

    /// Creates a header from its four fields.
    public init(oldStart: Int, oldCount: Int, newStart: Int, newCount: Int) {
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
    }

    /// How this hunk should be marked in a gutter or change list.
    ///
    /// A hunk that produces no new lines is a deletion; one that consumed no old lines is an
    /// addition; anything else replaced text and is a modification. Checking `newCount` first
    /// matters — a hunk with both counts zero is degenerate, and reporting it as "deleted"
    /// keeps it out of the added/modified marks rather than marking a zero-length range.
    public var changeKind: GitChangeKind {
        if newCount == 0 { return .deleted }
        return oldCount == 0 ? .added : .modified
    }

    /// The new-side line range this hunk marks, empty for a pure deletion.
    ///
    /// A pure deletion has no new-side lines of its own; callers mark `max(1, newStart)` as
    /// deleted instead. Clamped to 1 because git reports `newStart` as 0 when a hunk removes
    /// the very first line of a file, and there is no line 0 to mark.
    public var newLineRange: Range<Int> {
        guard newCount > 0 else { return 0..<0 }
        return newStart..<(newStart + newCount)
    }

    /// Parses a `@@ … @@` header line, or returns nil when it is not one / is malformed.
    ///
    /// Tolerant in the ways real `git diff` output requires: a missing count means `1` (the
    /// unified-diff shorthand, so `-5` is `(5, 1)`), a trailing section heading after the
    /// closing `@@` is ignored, and anything that does not start with `@@` is rejected rather
    /// than half-parsed.
    ///
    /// - Parameter line: One line of unified-diff output, with or without its trailing newline.
    /// - Returns: The parsed header, or nil if `line` is not a well-formed hunk header.
    public static func parse(_ line: some StringProtocol) -> HunkHeader? {
        guard line.hasPrefix("@@") else { return nil }
        let parts = line.split(separator: " ")
        // parts[0] == "@@", parts[1] == "-old[,count]", parts[2] == "+new[,count]"
        guard parts.count >= 3, parts[1].hasPrefix("-"), parts[2].hasPrefix("+") else { return nil }
        guard let old = field(parts[1]), let new = field(parts[2]) else { return nil }
        return HunkHeader(oldStart: old.start, oldCount: old.count,
                          newStart: new.start, newCount: new.count)
    }

    /// Parses one `±start[,count]` field. Returns nil when the start is not a number, so a
    /// malformed header is rejected outright instead of silently becoming `(0, 1)`.
    ///
    /// Generic over `StringProtocol` so it accepts whatever `split` produced from the caller's
    /// line type — `Substring` from a `String`, but `Substring.SubSequence` when the caller
    /// already handed us a slice.
    private static func field(_ f: some StringProtocol) -> (start: Int, count: Int)? {
        let nums = f.dropFirst().split(separator: ",")   // strip the +/-
        guard let first = nums.first, let start = Int(first) else { return nil }
        let count = nums.count > 1 ? (Int(nums[1]) ?? 1) : 1
        return (start, count)
    }
}
