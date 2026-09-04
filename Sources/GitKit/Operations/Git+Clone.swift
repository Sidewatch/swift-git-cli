//
//  Git+Clone.swift
//  SwiftGitCLI
//
//  Clone a remote repository into a local directory.
//

import Foundation

public extension Git {

    /// The outcome of a clone: the created directory on success, or git's error text.
    struct CloneResult: Equatable, Sendable {
        public let path: URL?
        public let error: String?
        public var succeeded: Bool { path != nil }
    }

    /// Clones `url` into `parent` (under `name`, or git's default directory name).
    ///
    /// Blocking and network-bound — call OFF the main thread. Unlike ``run(_:in:)`` this
    /// captures git's stderr so a failure (bad URL, auth, network) surfaces a real message.
    ///
    /// - Returns: `.path` = the cloned directory on success; `.error` = git's stderr otherwise.
    static func clone(from url: String, into parent: URL, name: String? = nil) -> CloneResult {
        var args = ["clone", url]
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedName, !trimmedName.isEmpty { args.append(trimmedName) }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        p.currentDirectoryURL = parent
        let errPipe = Pipe()
        p.standardOutput = FileHandle.nullDevice
        p.standardError = errPipe
        do { try p.run() } catch {
            return CloneResult(path: nil, error: "Couldn't launch git: \(error.localizedDescription)")
        }
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let text = (String(data: errData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return CloneResult(path: nil, error: text.isEmpty ? "git clone failed (exit \(p.terminationStatus))" : text)
        }
        let dir = (trimmedName?.isEmpty == false ? trimmedName! : defaultCloneDirectoryName(for: url))
        return CloneResult(path: parent.appendingPathComponent(dir), error: nil)
    }

    /// The directory `git clone <url>` creates by default: the last path component of the
    /// URL, minus a trailing `.git`. Handles both `https://…/owner/repo.git` and scp-style
    /// `git@host:owner/repo.git`. Pure — covered by `GitCloneTests`.
    static func defaultCloneDirectoryName(for url: String) -> String {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        // Take everything after the last "/" or ":" (scp form has no slash before the repo).
        if let cut = s.lastIndex(where: { $0 == "/" || $0 == ":" }) {
            s = String(s[s.index(after: cut)...])
        }
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        return s.isEmpty ? "repository" : s
    }
}
