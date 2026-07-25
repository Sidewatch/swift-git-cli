//
//  Git+Checkpoint.swift
//  SwiftGitCLI
//
//  Non-destructive snapshots of the working tree, so a range of edits can be diffed exactly
//  rather than inferred.
//
//  Created by David Sherlock on 7/25/26.
//

import Foundation

public extension Git {

    /// The ref namespace checkpoints are anchored under.
    ///
    /// Namespaced away from `refs/heads` and `refs/tags` so checkpoints never appear in
    /// `git branch`, `git tag`, or a branch picker — they are Sidewatch bookkeeping, invisible
    /// to normal use of the repo.
    static var checkpointRefPrefix: String { "refs/sidewatch/checkpoints/" }

    /// Captures the entire working tree — modifications, new files, and deletions — as a
    /// dangling commit, **without touching the working tree, the index, or the stash list**.
    ///
    /// The commit is built through a scratch index: `git add -A` into a `GIT_INDEX_FILE`
    /// outside the repo, `git write-tree`, then `git commit-tree` parented on `HEAD`. Two of
    /// these bracketing a range of edits make `git diff <a> <b>` an exact answer to "what
    /// changed in between", where reading the working tree can only ever approximate it.
    ///
    /// The scratch index lives outside the repository deliberately: inside, `git add -A` sweeps
    /// up the index's own `.lock` file and commits it.
    ///
    /// `.gitignore` is respected, so build output never lands in a checkpoint.
    ///
    /// - Important: The returned commit is unreferenced and therefore eligible for garbage
    ///   collection. Pass it to ``anchorCheckpoint(_:id:repoRoot:)`` to keep it alive.
    ///
    /// - Parameter repoRoot: The repository to snapshot.
    /// - Returns: The commit SHA, or `nil` if any step failed.
    static func createCheckpoint(repoRoot: URL) -> String? {
        let indexPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("sidewatch-checkpoint-index-\(UUID().uuidString)").path
        defer {
            try? FileManager.default.removeItem(atPath: indexPath)
            try? FileManager.default.removeItem(atPath: indexPath + ".lock")
        }
        let env = ["GIT_INDEX_FILE": indexPath]

        // Seed from HEAD first. `git add -A` into an EMPTY index skips a tracked-but-ignored
        // file (one committed before its path was added to .gitignore — .vscode/settings.json,
        // a checked-in dist/), because add only re-adds an ignored path already in the index.
        // Without this the file is missing from every checkpoint tree, so it shows as a phantom
        // deletion against any real commit and a turn's edits to it are invisible.
        // A repo with no commits has no HEAD; there is nothing to seed from, which is correct.
        _ = run(["read-tree", "HEAD"], in: repoRoot, environment: env)
        guard run(["add", "-A"], in: repoRoot, environment: env) != nil,
              let tree = trimmed(run(["write-tree"], in: repoRoot, environment: env))
        else { return nil }

        // An identity is required to write a commit object, and the repo may not configure one
        // (or may configure one we shouldn't borrow). These -c flags apply to this call only.
        var args = ["-c", "user.name=Sidewatch", "-c", "user.email=checkpoint@sidewatch.local",
                    "commit-tree", tree, "-m", "sidewatch checkpoint"]
        // Parent on HEAD when there is one — a repository with no commits yet has none, and
        // passing `-p` with an empty value fails outright.
        if let head = trimmed(run(["rev-parse", "HEAD"], in: repoRoot)) { args += ["-p", head] }
        return trimmed(run(args, in: repoRoot))
    }

    /// Anchors a checkpoint commit under ``checkpointRefPrefix`` so it survives garbage
    /// collection.
    ///
    /// Without a ref, the commit from ``createCheckpoint(repoRoot:)`` is unreachable and a
    /// `git gc` — which git runs on its own schedule — will prune it, silently turning a
    /// reviewable turn into a dangling SHA.
    ///
    /// - Parameters:
    ///   - commit: The checkpoint commit SHA.
    ///   - id: The checkpoint's identifier, used as the ref's last path component.
    ///   - repoRoot: The repository holding the commit.
    /// - Returns: `true` when the ref was written.
    @discardableResult
    static func anchorCheckpoint(_ commit: String, id: String, repoRoot: URL) -> Bool {
        guard let id = sanitizedCheckpointID(id) else { return false }
        return run(["update-ref", checkpointRefPrefix + id, commit], in: repoRoot) != nil
    }

    /// Drops a checkpoint's anchor, making its commit collectable again.
    ///
    /// - Parameters:
    ///   - id: The checkpoint identifier passed to ``anchorCheckpoint(_:id:repoRoot:)``.
    ///   - repoRoot: The repository holding the ref.
    /// - Returns: `true` when the ref was removed.
    @discardableResult
    static func removeCheckpoint(id: String, repoRoot: URL) -> Bool {
        guard let id = sanitizedCheckpointID(id) else { return false }
        return run(["update-ref", "-d", checkpointRefPrefix + id], in: repoRoot) != nil
    }

