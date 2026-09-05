//
//  SideBySideRow.swift
//  GitKit
//
//  One row of a side-by-side diff: a line number, its text, and what the row is.
//
//  Created by David Sherlock on 9/6/26.
//

import Foundation

/// One row on one side of a side-by-side diff. The two sides are equal-length arrays, so
/// row `i` on the left faces row `i` on the right; a `filler` is the blank that keeps them
/// aligned where only one side has a line.
public struct SideBySideRow: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// An `@@` hunk header, shown on both sides.
        case header
        /// An unchanged line, present on both sides.
        case context
        /// An old-side-only line (left pane).
        case removed
        /// A new-side-only line (right pane).
        case added
        /// A removed line paired with an added one — both panes, tinted as a change.
        case modified
        /// A blank alignment row on the side that lacks a line.
        case filler
    }

    /// The 1-based line number on this side; nil for headers and fillers.
    public let number: Int?
    public let text: String
    public let kind: Kind

    public init(number: Int?, text: String, kind: Kind) {
        self.number = number
        self.text = text
        self.kind = kind
    }
}
