import Foundation

/// "Watch, then repeat": a pattern of tiles on a 3×3 grid. No tile repeats back to back, so
/// every step is a visible change.
struct MemoryGame: Sendable {
    static let tileCount = 9

    enum Result: Equatable, Sendable {
        case correct
        case mistake
        case solved
    }

    let length: Int
    private(set) var pattern: [Int] = []
    private(set) var entered: [Int] = []

    init(length: Int) {
        self.length = max(2, length)
    }

    /// Starts a fresh round with a new pattern.
    mutating func newPattern<R: RandomNumberGenerator>(using random: inout R) {
        var tiles: [Int] = []
        while tiles.count < length {
            let tile = Int.random(in: 0..<Self.tileCount, using: &random)
            if tile != tiles.last { tiles.append(tile) }
        }
        pattern = tiles
        entered = []
    }

    mutating func newPattern() {
        var random = SystemRandomNumberGenerator()
        newPattern(using: &random)
    }

    /// Records a tap. A mistake clears the input; call `newPattern` for the next attempt.
    mutating func tap(_ tile: Int) -> Result {
        guard entered.count < pattern.count else { return .solved }
        guard pattern[entered.count] == tile else {
            entered = []
            return .mistake
        }
        entered.append(tile)
        return entered.count == pattern.count ? .solved : .correct
    }
}
