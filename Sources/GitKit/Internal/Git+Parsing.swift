//
//  Git+Parsing.swift
//  SwiftGitCLI
//
//  Internal pure-function parsers shared across operations. Kept at `internal`
//  access (not `private`) so they can be unit-tested directly.
//
//  Created by David Sherlock on 7/9/26.
//

import Foundation

extension Git {

    /// Parses a unified-diff hunk field like `"+12,3"` → `(start: 12, count: 3)`.
    ///
    /// The leading `+`/`-` is stripped; a missing count defaults to `1`
    /// (e.g. `"-5"` → `(5, 1)`), matching the unified-diff shorthand.
    static func counts(_ field: Substring) -> (Int, Int) {
        let body = field.dropFirst()  // strip +/-
        let nums = body.split(separator: ",")
        let start = Int(nums.first ?? "0") ?? 0
        let count = nums.count > 1 ? (Int(nums[1]) ?? 1) : 1
        return (start, count)
    }

    /// Formats a Unix epoch timestamp as a short relative age (`"just now"`,
    /// `"5m ago"`, `"3d ago"`, `"2mo ago"`, `"1y ago"`).
    ///
    /// - Parameters:
    ///   - ts: The event time as seconds since the Unix epoch.
    ///   - now: The reference "now", defaulting to the current time. Injectable
    ///     so the formatting is deterministically unit-testable.
    static func relativeTime(_ ts: TimeInterval, now: TimeInterval = Date().timeIntervalSince1970) -> String {
        let s = Int(now - ts)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86400 { return "\(s / 3600)h ago" }
        if s < 2_592_000 { return "\(s / 86400)d ago" }
        if s < 31_536_000 { return "\(s / 2_592_000)mo ago" }
        return "\(s / 31_536_000)y ago"
    }
}
