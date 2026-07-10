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

enum DisplayKey {
    static let dialStyle = "display.dialStyle"
}

enum Display {
    static var dialStyle: DialStyle {
        DialStyle(rawValue: UserDefaults.standard.string(forKey: DisplayKey.dialStyle) ?? "") ?? .radial
    }
}
