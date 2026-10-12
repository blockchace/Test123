import SwiftUI
import AppKit

@main
struct AireAudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup("Aire Audio") {
            MainView(model: Recorder.shared)
                .frame(minWidth: 400, minHeight: 350)
        }
        .defaultSize(width: 460, height: 500)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem?
    private var panel: NSPanel?
    private var observer: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refreshMenu()
        observer = NotificationCenter.default.addObserver(
            forName: Recorder.stateChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshMenu() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showApp()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard Recorder.shared.busy else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Hay una grabación en curso"
        alert.informativeText = "Detén y guarda la grabación antes de salir."
        alert.addButton(withTitle: "Volver a la grabación")
        alert.runModal()
        return .terminateCancel
    }

    private func refreshMenu() {
        let model = Recorder.shared
        item?.button?.image = NSImage(systemSymbolName: model.busy ? "record.circle.fill" : "mic.fill", accessibilityDescription: "Aire Audio")
        item?.button?.contentTintColor = model.busy ? .systemRed : nil
        item?.button?.title = model.busy ? (model.paused ? " Pausa" : " REC") : ""
        let menu = NSMenu()
        let open = NSMenuItem(title: "Mostrar Aire Audio", action: #selector(showApp), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        if model.busy {
            let pause = NSMenuItem(title: model.paused ? "Reanudar" : "Pausar", action: #selector(togglePause), keyEquivalent: "")
            pause.target = self
            pause.isEnabled = model.phase == .recording
            menu.addItem(pause)
            let stop = NSMenuItem(title: "Detener y guardar", action: #selector(stopRecording), keyEquivalent: "")
            stop.target = self
            stop.isEnabled = model.phase == .recording
            menu.addItem(stop)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        item?.menu = menu
        if model.phase == .recording {
            if panel == nil {
                let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 78), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                p.level = .floating
                p.isFloatingPanel = true
                p.isMovableByWindowBackground = true
                p.backgroundColor = .clear
                p.isOpaque = false
                p.hasShadow = true
                p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                p.contentView = NSHostingView(rootView: FloatingControls(model: model))
                if let screen = NSScreen.main {
                    p.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 340, y: screen.visibleFrame.maxY - 100))
                }
                panel = p
            }
            panel?.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }

    @objc private func showApp() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { !($0 is NSPanel) })?.makeKeyAndOrderFront(nil)
    }
    @objc private func togglePause() { Recorder.shared.togglePause() }
    @objc private func stopRecording() { Recorder.shared.stop() }
}
