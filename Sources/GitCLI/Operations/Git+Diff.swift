//
//  Git+Diff.swift
//  SwiftGitCLI
//
//  Line-level diff parsing: gutter markers and phantom removed rows.
//
//  Created by David Sherlock on 7/9/26.
//

import Foundation

public extension Git {

    /// Per-line change kind for one file versus `HEAD`, for editor gutter markers.
    ///
    /// Parses `git diff --unified=0`. Added and modified lines map to their
    /// 1-based working-copy line number; a pure deletion marks the surviving line
    /// just below the removal.
    ///
    /// - Returns: A map from 1-based line number to ``GitChangeKind``.
    static func lineChanges(for file: URL, repoRoot root: URL) -> [Int: GitChangeKind] {
        lineDiff(for: file, repoRoot: root).marks
    }

    /// Both gutter maps for one file versus `HEAD` — the per-line change kinds
    /// *and* the removed-line text — from a **single** `git diff --unified=0`
    /// run, where calling ``lineChanges(for:repoRoot:)`` and
    /// ``removedLines(for:repoRoot:)`` separately would spawn (and parse) the
    /// identical diff twice.
    ///
    /// - Returns: `marks` exactly as ``lineChanges(for:repoRoot:)`` returns it
    ///   (added/modified lines keyed by their 1-based working-copy line; a pure
    ///   deletion marks the surviving line just below), and `removed` exactly as
    ///   ``removedLines(for:repoRoot:)`` returns it (removed text keyed by the
    ///   1-based new-file line it renders above).
    static func lineDiff(for file: URL, repoRoot root: URL) -> (marks: [Int: GitChangeKind], removed: [Int: [String]]) {
        let rel = relativePath(file, root: root)
        guard let diff = run(["diff", "--unified=0", "--no-color", "HEAD", "--", rel], in: root) else {
            return ([:], [:])
        }
        var marks: [Int: GitChangeKind] = [:]
        var removed: [Int: [String]] = [:]
        var pending: [String] = []
        var anchor = 1
        var inHunk = false   // real `---`/`+++` file headers only precede the first @@
        func flush() {
            if !pending.isEmpty { removed[anchor, default: []].append(contentsOf: pending); pending = [] }
        }
        for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("@@") {
                flush()
                inHunk = true
                guard let hunk = HunkHeader.parse(line) else { continue }
                if hunk.changeKind == .deleted {
                    marks[max(1, hunk.newStart)] = .deleted       // pure deletion
                    anchor = max(1, hunk.newStart + 1)            // after a pure deletion
                } else {
                    for l in hunk.newLineRange { marks[l] = hunk.changeKind }
                    anchor = hunk.newStart                        // above the first new line
                }
            } else if inHunk, line.hasPrefix("-") {
                pending.append(String(line.dropFirst()))   // removed content (even if it starts with "--")
            }
        }
        flush()
        return (marks, removed)
    }

    /// Unified diff presenting an untracked file as all-new content — what
    /// `git diff HEAD` cannot show (untracked files are invisible to it).
    ///
    /// Runs `git diff --no-index /dev/null <path>`, which exits 1 when the
    /// inputs differ — its normal "found a difference" result, hence the widened
    /// exit contract. The output is a regular unified diff (`diff --git` header,
    /// `--- /dev/null`, `+++ b/<path>`, one all-additions hunk), so it splices
    /// cleanly into any combined-diff rendering.
    ///
    /// - Returns: The synthesized diff, or `""` when `file` is not under `root`
    ///   or is missing/unreadable.
    static func untrackedDiff(for file: URL, repoRoot root: URL) -> String {
        guard let rel = relativePathIfUnderRoot(file, root: root) else { return "" }
        return run(["-c", "core.quotePath=false", "diff", "--no-color", "--no-index", "--", "/dev/null", rel],
                   in: root, allowedStatuses: [1]) ?? ""
    }

    /// Per-file changed-line maps for the whole working tree versus `HEAD`, from
    /// one `git diff --unified=0 HEAD` — one process spawn instead of one
    /// ``lineChanges(for:repoRoot:)`` spawn per changed file.
    ///
    /// Keys are repository-relative paths (the new path for a rename; the old
    /// path for a deletion); each value matches what
    /// ``lineChanges(for:repoRoot:)`` returns for that file. Untracked files are
    /// absent (they're absent from `git diff`), matching the per-file call's
    /// empty result for them.
    static func lineChangesAll(repoRoot root: URL) -> [String: [Int: GitChangeKind]] {
        // core.quotePath=false keeps non-ASCII paths verbatim in the ---/+++
        // headers instead of C-style octal-escaped.
        guard let diff = run(["-c", "core.quotePath=false", "diff", "--unified=0", "--no-color", "HEAD"],
                             in: root) else { return [:] }
        var all: [String: [Int: GitChangeKind]] = [:]
        var aPath: String?, bPath: String?
        var inHunk = false   // real ---/+++ headers only appear between `diff --git` and the first @@
        func headerPath(_ s: Substring) -> String? {
            guard s != "/dev/null" else { return nil }
            let p = (s.hasPrefix("a/") || s.hasPrefix("b/")) ? s.dropFirst(2) : s
            return String(p)
        }
        for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("diff --git ") { inHunk = false; aPath = nil; bPath = nil; continue }
            if !inHunk, line.hasPrefix("--- ") { aPath = headerPath(line.dropFirst(4)); continue }
            if !inHunk, line.hasPrefix("+++ ") { bPath = headerPath(line.dropFirst(4)); continue }
            guard line.hasPrefix("@@") else { continue }
            inHunk = true
            guard let path = bPath ?? aPath, let hunk = HunkHeader.parse(line) else { continue }
            if hunk.changeKind == .deleted {
                all[path, default: [:]][max(1, hunk.newStart)] = .deleted
            } else {
                for l in hunk.newLineRange { all[path, default: [:]][l] = hunk.changeKind }
            }
        }
        return all
    }

    /// Removed (old) lines to ghost inline as phantom rows, for a Cursor-style
    /// inline diff.
    ///
    /// Parses `git diff --unified=0`. Removed lines are keyed by the 1-based
    /// new-file line they should render *above* (for a pure deletion, the line
    /// just below where the content used to be).
    ///
    /// - Returns: A map from 1-based new-file line number to the removed lines'
    ///   text, in order.
    static func removedLines(for file: URL, repoRoot root: URL) -> [Int: [String]] {
        lineDiff(for: file, repoRoot: root).removed
    }

    /// Total insertions/deletions in the working tree versus `HEAD` (staged +
    /// unstaged tracked changes), summed across all files.
    ///
    /// Parses `git diff --numstat HEAD`. Untracked files are not counted (they're
    /// absent from `git diff`); binary files contribute nothing. Returns `(0, 0)`
    /// on an unborn `HEAD` or any failure.
    static func diffStat(repoRoot root: URL) -> (insertions: Int, deletions: Int) {
        guard let out = run(["diff", "--numstat", "--no-color", "HEAD"], in: root) else { return (0, 0) }
        return parseNumstat(out)
    }

    /// Sums a `git diff --numstat` body. Each line is `<added>\t<deleted>\t<path>`;
    /// binary files report `-` in both count columns and are skipped. Pure — exposed
    /// for testing without a repo.
    static func parseNumstat(_ text: String) -> (insertions: Int, deletions: Int) {
        var insertions = 0, deletions = 0
        for line in text.split(separator: "\n") {
            let cols = line.split(separator: "\t")
            guard cols.count >= 2 else { continue }
            if let a = Int(cols[0]) { insertions += a }   // "-" (binary) → nil → skipped
            if let d = Int(cols[1]) { deletions += d }
        }
        return (insertions, deletions)
    }
}
