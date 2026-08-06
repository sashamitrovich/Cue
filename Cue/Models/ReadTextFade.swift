import Foundation

/// How brightly a word that has already been read is drawn.
///
/// Read text used to be one flat grey for everything behind the cursor, which
/// made the line you had just said unreadable from any distance — exactly the
/// line you want back when you decide to say it again. Brightness now falls
/// with distance behind the cursor instead: the last line or two stays
/// legible, older text recedes, and the sense of progress survives.
enum ReadTextFade {
    /// Brightness of a word immediately behind the cursor.
    static let nearBrightness: Double = 0.85
    /// How many words behind the cursor it takes to reach the floor.
    static let fadeDistance: Double = 15

    /// The dimmest read text can go, and the range offered to the reader.
    static let floorRange: ClosedRange<Double> = 0.25...0.9
    static let defaultFloor: Double = 0.55

    /// - Parameters:
    ///   - wordsBehind: how far behind the cursor the word is; 0 is the word
    ///     just read.
    ///   - floor: the dimmest the reader allows read text to become.
    static func brightness(wordsBehind: Int, floor: Double) -> Double {
        let floor = min(max(floor, floorRange.lowerBound), floorRange.upperBound)
        // A floor brighter than the near value would fade text *upward*; treat
        // it as a flat brightness instead.
        guard nearBrightness > floor else { return floor }
        let distance = min(max(Double(wordsBehind), 0), fadeDistance)
        let travelled = distance / fadeDistance
        return nearBrightness - (nearBrightness - floor) * travelled
    }
}
