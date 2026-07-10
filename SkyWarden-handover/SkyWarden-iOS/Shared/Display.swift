// Sky Warden — display preferences
//
// The dial exists in two forms and neither is obviously better: the arc reads
// like a gauge (left is good, right is not), the radial reads like a dashboard
// and puts the verdict in the middle. Both encode identical data with the same
// comfort-angle mapping, so this is taste, not meaning — hence a setting.

import Foundation

enum DialStyle: String, CaseIterable, Identifiable {
    case arc, radial
    var id: String { rawValue }

    var title: String {
        switch self {
        case .arc:    "Arc"
        case .radial: "Radial"
        }
    }

    var blurb: String {
        switch self {
        case .arc:    "A half-dial gauge. Good on the left, uncomfortable on the right."
        case .radial: "Full rings around a verdict orb, coloured by how good today is."
        }
    }
}

/// What a ring's *filled length* means on the arc dial. Position and colour
/// always carry comfort; this only changes where the fill starts and how far it
/// runs, because "start at 0" means genuinely different things:
///
///   .comfort  fill runs from the good (left) end to the needle. A comfortable
///             metric is a short arc, an uncomfortable one nearly full. Length
///             and colour then agree. Nothing emanates from the top.
///   .value    fill is the raw value on the metric's own 0→max scale. UV 0 is
///             empty, UV 11 full. Honest to the number, but two temperatures
///             sit at different lengths for reasons unrelated to comfort.
///   .both     value fill, plus a tick marking where the comfort borderline
///             falls on that ring. Magnitude from length, comfort from the tick.
enum ArcFillMode: String, CaseIterable, Identifiable {
    case comfort, value, both
    var id: String { rawValue }

    var title: String {
        switch self {
        case .comfort: "Comfort"
        case .value:   "Value"
        case .both:    "Both"
        }
    }

    var blurb: String {
        switch self {
        case .comfort: "Arc length grows as the metric gets less comfortable."
        case .value:   "Arc length is the raw reading on its own 0-to-max scale."
        case .both:    "Arc length is the reading; a tick marks the comfort line."
        }
    }
}

enum DisplayKey {
    static let dialStyle   = "display.dialStyle"
    static let arcFillMode = "display.arcFillMode"
}

enum Display {
    static var dialStyle: DialStyle {
        DialStyle(rawValue: UserDefaults.standard.string(forKey: DisplayKey.dialStyle) ?? "") ?? .arc
    }
    static var arcFillMode: ArcFillMode {
        ArcFillMode(rawValue: UserDefaults.standard.string(forKey: DisplayKey.arcFillMode) ?? "") ?? .comfort
    }
}
