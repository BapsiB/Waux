import SwiftUI

struct AppStyle {
    static let mainColor = Color(hex: 0xDF8363)
    static let secondaryColor = Color(hex: 0xE0BCB7)
    
    // You can add more style constants here as needed
    // static let secondaryColor = Color(hex: 0x...)
    // static let backgroundColor = Color(hex: 0x...)
    // static let textColor = Color(hex: 0x...)
}

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}
