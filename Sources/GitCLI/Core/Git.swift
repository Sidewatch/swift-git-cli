//
//  Git.swift
//  SwiftGitCLI
//
//  The `Git` namespace and its low-level process/path primitives.
//
//  Created by David Sherlock on 7/9/26.
//

import Foundation

/// A thin wrapper over the `git` command-line tool.
///
/// `Git` is a namespace (a caseless `enum`) — you never instantiate it; call the
/// static methods directly:
///
/// ```swift
/// import GitCLI
///
/// guard let root = Git.repoRoot(for: someFileURL) else { return }
/// for change in Git.status(repoRoot: root) {
///     print(change.path, change.kind)
/// }
/// ```
///
/// Every call shells out to ``executable`` synchronously and is cheap. When
/// scanning a whole repository, run these off the main queue.
///
/// The operations are grouped across the package:
/// - Status: ``status(repoRoot:)``
/// - Diff: ``lineChanges(for:repoRoot:)``, ``removedLines(for:repoRoot:)``
/// - Blame: ``blame(for:line:repoRoot:)``
/// - Actions: ``stage(_:repoRoot:)``, ``unstage(_:repoRoot:)``, ``discard(_:kind:repoRoot:)``
/// - Worktrees: ``currentBranch(repoRoot:)``, ``worktrees(repoRoot:)``
///
/// - Note: This wraps the `git` executable rather than linking libgit2, so a
///   working `git` must be installed at ``executable``.
public enum Git {

    /// Absolute path to the `git` executable used for every invocation.
    ///
    /// Defaults to the system git at `/usr/bin/git` (the Command Line Tools shim
    /// on macOS). Point it elsewhere before making calls to use a different git.
    public static var executable = "/usr/bin/git"

    /// Runs `git <args>` in `dir` and returns standard output.
    ///
    /// - Parameters:
    ///   - args: Arguments passed to `git`, e.g. `["status", "--porcelain=v1"]`.
    ///   - dir: Working directory the command runs in.
    /// - Returns: The command's standard output decoded as UTF-8, or `nil` if the
    ///   process failed to launch or exited with a non-zero status.
    public static func run(_ args: [String], in dir: URL) -> String? {
        run(args, in: dir, allowedStatuses: [])
    }

    /// Runs `git <args>` like ``run(_:in:)`` but also treats the exit statuses in
    /// `allowedStatuses` as success.
    ///
    /// Some git subcommands use a non-zero exit to report a *result*, not a
    /// failure — `git diff --no-index` exits 1 when the inputs differ, which is
    /// its normal "found a difference" outcome.
    ///
    /// - Parameters:
    ///   - args: Arguments passed to `git`.
    ///   - dir: Working directory the command runs in.
    ///   - allowedStatuses: Non-zero exit statuses to accept alongside 0.
    /// - Returns: The command's standard output decoded as UTF-8, or `nil` if the
    ///   process failed to launch or exited with a status outside the allowed set.
    public static func run(_ args: [String], in dir: URL, allowedStatuses: Set<Int32>) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        p.currentDirectoryURL = dir
        let out = Pipe()
        p.standardOutput = out
        // Discard stderr outright. Attaching a Pipe that is never drained deadlocks
        // once git writes ~64KB of warnings: the child blocks in write(2) on stderr
        // while we block reading stdout to EOF, and neither ever progresses.
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 || allowedStatuses.contains(p.terminationStatus) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Runs `git <args>` like ``run(_:in:allowedStatuses:)`` with extra environment variables
    /// layered over the process environment.
    ///
    /// Needed for the plumbing commands that are steered by the environment rather than by
    /// flags — chiefly `GIT_INDEX_FILE`, which lets ``createCheckpoint(repoRoot:)`` stage the
    /// working tree into a scratch index without disturbing the real one.
    ///
    /// - Parameters:
    ///   - args: Arguments passed to `git`.
    ///   - dir: Working directory the command runs in.
    ///   - environment: Variables layered over (and overriding) the inherited environment.
    ///   - allowedStatuses: Non-zero exit statuses to accept alongside 0.
    /// - Returns: The command's standard output decoded as UTF-8, or `nil` on failure.
    public static func run(_ args: [String], in dir: URL,
                           environment: [String: String],
                           allowedStatuses: Set<Int32> = []) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        p.currentDirectoryURL = dir
        p.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        let out = Pipe()
        p.standardOutput = out
        // Same stderr contract as `run(_:in:allowedStatuses:)` — see the note there.
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 || allowedStatuses.contains(p.terminationStatus) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The repository root containing `dir`, or `nil` if `dir` is not inside a git repo.
    ///
    /// - Parameter dir: A file or directory URL. If a file is passed, its parent
    ///   directory is searched.
    public static func repoRoot(for dir: URL) -> URL? {
        let base = dir.hasDirectoryPath ? dir : dir.deletingLastPathComponent()
        guard let out = run(["rev-parse", "--show-toplevel"], in: base)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !out.isEmpty else { return nil }
        return URL(fileURLWithPath: out)
    }

    /// The path of `file` relative to the repository `root`.
    ///
    /// Falls back to the file's last path component when `file` is not located
    /// under `root`. Mutating operations (stage/unstage/discard) never use the
    /// fallback — they refuse to act on files outside `root` instead of guessing
    /// a pathspec (see ``relativePathIfUnderRoot(_:root:)``).
    public static func relativePath(_ file: URL, root: URL) -> String {
        relativePathIfUnderRoot(file, root: root) ?? file.lastPathComponent
    }

    /// The path of `file` relative to `root`, or `nil` when `file` is not under `root`.
    ///
    /// Compares standardized paths first (cheap, no disk I/O), then fully
    /// canonicalized paths. Standardization/symlink resolution only reconciles
    /// the macOS `/private/var` ↔ `/var` symlink for paths that exist on disk,
    /// so a *deleted* file expressed via the unresolved form would otherwise
    /// fail the prefix check — see ``canonicalPath(_:)``.
    ///
    /// Use this (not ``relativePath(_:root:)``) whenever a path may originate
    /// outside the repo — e.g. an agent's absolute edit path — so an out-of-root
    /// file is refused rather than collapsed to a bare basename that could match
    /// an unrelated same-named file inside the repo.
    public static func relativePathIfUnderRoot(_ file: URL, root: URL) -> String? {
        func relative(_ f: String, _ r: String) -> String? {
            f.hasPrefix(r + "/") ? String(f.dropFirst(r.count + 1)) : nil
        }
        if let rel = relative(file.standardizedFileURL.path, root.standardizedFileURL.path) {
            return rel
        }
        return relative(canonicalPath(file), canonicalPath(root))
    }

    /// Canonicalizes `url` even when it no longer exists on disk: resolves
    /// symlinks over the longest existing prefix (which strips macOS's
    /// `/private` designator), then re-appends the nonexistent tail verbatim.
    static func canonicalPath(_ url: URL) -> String {
        var existing = url.standardizedFileURL
        var tail: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" {
            tail.append(existing.lastPathComponent)
            existing = existing.deletingLastPathComponent()
        }
        var resolved = existing.resolvingSymlinksInPath()
        for component in tail.reversed() { resolved.appendPathComponent(component) }
        return resolved.path
    }
}
