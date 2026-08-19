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
    /// Shared surface for the outline and inspector. Both side panels use the
    /// same flat material; cards are reserved for content inside a panel.
    static let workspacePanelBackground = Color(nsColor: .controlBackgroundColor)
}

private struct WorkspaceFloatingPanel: ViewModifier {
    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: shape)
            .clipShape(shape)
            .overlay(shape.stroke(Color.secondary.opacity(0.14), lineWidth: 1))
            .padding(8)
    }
}

extension View {
    /// Gives the inspector the same floating panel hierarchy as the system
    /// navigation sidebar, while leaving cards inside the panel unchanged.
    func workspaceFloatingPanel() -> some View {
        modifier(WorkspaceFloatingPanel())
    }
}
