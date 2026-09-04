//
//  Git+Worktree.swift
//  SwiftGitCLI
//
//  Branch identity and worktree enumeration.
//
//  Created by David Sherlock on 7/16/26.
//

import Foundation

public extension Git {

    /// The short name of the branch currently checked out at `root`.
    ///
    /// Runs `git rev-parse --abbrev-ref HEAD`. On a detached `HEAD` (where
    /// git reports the literal name `"HEAD"`) this falls back to the short
    /// commit SHA via `git rev-parse --short HEAD`, so the result is always
    /// something meaningful to display.
    ///
    /// - Parameter root: The repository root (see ``repoRoot(for:)``).
    /// - Returns: The branch name, the short SHA when detached, or `nil` when
    ///   git fails (e.g. an unborn `HEAD` in a repository with no commits).
    static func currentBranch(repoRoot root: URL) -> String? {
        guard let name = run(["rev-parse", "--abbrev-ref", "HEAD"], in: root)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        guard name == "HEAD" else { return name }
        // Detached HEAD — identify the checkout by its short commit SHA instead.
        guard let sha = run(["rev-parse", "--short", "HEAD"], in: root)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !sha.isEmpty else { return nil }
        return sha
    }

    /// All worktrees of the repository containing `root`, main worktree first.
    ///
    /// Parses `git worktree list --porcelain`, whose blank-line-separated
    /// entries carry `worktree <path>` plus optional `HEAD <sha>`,
    /// `branch refs/heads/<name>`, `detached`, and `bare` attribute lines.
    /// Branch refs have their `refs/heads/` prefix stripped; detached and
    /// bare entries surface with a `nil` branch. Git always lists the main
    /// worktree first, which is what ``GitWorktree/isMain`` reflects.
    ///
    /// - Parameter root: Any worktree's root (main or linked); the full set
    ///   is returned regardless of which worktree the call runs in.
    /// - Returns: One ``GitWorktree`` per working tree, or `[]` on failure.
    static func worktrees(repoRoot root: URL) -> [GitWorktree] {
        guard let out = run(["worktree", "list", "--porcelain"], in: root) else { return [] }
        var result: [GitWorktree] = []
        var path: URL?
        var branch: String?
        func flush() {
            if let path {
                result.append(GitWorktree(path: path, branch: branch, isMain: result.isEmpty))
            }
            path = nil
            branch = nil
        }
        for line in out.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty {   // blank line terminates an entry
                flush()
            } else if line.hasPrefix("worktree ") {
                path = URL(fileURLWithPath: String(line.dropFirst("worktree ".count)),
                           isDirectory: true)
            } else if line.hasPrefix("branch ") {
                let ref = String(line.dropFirst("branch ".count))
                branch = ref.hasPrefix("refs/heads/")
                    ? String(ref.dropFirst("refs/heads/".count))
                    : ref
            }
            // "HEAD", "detached", "bare", "locked", "prunable" need no handling:
            // detached/bare entries simply never receive a `branch` line.
        }
        flush()   // porcelain output may or may not end with a trailing blank line
        return result
    }

    /// Every worktree of the repository containing `root`, each paired with a
    /// per-kind tally of its uncommitted changes — the data for a parallel-agent
    /// review rail.
    ///
    /// Runs one `git status` per worktree (against that worktree's own path), so
    /// the cost scales with the number of worktrees. Call off-main.
    ///
    /// - Parameter root: Any worktree's root; the full set is summarized.
    /// - Returns: One ``WorktreeSummary`` per worktree, main first, or `[]` on failure.
    static func worktreeSummaries(repoRoot root: URL) -> [WorktreeSummary] {
        worktrees(repoRoot: root).map {
            let stat = diffStat(repoRoot: $0.path)
            return WorktreeSummary.make(worktree: $0, status: status(repoRoot: $0.path),
                                        insertions: stat.insertions, deletions: stat.deletions)
        }
    }

    /// Removes a linked worktree (`git worktree remove`). **Destructive** — it
    /// deletes the worktree's directory. A plain call refuses (returns `false`)
    /// when the worktree has uncommitted changes, submodules, **or is locked**;
    /// git also refuses to remove the main worktree.
    ///
    /// - Parameters:
    ///   - worktree: the linked worktree's path (from ``GitWorktree/path``).
    ///   - root: any worktree's root (the command locates the shared repo).
    ///   - force: when `true`, passes `--force --force`, which overrides *both* a
    ///     dirty tree and a lock (git requires the doubled flag to override a
    ///     lock). Discards uncommitted changes.
    /// - Returns: `true` on success.
    @discardableResult
    static func removeWorktree(_ worktree: URL, repoRoot root: URL, force: Bool = false) -> Bool {
        var args = ["worktree", "remove"]
        if force { args.append("--force"); args.append("--force") }   // -f -f overrides a lock too
        args.append(worktree.path)
        return run(args, in: root) != nil
    }
}
