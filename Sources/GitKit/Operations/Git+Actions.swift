//
//  Git+Actions.swift
//  SwiftGitCLI
//
//  Mutating actions: stage, unstage, and discard.
//
//  Created by David Sherlock on 7/9/26.
//

import Foundation

public extension Git {

    /// Stages `file` (`git add`). Returns `true` on success.
    ///
    /// Fails (returns `false`) when `file` is not located under `root`.
    @discardableResult
    static func stage(_ file: URL, repoRoot root: URL) -> Bool {
        guard let rel = relativePathIfUnderRoot(file, root: root) else { return false }
        return run(["add", "--", rel], in: root) != nil
    }

    /// Unstages `file` (`git restore --staged`). Returns `true` on success.
    ///
    /// Fails (returns `false`) when `file` is not located under `root`.
    ///
    /// - Note: Requires an existing `HEAD` (a repository with at least one commit).
    @discardableResult
    static func unstage(_ file: URL, repoRoot root: URL) -> Bool {
        guard let rel = relativePathIfUnderRoot(file, root: root) else { return false }
        return run(["restore", "--staged", "--", rel], in: root) != nil
    }

    /// Reverts `file` to `HEAD` (tracked) or deletes it (untracked). **Destructive.**
    ///
    /// Fails (returns `false`) when a tracked `file` is not located under `root` —
    /// never falls back to a bare-filename pathspec that could clobber an
    /// unrelated same-named file at the repository root.
    ///
    /// - Parameter kind: The file's change kind. `.untracked` files are removed
    ///   from disk; `.added` files (staged-new, absent from `HEAD`) are removed
    ///   from the index and disk; `.renamed` files come back under their old
    ///   name with the new name removed; all others are restored from `HEAD`,
    ///   discarding local edits.
    /// - Returns: `true` on success.
    @discardableResult
    static func discard(_ file: URL, kind: GitChangeKind, repoRoot root: URL) -> Bool {
        if kind == .untracked { return (try? FileManager.default.removeItem(at: file)) != nil }
        guard let rel = relativePathIfUnderRoot(file, root: root) else { return false }
        // `checkout HEAD -- <path>` requires the pathspec to exist in HEAD, which a
        // staged-new file and a rename's NEW path (the path status reports) never
        // do — git exits 1 with "pathspec did not match". `restore --source=HEAD
        // --staged --worktree` reverts every kind uniformly: paths in HEAD are
        // restored, paths absent from HEAD are removed from the index and disk.
        // A rename needs BOTH paths so the old file comes back too.
        var paths = [rel]
        if kind == .renamed, let old = renameSource(of: rel, repoRoot: root) { paths.insert(old, at: 0) }
        return run(["restore", "--source=HEAD", "--staged", "--worktree", "--"] + paths, in: root) != nil
    }

    /// The pre-rename (old) path of the staged rename/copy whose new path is
    /// `rel`, from `git status --porcelain=v1 -z` (the old path is the entry's
    /// extra NUL-terminated field, which ``status(repoRoot:)`` skips).
    private static func renameSource(of rel: String, repoRoot root: URL) -> String? {
        guard let out = run(["status", "--porcelain=v1", "-z"], in: root) else { return nil }
        let fields = out.split(separator: "\0", omittingEmptySubsequences: true)
        var i = 0
        while i < fields.count {
            let entry = String(fields[i])
            i += 1
            guard entry.count >= 4 else { continue }
            let code = entry.prefix(2)
            guard code.contains("R") || code.contains("C") else { continue }
            let newPath = String(entry.dropFirst(3))
            guard i < fields.count else { return nil }
            let old = String(fields[i])
            i += 1
            if newPath == rel { return old }
        }
        return nil
    }
}
