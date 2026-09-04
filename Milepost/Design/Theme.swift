import SwiftUI

enum Theme {
    static let orange = Color(red: 1.0, green: 0.36, blue: 0.10)
    static let paused = Color(red: 1.0, green: 0.76, blue: 0.0)
    static let splitBlue = Color(red: 0.16, green: 0.44, blue: 0.88)
    static let background = Color(red: 0.055, green: 0.055, blue: 0.055)
    static let card = Color(red: 0.11, green: 0.11, blue: 0.11)
    static let barIdle = Color(red: 0.22, green: 0.22, blue: 0.22)
    static let secondaryText = Color(white: 0.7)
}

extension Font {
    static func stat(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }
}

extension Date {
    var activityDateText: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: self)
    }
}
