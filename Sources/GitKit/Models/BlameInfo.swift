//
//  BlameInfo.swift
//  SwiftGitCLI
//
//  Authorship information for a single blamed line.
//
//  Created by David Sherlock on 7/9/26.
//

import Foundation

/// Authorship information for a single line, produced by ``Git/blame(for:line:repoRoot:)``.
public struct BlameInfo: Sendable, Equatable {

    /// The author's name, or `"Not Committed Yet"` for uncommitted lines.
    public let author: String

    /// A short human-readable age of the commit (e.g. `"3d ago"`), or `""` when unavailable.
    public let timeAgo: String

    /// The commit's summary line (its first line).
    public let summary: String

    /// Creates a blame record. Normally produced by ``Git/blame(for:line:repoRoot:)``;
    /// public for constructing fixtures in tests and previews.
    public init(author: String, timeAgo: String, summary: String) {
        self.author = author
        self.timeAgo = timeAgo
        self.summary = summary
    }
}
