//
//  GitWorktree.swift
//  SwiftGitCLI
//
//  A single working tree of a repository (main or linked).
//
//  Created by David Sherlock on 7/16/26.
//

import Foundation

/// One working tree of a repository, produced by ``Git/worktrees(repoRoot:)``.
///
/// A repository always has a *main* worktree (the checkout that owns `.git/`)
/// and may have any number of *linked* worktrees created with `git worktree add`.
public struct GitWorktree: Sendable, Equatable {

    /// Absolute path to the worktree's root directory, as reported by git.
    public let path: URL

    /// The short branch name checked out in this worktree (e.g. `"main"`,
    /// with the `refs/heads/` prefix stripped), or `nil` when the worktree
    /// is on a detached `HEAD` or is a bare repository entry.
    public let branch: String?

    /// `true` for the main worktree (always listed first by git), `false`
    /// for linked worktrees.
    public let isMain: Bool

    /// Creates a worktree entry. Normally produced by ``Git/worktrees(repoRoot:)``;
    /// public for constructing fixtures in tests and previews.
    public init(path: URL, branch: String?, isMain: Bool) {
        self.path = path
        self.branch = branch
        self.isMain = isMain
    }

    /// Whether this worktree is the one containing `root`.
    ///
    /// Paths are compared canonically (symlinks resolved over the longest
    /// existing prefix), so the macOS `/private/var` ↔ `/var` symlink and
    /// similar aliases never cause a false mismatch.
    ///
    /// - Parameter root: A repository root, typically from ``Git/repoRoot(for:)``
    ///   (which reports the enclosing worktree's root when called inside one).
    public func isCurrent(relativeTo root: URL) -> Bool {
        Git.canonicalPath(path) == Git.canonicalPath(root)
    }
}
