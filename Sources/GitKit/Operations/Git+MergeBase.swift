//
//  Git+MergeBase.swift
//  SwiftGitCLI
//
//  Where the current branch left its base — the anchor for "everything this branch changed".
//
//  Created by David Sherlock on 7/25/26.
//

import Foundation

public extension Git {

    /// The commit where the current branch diverged from `base`.
    ///
    /// - Parameters:
    ///   - base: The ref to compare against.
    ///   - repoRoot: The repository.
    /// - Returns: The merge-base commit, or `nil` when the refs share no history.
    static func mergeBase(with base: String, repoRoot: URL) -> String? {
        guard let out = run(["merge-base", "HEAD", base], in: repoRoot)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !out.isEmpty else { return nil }
        return out
    }

    /// The commit the current branch forked from its integration branch.
    ///
    /// The integration branch is resolved by trying, in order: the remote's own default
    /// (`origin/HEAD`, which is what the remote says it is), then `main`, then `master`. That
    /// order matters — a repo can carry a stale local `main` alongside a remote default of
    /// something else, and the remote is the more trustworthy answer.
    ///
    /// - Parameter repoRoot: The repository.
    /// - Returns: The fork point, or `nil` when no candidate branch exists (a repo with only
    ///   one branch, or one named something else entirely).
    static func defaultBranchMergeBase(repoRoot: URL) -> String? {
        for candidate in ["origin/HEAD", "main", "master"] {
            // Skip a candidate that doesn't resolve, or merge-base would report the failure
            // as "no shared history" and stop the search early.
            guard run(["rev-parse", "--verify", "--quiet", candidate], in: repoRoot) != nil,
                  let base = mergeBase(with: candidate, repoRoot: repoRoot) else { continue }
            // On the integration branch itself the merge-base is HEAD, so the branch scope
            // would show nothing. That's the honest answer — there is no branch work yet.
            return base
        }
        return nil
    }
}
