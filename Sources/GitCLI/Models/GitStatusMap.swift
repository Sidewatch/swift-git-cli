//
//  GitStatusMap.swift
//  SwiftGitCLI
//
//  A snapshot of `git status` shaped for O(1) per-path lookups.
//

import Foundation

/// A snapshot of `git status` shaped for O(1) per-row lookups by a file tree or a
/// tab bar: absolute file path → change kind, plus the set of every ancestor
/// directory of a changed file (so a collapsed folder can show a "contains
/// changes" dot).
///
/// Deleted files are excluded — they have no row in a tree and no tab worth
/// tinting; they belong in a Changes list.
///
/// Build it off-main from ``Git/status(repoRoot:)`` output. Keys are inserted
/// under every alias of the repo root (standardized, symlink-resolved, and
/// `/private`-prefixed) so the macOS `/private/var` ↔ `/var` aliasing never
/// makes a lookup miss — the same gotcha GitCLI's canonical-path handling
/// reconciles elsewhere.
public struct GitStatusMap: Equatable, Sendable {

    public static let empty = GitStatusMap(kinds: [:], changedDirs: [])

    /// Absolute file path → change kind (no `.deleted` entries).
    private let kinds: [String: GitChangeKind]
    /// Absolute path of every directory containing (at any depth) a changed file.
    private let changedDirs: Set<String>

    init(kinds: [String: GitChangeKind], changedDirs: Set<String>) {
        self.kinds = kinds
        self.changedDirs = changedDirs
    }

    /// The change kind for a file URL, or nil when the file is unchanged.
    public func kind(for url: URL) -> GitChangeKind? {
        kinds.isEmpty ? nil : kinds[url.standardizedFileURL.path]
    }

    /// Absolute paths of every changed file — the "search the agent's changes"
    /// scope. Sorted so consumers get a stable order.
    public var changedFilePaths: [String] { kinds.keys.sorted() }

    /// Whether the directory at `url` contains (at any depth) a changed file.
    public func directoryContainsChanges(_ url: URL) -> Bool {
        !changedDirs.isEmpty && changedDirs.contains(url.standardizedFileURL.path)
    }

    /// Builds the lookup from repo-relative `git status` paths. Runs off-main
    /// (touches disk to resolve the repo root's symlink aliases, once per build).
    public static func build(status: [(path: String, kind: GitChangeKind)], repoRoot: URL) -> GitStatusMap {
        let live = status.filter { $0.kind != .deleted }
        guard !live.isEmpty else { return .empty }

        // Every alias the repo root may appear under in row/tab URLs: as given
        // (standardized), symlink-resolved (strips macOS's /private designator),
        // and explicitly /private-prefixed (adds it back) — so a lookup keyed via
        // either side of the /private/var ↔ /var symlink hits.
        var roots: Set<String> = [repoRoot.standardizedFileURL.path]
        roots.insert((repoRoot.standardizedFileURL.path as NSString).resolvingSymlinksInPath)
        for r in Array(roots) where !r.hasPrefix("/private/") {
            let aliased = "/private" + r
            if FileManager.default.fileExists(atPath: aliased) { roots.insert(aliased) }
        }

        var kinds: [String: GitChangeKind] = [:]
        var dirs: Set<String> = []
        for entry in live {
            // Defensive: without `-uall`, `git status` collapses an untracked
            // directory to a single trailing-slash entry ("?? NewFeature/").
            // GitCLI passes -uall, but handle the directory form anyway so older
            // cached outputs still decorate the folder + its ancestors (a
            // trailing-slash key could never match a lookup path, and
            // `deletingLastPathComponent` on "NewFeature/" returns "" — the entry
            // used to vanish entirely).
            let isDirEntry = entry.path.hasSuffix("/")
            let path = isDirEntry ? String(entry.path.dropLast()) : entry.path
            guard !path.isEmpty else { continue }
            for root in roots {
                if isDirEntry {
                    dirs.insert(root + "/" + path)   // the untracked folder itself gets a dot
                } else {
                    kinds[root + "/" + path] = entry.kind
                }
                var dir = (path as NSString).deletingLastPathComponent
                while !dir.isEmpty {
                    dirs.insert(root + "/" + dir)
                    dir = (dir as NSString).deletingLastPathComponent
                }
                dirs.insert(root)   // the root folder itself contains changes
            }
        }
        return GitStatusMap(kinds: kinds, changedDirs: dirs)
    }
}
