import Foundation

public enum PCMMeter: Sendable {
    public static func measure(_ samples: [Float]) -> PCMMeterLevel {
        let finite = samples.filter(\.isFinite)
        guard !finite.isEmpty else { return .silence }
        var peak: Float = 0
        var sumOfSquares: Double = 0
        for sample in finite {
            peak = max(peak, abs(sample))
            sumOfSquares += Double(sample) * Double(sample)
        }
        return PCMMeterLevel(
            peak: min(peak, 1),
            rootMeanSquare: Float((sumOfSquares / Double(finite.count)).squareRoot())
        )
    }
}
