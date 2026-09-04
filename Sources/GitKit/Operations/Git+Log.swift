//
//  Git+Log.swift
//  SwiftGitCLI
//
//  Commit history for the History panel.
//

import Foundation

/// One commit from `git log`.
public struct GitCommit: Equatable, Sendable {
    public let hash: String        // full 40-char SHA
    public let shortHash: String   // abbreviated SHA
    public let author: String
    public let date: String        // YYYY-MM-DD (author date)
    public let subject: String     // first line of the message

    public init(hash: String, shortHash: String, author: String, date: String, subject: String) {
        self.hash = hash; self.shortHash = shortHash; self.author = author
        self.date = date; self.subject = subject
    }
}

public extension Git {

    /// The most recent commits on the current branch, newest first.
    ///
    /// Uses a `%x1f` (unit-separator) delimited pretty-format so commit subjects with any
    /// punctuation parse cleanly. Records are newline-separated.
    ///
    /// - Parameters:
    ///   - root: The repository root (see ``repoRoot(for:)``).
    ///   - limit: Maximum commits to return.
    static func log(repoRoot root: URL, limit: Int = 300) -> [GitCommit] {
        guard let out = run(["log", "-n", "\(max(1, limit))", "--date=short",
                             "--pretty=format:\(Self.commitFormat)"], in: root) else { return [] }
        return parseCommits(out)
    }

    /// Commit history touching `path` (repository-relative), newest first — the History of
    /// a single file. Follows across renames.
    static func fileLog(path: String, repoRoot root: URL, limit: Int = 100) -> [GitCommit] {
        guard let out = run(["log", "-n", "\(max(1, limit))", "--date=short", "--follow",
                             "--pretty=format:\(Self.commitFormat)", "--", path], in: root) else { return [] }
        return parseCommits(out)
    }

    /// The full patch for one commit (`git show`), for the History detail view. `nil` on error.
    static func showCommit(_ hash: String, repoRoot root: URL) -> String? {
        run(["show", "--no-color", "--stat", "--patch", hash], in: root)
    }

    /// A file's content at `revision` (`git show <rev>:<path>`), for viewing a past version
    /// or building an arbitrary-revision diff. `nil` if the path didn't exist there.
    static func showFile(revision: String, path: String, repoRoot root: URL) -> String? {
        run(["show", "\(revision):\(path)"], in: root)
    }

    /// The unit-separator pretty-format shared by ``log`` and ``fileLog``.
    private static var commitFormat: String { "%H%x1f%h%x1f%an%x1f%ad%x1f%s" }

    /// Parses newline-separated `commitFormat` records into ``GitCommit``s.
    private static func parseCommits(_ out: String) -> [GitCommit] {
        out.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let f = line.components(separatedBy: "\u{1f}")
            guard f.count == 5 else { return nil }
            return GitCommit(hash: f[0], shortHash: f[1], author: f[2], date: f[3], subject: f[4])
        }
    }
}
