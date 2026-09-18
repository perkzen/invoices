import Foundation

extension Decimal {
    /// Rounds to `scale` decimal places, half-up — the rule Slovenian
    /// accounting expects for line and invoice amounts.
    nonisolated func rounded(scale: Int = 2) -> Decimal {
        var input = self
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .plain)
        return result
    }
}
