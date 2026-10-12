import SwiftUI
import AppKit

/// One system-composited material for the window; cards use plain translucent fills.
struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = WindowMaterial()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private final class WindowMaterial: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.titlebarAppearsTransparent = true
    }
}

struct GlassCard: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content
            .background(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : (scheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.38)), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(scheme == .dark ? 0.12 : 0.55), lineWidth: 0.5))
    }
}
