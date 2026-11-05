import AppKit

let widgetLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 2)

extension NSScreen {
    var displayID: UInt32 {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

func realWidgetFrames() -> [CGRect] {
    let height = NSScreen.screens.first?.frame.height ?? 0
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.compactMap { info in
        guard info[kCGWindowLayer as String] as? Int == widgetLevel.rawValue,
              let pid = info[kCGWindowOwnerPID as String] as? pid_t,
              NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.notificationcenterui",
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds),
              rect.width >= 100, rect.height >= 100 else { return nil }
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }
}

func currentDisplays() -> [Display] {
    NSScreen.screens.enumerated().map { i, screen in
        Display(id: screen.displayID, grid: SlotGrid(visibleFrame: screen.visibleFrame), isMain: i == 0)
    }
}

final class PlacementOutline {
    private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private unowned let widget: NSWindow
    private var shown: CGRect?

    init(below widget: NSWindow) {
        self.widget = widget
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = widget.level
        panel.collectionBehavior = widget.collectionBehavior
        let ring = NSView()
        ring.wantsLayer = true
        ring.layer?.cornerRadius = 30
        ring.layer?.cornerCurve = .continuous
        ring.layer?.borderWidth = 2
        ring.layer?.borderColor = rgba(255, 255, 255, 0.62)
        ring.layer?.backgroundColor = rgba(255, 255, 255, 0.07)
        panel.contentView = ring
    }

    func show(around frame: CGRect) {
        let target = frame.insetBy(dx: -4, dy: -4)
        guard target != shown else { return }
        let moving = shown != nil
        shown = target
        if !moving {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0
                panel.animator().setFrame(target, display: true)
            }
            panel.alphaValue = 0
            panel.order(.below, relativeTo: widget.windowNumber)
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = moving ? 0.16 : 0.15
            if moving { panel.animator().setFrame(target, display: true) } else { panel.animator().alphaValue = 1 }
        }
    }

    func hide() {
        guard shown != nil else { return }
        shown = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.shown == nil else { return }
            self.panel.orderOut(nil)
        })
    }
}
