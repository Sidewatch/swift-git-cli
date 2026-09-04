//
//  Git+Status.swift
//  SwiftGitCLI
//
//  Working-tree status of changed files.
//
//  Created by David Sherlock on 7/9/26.
//

import Foundation

public extension Git {

    /// Working-tree changes versus `HEAD`, one entry per changed file.
    ///
    /// Parses `git status --porcelain=v1 -z -uall`. The `-z` (NUL-delimited)
    /// format emits pathnames verbatim — no C-style quoting for spaces, quotes,
    /// backslashes, or non-ASCII characters — so paths match the disk exactly.
    /// `-uall` lists every untracked file individually — without it, git
    /// collapses a brand-new untracked directory to a single trailing-slash
    /// entry (`?? NewFeature/`), hiding the files inside it from callers that
    /// decorate per file. For renames/copies, `path` is the new path (the old
    /// path arrives as a separate NUL-terminated field and is skipped).
    ///
    /// - Parameter root: The repository root (see ``repoRoot(for:)``).
    /// - Returns: `(path, kind)` pairs, where `path` is repository-relative.
    static func status(repoRoot root: URL) -> [(path: String, kind: GitChangeKind)] {
        guard let out = run(["status", "--porcelain=v1", "-z", "-uall"], in: root) else { return [] }
        var result: [(String, GitChangeKind)] = []
        let fields = out.split(separator: "\0", omittingEmptySubsequences: true)
        var i = 0
        while i < fields.count {
            let entry = String(fields[i])
            i += 1
            guard entry.count >= 4 else { continue }
            let code = String(entry.prefix(2))
            let path = String(entry.dropFirst(3))
            // Rename/copy entries carry the OLD path as the next NUL field — skip it.
            if code.contains("R") || code.contains("C") { i += 1 }
            let kind: GitChangeKind
            if code.contains("?") { kind = .untracked }
            else if code.contains("A") { kind = .added }
            else if code.contains("D") { kind = .deleted }
            else if code.contains("R") { kind = .renamed }
            else { kind = .modified }
            result.append((path, kind))
        }
        return result
    }
}
