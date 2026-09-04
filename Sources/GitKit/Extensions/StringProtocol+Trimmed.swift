import Foundation

extension StringProtocol {
    /// Leading and trailing whitespace and newlines removed.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
