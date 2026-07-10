// Sky Warden — how much the sources disagree
//
// The obvious measure is the range (max − min), but the range grows mechanically
// as you add samples: with six models the two extremes are almost always further
// apart than with two, so a fixed threshold silently becomes stricter every time
// a source is added. That would make the confidence score fall as the app got
// *better informed*, which is exactly backwards.
//
// So with four or more sources we drop the single highest and lowest reading
// before measuring — the same trimming the consensus mean already uses. One wild
// model can no longer define the disagreement, but a genuine split still does.

import Foundation

func robustSpread(_ values: [Double]) -> Double? {
    guard values.count >= 2 else { return nil }
    let sorted = values.sorted()
    let core = sorted.count >= 4 ? Array(sorted.dropFirst().dropLast()) : sorted
    guard let lo = core.first, let hi = core.last else { return nil }
    return hi - lo
}
