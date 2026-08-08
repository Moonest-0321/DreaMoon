import SwiftUI
import AppKit

// MARK: - 集中主題色（PRD 第六節）
// 淺色模式：完全跟隨系統（PRD「跟隨系統」）。
// 深色模式：用 PRD 點名的護眼深灰 #1E1E1E 取代系統純黑。
// 實作：NSColor dynamic provider 依當前 NSAppearance 自動切換，無需手動讀 colorScheme。
extension NSColor {
    static let appBackgroundDynamic: NSColor = NSColor(name: nil, dynamicProvider: { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(red: 30.0/255.0, green: 30.0/255.0, blue: 30.0/255.0, alpha: 1.0) // #1E1E1E
            : NSColor.windowBackgroundColor
    })
}

extension Color {
    static let appBackground: Color = Color(nsColor: .appBackgroundDynamic)
}
