//
//  GitHubCLI.swift
//  GitKit
//
//  Thin, best-effort wrapper around the GitHub CLI (`gh`).
//
//  Created by David Sherlock on 9/5/26.
//

import Foundation
import ProcessRunner

/// Thin, best-effort wrapper around the GitHub CLI (`gh`). Deliberately minimal and OPTIONAL:
/// it opens a pull-request page in the browser and tells you whether `gh` exists — it never
/// authors a PR body, never merges. If `gh` isn't installed, every call degrades gracefully.
public enum GitHubCLI {
    /// Where `gh` might live. A sandboxed or GUI process often has a bare PATH, so the common
    /// Homebrew and system locations are probed directly before falling back to `which`.
    public static let candidatePaths = [
        "/opt/homebrew/bin/gh",   // Apple Silicon Homebrew
        "/usr/local/bin/gh",      // Intel Homebrew
        "/usr/bin/gh",
        "/run/current-system/sw/bin/gh",   // nix
    ]

    /// Absolute path to `gh`, or nil if it can't be found.
    public static func executablePath(candidates: [String] = candidatePaths,
                                      which: (String) -> String? = ProcessRunner.which) -> String? {
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) { return path }
        return which("gh")
    }

    /// Whether `gh` is available on this machine.
    public static var isAvailable: Bool { executablePath() != nil }

    /// Opens the branch's pull request in the browser: the existing PR (`gh pr view --web`) or,
    /// if there is none, the create-PR page (`gh pr create --web`, which the user fills in).
    /// False when `gh` is unavailable or neither command launched. Blocking — call off-main.
    @discardableResult
    public static func openPullRequestInBrowser(cwd: URL) -> Bool {
        guard let gh = executablePath() else { return false }
        if ProcessRunner.run(gh, ["pr", "view", "--web"], directory: cwd).succeeded { return true }
        return ProcessRunner.run(gh, ["pr", "create", "--web"], directory: cwd).succeeded
    }
}
