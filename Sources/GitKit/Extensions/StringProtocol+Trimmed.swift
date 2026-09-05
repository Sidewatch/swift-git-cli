//
//  StringProtocol+Trimmed.swift
//  GitKit
//
//  Leading and trailing whitespace and newlines removed.
//
//  Created by David Sherlock on 9/5/26.
//

import Foundation

extension StringProtocol {
    /// Leading and trailing whitespace and newlines removed.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
