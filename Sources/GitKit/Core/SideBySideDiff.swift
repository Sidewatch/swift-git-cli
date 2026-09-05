//
//  SideBySideDiff.swift
//  GitKit
//
//  A unified diff as two aligned columns — the standard side-by-side layout.
//
//  Created by David Sherlock on 9/6/26.
//

import Foundation

/// Splits a unified diff into two equal-length row arrays (left = old side, right = new
/// side). Within a hunk, a run of removed lines followed by a run of added lines pairs
/// index-wise as `modified` rows; the longer run's overflow gets `filler` rows on the
/// opposite side. File-header lines (`diff --git`, `index`, `---`/`+++`, …) carry no per-side
/// content and are skipped; `@@` headers render on both sides and restart the numbering.
public enum SideBySideDiff {

    public static func rows(from diff: String) -> (left: [SideBySideRow], right: [SideBySideRow]) {
        var builder = Builder()
        var lines = diff.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }          // the final newline's empty component
        for raw in lines { builder.take(raw) }
        builder.flushPending()
        return (builder.left, builder.right)
    }

    /// The walk's state: the two columns, the next line number per side, and the removed /
    /// added runs waiting to be paired.
    private struct Builder {
        var left: [SideBySideRow] = [], right: [SideBySideRow] = []
        var oldN = 1, newN = 1
        var pendingRemoved: [String] = [], pendingAdded: [String] = []
        var inHunk = false

        mutating func take(_ raw: String) {
            // A multi-file diff restarts here. Without leaving hunk state, the NEXT file's
            // index/---/+++ headers would be treated as content and render as added/removed
            // rows — and a diff can legitimately hold several files.
            if raw.hasPrefix("diff --git ") {
                flushPending()
                inHunk = false
            } else if raw.hasPrefix("@@") {
                flushPending()
                inHunk = true
                if let hunk = HunkHeader.parse(raw) { oldN = hunk.oldStart; newN = hunk.newStart }
                left.append(SideBySideRow(number: nil, text: raw, kind: .header))
                right.append(SideBySideRow(number: nil, text: raw, kind: .header))
            } else if !inHunk {
                return                                       // file header (index / --- / +++ / mode …)
            } else if raw.hasPrefix("\\") {
                return                                       // "\ No newline at end of file": no row of its own
            } else if raw.hasPrefix("-") {
                pendingRemoved.append(String(raw.dropFirst()))
            } else if raw.hasPrefix("+") {
                pendingAdded.append(String(raw.dropFirst()))
            } else {
                // A context line, leading space stripped. A fully empty component is a blank
                // context row too: git emits blank context lines with no leading space when
                // `diff.suppressBlankEmpty` is set, and dropping them would drift every line
                // number below in the hunk.
                flushPending()
                let text = String(raw.dropFirst())
                left.append(SideBySideRow(number: oldN, text: text, kind: .context))
                right.append(SideBySideRow(number: newN, text: text, kind: .context))
                oldN += 1
                newN += 1
            }
        }

        /// Emits the buffered removed/added runs as modified pairs plus filler overflow.
        mutating func flushPending() {
            let pairs = min(pendingRemoved.count, pendingAdded.count)
            for i in 0..<pairs {
                left.append(SideBySideRow(number: oldN + i, text: pendingRemoved[i], kind: .modified))
                right.append(SideBySideRow(number: newN + i, text: pendingAdded[i], kind: .modified))
            }
            for i in pairs..<pendingRemoved.count {
                left.append(SideBySideRow(number: oldN + i, text: pendingRemoved[i], kind: .removed))
                right.append(SideBySideRow(number: nil, text: "", kind: .filler))
            }
            for i in pairs..<pendingAdded.count {
                left.append(SideBySideRow(number: nil, text: "", kind: .filler))
                right.append(SideBySideRow(number: newN + i, text: pendingAdded[i], kind: .added))
            }
            oldN += pendingRemoved.count
            newN += pendingAdded.count
            pendingRemoved = []
            pendingAdded = []
        }
    }
}