    /// Every anchored checkpoint, oldest ref first.
    ///
    /// - Parameter repoRoot: The repository to list.
    /// - Returns: Pairs of checkpoint id and commit SHA.
    static func checkpoints(repoRoot: URL) -> [(id: String, commit: String)] {
        guard let out = run(["for-each-ref", "--format=%(refname)%09%(objectname)", checkpointRefPrefix],
                            in: repoRoot) else { return [] }
        return out.split(separator: "\n").compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count == 2, parts[0].hasPrefix(checkpointRefPrefix) else { return nil }
            return (String(parts[0].dropFirst(checkpointRefPrefix.count)), parts[1])
        }
    }

    /// The unified diff between two checkpoints, optionally narrowed to one path.
    ///
    /// - Parameters:
    ///   - from: The earlier checkpoint commit (or any commit-ish).
    ///   - to: The later checkpoint commit, or `nil` to diff against the **live working tree** —
    ///     which is what the turn currently in progress needs, having no closing snapshot yet.
    ///   - path: A repo-relative path to narrow to, or `nil` for every change.
    ///   - repoRoot: The repository to diff in.
    /// - Returns: The unified diff, empty when nothing changed, or `nil` on failure.
    static func checkpointDiff(from: String, to: String?, path: String? = nil, repoRoot: URL) -> String? {
        // Working-tree comparison: diff directly and splice in untracked files, rather than
        // snapshotting. Building an ephemeral checkpoint here re-hashed the ENTIRE working tree
        // and wrote an unreferenced tree+commit into .git/objects on every git tick that a
        // still-open turn tab refreshed on.
        guard let target = to else {
            var diff = run(["-c", "core.quotePath=false", "diff", "--no-color", from], in: repoRoot) ?? ""
            let untracked = run(["-c", "core.quotePath=false", "ls-files", "--others",
                                 "--exclude-standard", "-z"], in: repoRoot) ?? ""
            for file in untracked.split(separator: "\0").map(String.init) {
                if let path, file != path { continue }
                diff += untrackedDiff(for: repoRoot.appendingPathComponent(file), repoRoot: repoRoot)
            }
            return diff
        }
        var args = ["-c", "core.quotePath=false", "diff", from, target]
        if let path { args += ["--", path] }
        return run(args, in: repoRoot)
    }

    /// The files that changed between two checkpoints.
    ///
    /// This is the exact answer to "what did this turn touch", where walking the transcript
    /// only reports what the agent *said* it touched.
    ///
    /// - Parameters:
    ///   - from: The earlier checkpoint commit.
    ///   - to: The later checkpoint commit, or `nil` to compare against the live working tree.
    ///   - repoRoot: The repository to diff in.
    /// - Returns: Repo-relative paths with their change kind, in git's order.
    static func checkpointChangedFiles(from: String, to: String?,
                                       repoRoot: URL) -> [(path: String, kind: GitChangeKind)] {
        // Same reasoning as `checkpointDiff`: compare against the working tree directly and add
        // untracked files, instead of hashing the whole tree into a throwaway commit.
        guard let target = to else {
            var files = changedFiles(rawNameStatus: run(["-c", "core.quotePath=false", "diff",
                                                         "--name-status", from], in: repoRoot))
            let untracked = run(["-c", "core.quotePath=false", "ls-files", "--others",
                                 "--exclude-standard", "-z"], in: repoRoot) ?? ""
            files += untracked.split(separator: "\0").map { (path: String($0), kind: GitChangeKind.added) }
            return files
        }
        // core.quotePath=false: without it a path with non-ASCII characters comes back C-quoted
        // ("\303\251"), which no caller can open.
        return changedFiles(rawNameStatus: run(["-c", "core.quotePath=false", "diff",
                                                "--name-status", from, target], in: repoRoot))
    }

    /// Parses `git diff --name-status` output.
    private static func changedFiles(rawNameStatus: String?) -> [(path: String, kind: GitChangeKind)] {
        guard let out = rawNameStatus else { return [] }
        return out.split(separator: "\n").compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 2, let status = parts[0].first else { return nil }
            // A rename reports `R<score>\told\tnew` — the new path is what a reviewer opens.
            let path = parts.count >= 3 ? parts[2] : parts[1]
            let kind: GitChangeKind
            switch status {
            case "A": kind = .added
            case "D": kind = .deleted
            case "R": kind = .renamed
            default:  kind = .modified
            }
            return (path, kind)
        }
    }

    /// Drops the oldest anchors, keeping the `keeping` newest by commit time.
    ///
    /// Checkpoints accumulate one per agent turn, and each pins a whole tree; without pruning
    /// a long-running repo would keep every tree it ever saw alive.
    ///
    /// - Parameters:
    ///   - keeping: How many checkpoints to retain. Values below zero are treated as zero.
    ///   - repoRoot: The repository to prune.
    /// - Returns: The ids that were dropped.
    @discardableResult
    static func pruneCheckpoints(keeping: Int, repoRoot: URL) -> [String] {
        // Newest first, so everything past the keep count is the tail to drop.
        guard let out = run(["for-each-ref", "--sort=-committerdate", "--format=%(refname)",
                             checkpointRefPrefix], in: repoRoot) else { return [] }
        let refs = out.split(separator: "\n").map(String.init)
        let doomed = refs.dropFirst(max(0, keeping))
        var dropped: [String] = []
        for ref in doomed where run(["update-ref", "-d", ref], in: repoRoot) != nil {
            dropped.append(String(ref.dropFirst(checkpointRefPrefix.count)))
        }
        return dropped
    }

    /// `out` stripped of surrounding whitespace, or `nil` when it is absent or empty.
    private static func trimmed(_ out: String?) -> String? {
        guard let s = out?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    /// `id` reduced to characters that are safe in a ref name, or `nil` when nothing survives.
    ///
    /// Ids reach here from transcript-derived turn identifiers, so they are not trusted to be
    /// ref-safe: git rejects a ref containing a space, `~`, `^`, `:`, `?`, `*`, `[`, `\`, or a
    /// `..` sequence, and a crafted one could otherwise escape the namespace entirely.
    private static func sanitizedCheckpointID(_ id: String) -> String? {
        let safe = id.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "-" }
        let joined = String(safe).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return joined.isEmpty ? nil : joined
    }
}
