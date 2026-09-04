//
//  Git+Info.swift
//  SwiftGitCLI
//
//  Branch, upstream, and remote information for a repository.
//

import Foundation

public extension Git {

    // `currentBranch(repoRoot:)` lives in Git+Worktree.

    /// Local branches, each flagged if it's the checked-out one. `%(HEAD)` is a single
    /// leading char — `*` for the current branch, a space otherwise. (ref-filter format
    /// has no `%x1f` escape, unlike log's pretty-format, so the prefix char is the marker.)
    static func localBranches(repoRoot root: URL) -> [(name: String, isCurrent: Bool)] {
        guard let out = run(["branch", "--format=%(HEAD)%(refname:short)"], in: root) else { return [] }
        return out.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let s = String(line)
            guard let marker = s.first else { return nil }
            let name = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : (name, marker == "*")
        }
    }

    /// Commits `HEAD` is ahead of / behind `ref` (default the upstream, `@{u}`). Returns
    /// `(0, 0)` when there's no upstream or the ref is unknown.
    static func aheadBehind(repoRoot root: URL, ref: String = "@{u}") -> (ahead: Int, behind: Int) {
        guard let out = run(["rev-list", "--left-right", "--count", "HEAD...\(ref)"], in: root) else { return (0, 0) }
        let parts = out.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count == 2, let ahead = Int(parts[0]), let behind = Int(parts[1]) else { return (0, 0) }
        return (ahead, behind)
    }

    /// The fetch URL of `remote` (default `origin`), or nil if it isn't configured.
    static func remoteURL(repoRoot root: URL, remote: String = "origin") -> String? {
        run(["remote", "get-url", remote], in: root)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when the working tree AND index are clean (nothing to commit).
    static func isClean(repoRoot root: URL) -> Bool {
        (run(["status", "--porcelain"], in: root) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Write / network (off-main; git's stderr is discarded, so these report only success)

    /// Fetches refs from `remote` (default `origin`). Network-bound — call off the main thread.
    @discardableResult
    static func fetch(repoRoot root: URL, remote: String = "origin") -> Bool {
        run(["fetch", remote], in: root) != nil
    }

    /// Switches the working tree to `branch`. Returns whether it succeeded.
    @discardableResult
    static func checkout(_ branch: String, repoRoot root: URL) -> Bool {
        run(["checkout", branch], in: root) != nil
    }
}
