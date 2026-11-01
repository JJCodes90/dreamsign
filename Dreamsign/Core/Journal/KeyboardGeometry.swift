import Foundation

/// QWERTY layout heuristics for spotting keyboard mashing ("asdf", "jkjkjk", "sdkfjh").
enum KeyboardGeometry {
    static let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    /// Horizontal stagger of each row in key widths (iPhone layout: the shift key pushes row 3 right).
    private static let offsets: [Double] = [0, 0.5, 1.5]

    private static let positions: [Character: (x: Double, y: Double)] = {
        var map: [Character: (x: Double, y: Double)] = [:]
        for (row, keys) in rows.enumerated() {
            for (column, key) in keys.enumerated() {
                map[key] = (Double(column) + offsets[row], Double(row))
            }
        }
        return map
    }()

    /// Same key, or physically touching keys (including diagonal neighbours).
    static func areAdjacent(_ a: Character, _ b: Character) -> Bool {
        guard let p = positions[a], let q = positions[b] else { return false }
        if a == b { return true }
        return abs(p.y - q.y) <= 1 && abs(p.x - q.x) <= 1.0001
    }

    /// Share of consecutive letter pairs that sit next to each other on the keyboard.
    static func adjacencyRatio(_ letters: [Character]) -> Double {
        guard letters.count >= 2 else { return 0 }
        var adjacent = 0
        for index in 1..<letters.count where areAdjacent(letters[index - 1], letters[index]) {
            adjacent += 1
        }
        return Double(adjacent) / Double(letters.count - 1)
    }

    /// True when `letters` contains `length` consecutive keys from one row, in either direction.
    static func containsRowRun(_ letters: [Character], length: Int = 4) -> Bool {
        guard letters.count >= length else { return false }
        let candidates = rows + rows.map { String($0.reversed()) }
        for start in 0...(letters.count - length) {
            let slice = String(letters[start..<(start + length)])
            if candidates.contains(where: { $0.contains(slice) }) { return true }
        }
        return false
    }
}

/// Letter-level heuristics shared by the journal validator.
enum GibberishHeuristics {
    private static let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]

    static func longestRun(_ letters: [Character]) -> Int {
        guard var previous = letters.first else { return 0 }
        var longest = 1, current = 1
        for letter in letters.dropFirst() {
            current = letter == previous ? current + 1 : 1
            longest = max(longest, current)
            previous = letter
        }
        return longest
    }

    static func vowelRatio(_ letters: [Character]) -> Double {
        guard !letters.isEmpty else { return 0 }
        return Double(letters.filter { vowels.contains($0) }.count) / Double(letters.count)
    }

    /// "lalala", "abcabc", "kjkjkj" — short units repeated.
    static func isPeriodic(_ letters: [Character]) -> Bool {
        guard letters.count >= 6 else { return false }
        for period in 1...3 where letters.count >= period * 2 {
            if letters.indices.allSatisfy({ letters[$0] == letters[$0 % period] }) { return true }
        }
        return false
    }

    /// Mashing signatures for a lowercase ASCII word the lexicon doesn't know.
    static func looksMashed(_ letters: [Character]) -> Bool {
        guard letters.allSatisfy({ $0.isASCII && $0.isLetter }) else { return false }
        let count = letters.count
        if count > 24 { return true }
        if count >= 4 && KeyboardGeometry.containsRowRun(letters) { return true }
        if count >= 4 && vowelRatio(letters) == 0 { return true }
        if count >= 5 && vowelRatio(letters) < 0.15 { return true }
        if count >= 5 && KeyboardGeometry.adjacencyRatio(letters) >= 0.7 { return true }
        if isPeriodic(letters) { return true }
        return false
    }
}
