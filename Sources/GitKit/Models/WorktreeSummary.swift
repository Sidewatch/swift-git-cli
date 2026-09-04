//
//  WorktreeSummary.swift
//  SwiftGitCLI
//
//  A worktree paired with a per-kind tally of its working-tree changes — the
//  data behind a parallel-agent review rail's cards.
//

import Foundation

/// A worktree plus a count of its working-tree changes by kind — enough to draw
/// a review card ("feature-x · 4 changed") without re-scanning. Build one per
/// worktree from that worktree's ``Git/status(repoRoot:)`` output, or get the
/// whole set from ``Git/worktreeSummaries(repoRoot:)``.
public struct WorktreeSummary: Sendable, Equatable {

    /// The worktree this summarizes.
    public let worktree: GitWorktree

    public let added: Int
    public let modified: Int
    public let deleted: Int
    public let untracked: Int
    public let renamed: Int

    /// Line insertions in the working tree vs HEAD (from ``Git/diffStat(repoRoot:)``;
    /// 0 when not gathered). Untracked files don't contribute.
    public let insertions: Int
    /// Line deletions in the working tree vs HEAD.
    public let deletions: Int

    /// Total changed entries across all kinds.
    public var changeCount: Int { added + modified + deleted + untracked + renamed }

    /// Whether the worktree has any uncommitted change worth reviewing.
    public var isDirty: Bool { changeCount > 0 }

    public init(worktree: GitWorktree, added: Int = 0, modified: Int = 0,
                deleted: Int = 0, untracked: Int = 0, renamed: Int = 0,
                insertions: Int = 0, deletions: Int = 0) {
        self.worktree = worktree
        self.added = added
        self.modified = modified
        self.deleted = deleted
        self.untracked = untracked
        self.renamed = renamed
        self.insertions = insertions
        self.deletions = deletions
    }

    /// Tallies a worktree's `git status` entries by kind. Pure — pass the status
    /// list from ``Git/status(repoRoot:)`` for `worktree.path`; `insertions`/
    /// `deletions` come from ``Git/diffStat(repoRoot:)`` (0 when not gathered).
    public static func make(worktree: GitWorktree,
                            status: [(path: String, kind: GitChangeKind)],
                            insertions: Int = 0, deletions: Int = 0) -> WorktreeSummary {
        var a = 0, m = 0, d = 0, u = 0, r = 0
        for entry in status {
            switch entry.kind {
            case .added:     a += 1
            case .modified:  m += 1
            case .deleted:   d += 1
            case .untracked: u += 1
            case .renamed:   r += 1
            }
        }
        return WorktreeSummary(worktree: worktree, added: a, modified: m,
                               deleted: d, untracked: u, renamed: r,
                               insertions: insertions, deletions: deletions)
    }
}
