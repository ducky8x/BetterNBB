import AppKit
import Vision
import ScreenCaptureKit

// MARK: - Screen Capture (ScreenCaptureKit)

func captureRegion(_ rect: CGRect) async -> CGImage? {
    guard let screen = NSScreen.main else { return nil }

    // Convert from top-left origin (AppKit) to bottom-left (Quartz)
    let flipped = CGRect(
        x: rect.origin.x,
        y: screen.frame.height - rect.origin.y - rect.height,
        width: rect.width,
        height: rect.height
    )

    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            print("⚠️  No display found")
            return nil
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect   = flipped
        config.width        = max(1, Int(rect.width))
        config.height       = max(1, Int(rect.height))
        config.scalesToFit  = false

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    } catch {
        print("⚠️  Capture failed: \(error)\n    → Grant Screen Recording in System Settings › Privacy & Security")
        return nil
    }
}

// MARK: - OCR

func recognizeNumber(in image: CGImage) -> String {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel        = .accurate
    request.usesLanguageCorrection  = false
    request.recognitionLanguages    = ["en-US"]

    try? VNImageRequestHandler(cgImage: image).perform([request])

    let raw = request.results?
        .compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: " ") ?? ""

    return raw
        .components(separatedBy: .whitespaces)
        .first { !$0.isEmpty && $0.allSatisfy { "0123456789.-".contains($0) } }
        ?? ""
}

// MARK: - Overlay Window

final class OverlayWindow: NSWindowController {
    private let label = NSTextField(labelWithString: "--")

    init() {
        let frame = NSRect(x: 0, y: 0, width: 480, height: 110)
        let win   = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.level            = .floating
        win.isOpaque         = false
        win.backgroundColor  = .clear
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.hasShadow        = false
        super.init(window: win)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment      = .center
        label.font           = NSFont(name: "Avenir-Heavy", size: 64) ?? .boldSystemFont(ofSize: 64)
        label.textColor      = .systemGreen
        label.backgroundColor = .clear
        win.contentView?.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: win.contentView!.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: win.contentView!.trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: win.contentView!.centerYAnchor),
        ])

        centerOnScreen()
        win.makeKeyAndOrderFront(nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func centerOnScreen() {
        guard let screen = NSScreen.main, let win = window else { return }
        win.setFrameOrigin(NSPoint(
            x: screen.frame.midX - win.frame.width  / 2,
            y: screen.frame.midY - win.frame.height / 2
        ))
    }

    func update(text: String, font: NSFont, color: NSColor) {
        DispatchQueue.main.async {
            self.label.stringValue = text.isEmpty ? "--" : text
            self.label.font        = font
            self.label.textColor   = color
        }
    }
}

// MARK: - Region Picker (drag a rectangle on screen)

protocol RegionPickerDelegate: AnyObject {
    func regionPicker(_ picker: RegionPicker, didSelect rect: CGRect)
}

final class RegionPicker: NSWindowController, NSWindowDelegate {
    weak var delegate: RegionPickerDelegate?
    private var startPoint: NSPoint = .zero
    private var selectionView: NSView?

    init() {
        let screen = NSScreen.main?.frame ?? .zero
        let win    = NSWindow(contentRect: screen, styleMask: .borderless, backing: .buffered, defer: false)
        win.level           = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        win.backgroundColor = NSColor.black.withAlphaComponent(0.35)
        win.isOpaque        = false
        win.ignoresMouseEvents = false
        super.init(window: win)
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        win.contentView?.addTrackingArea(NSTrackingArea(
            rect: win.contentView!.bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
            owner: win.contentView, userInfo: nil
        ))
        NSCursor.crosshair.set()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        startPoint = event.locationInWindow
        let box = NSView(frame: NSRect(origin: startPoint, size: .zero))
        box.wantsLayer = true
        box.layer?.borderColor = NSColor.systemBlue.cgColor
        box.layer?.borderWidth = 2
        box.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.15).cgColor
        window?.contentView?.addSubview(box)
        selectionView = box
    }

    override func mouseDragged(with event: NSEvent) {
        guard let box = selectionView else { return }
        let current = event.locationInWindow
        let origin  = NSPoint(x: min(startPoint.x, current.x), y: min(startPoint.y, current.y))
        let size    = NSSize(width: abs(current.x - startPoint.x), height: abs(current.y - startPoint.y))
        box.frame   = NSRect(origin: origin, size: size)
    }

    override func mouseUp(with event: NSEvent) {
        guard let box = selectionView, let screen = NSScreen.main else { close(); return }

        // box.frame is in window (bottom-left) coords — convert to top-left for our fields
        let picked = CGRect(
            x: box.frame.origin.x,
            y: screen.frame.height - box.frame.origin.y - box.frame.height,
            width: box.frame.width,
            height: box.frame.height
        )

        NSCursor.arrow.set()
        close()

        if picked.width > 4 && picked.height > 4 {
            delegate?.regionPicker(self, didSelect: picked)
        }
    }
}

// MARK: - Control Window

final class ControlWindow: NSWindowController, RegionPickerDelegate {
    // Region fields
    private let xField = field("100");  private let yField = field("100")
    private let wField = field("300");  private let hField = field("120")
    // Display fields
    private let fontField  = field("Avenir-Heavy")
    private let sizeField  = field("64")
    private let colorWell  = NSColorWell()

    private var picker: RegionPicker?

    var onStart: ((CGRect, NSFont, NSColor) -> Void)?
    var onStop:  (() -> Void)?

    init() {
        let win = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 460, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Number OCR"
        super.init(window: win)
        buildUI(in: win.contentView!)
        win.makeKeyAndOrderFront(nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UI Layout

    private func buildUI(in root: NSView) {
        let stack = vstack(spacing: 16, insets: NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20))
        root.addSubview(stack)
        fill(stack, in: root)

        // Section: Capture Region
        stack.addArrangedSubview(sectionLabel("Capture Region"))
        stack.addArrangedSubview(hrow("X:", xField, "Y:", yField))
        stack.addArrangedSubview(hrow("W:", wField, "H:", hField))

        let pickBtn = button("⌖  Pick Region…", action: #selector(pickRegion))
        stack.addArrangedSubview(pickBtn)

        // Section: Display
        stack.addArrangedSubview(sectionLabel("Display"))
        stack.addArrangedSubview(hrow("Font:", fontField, "Size:", sizeField))

        colorWell.color = .systemGreen
        colorWell.widthAnchor.constraint(equalToConstant: 44).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let colorRow = NSStackView(views: [NSTextField(labelWithString: "Color:"), colorWell, NSView()])
        colorRow.spacing = 8
        stack.addArrangedSubview(colorRow)

        // Buttons
        let startBtn = button("▶  Start", action: #selector(startTapped))
        let stopBtn  = button("■  Stop",  action: #selector(stopTapped))
        let btnRow   = NSStackView(views: [startBtn, stopBtn])
        btnRow.distribution = .fillEqually
        btnRow.spacing = 12
        stack.addArrangedSubview(btnRow)
    }

    // MARK: - Actions

    @objc private func pickRegion() {
        picker = RegionPicker()
        picker?.delegate = self
    }

    func regionPicker(_ picker: RegionPicker, didSelect rect: CGRect) {
        DispatchQueue.main.async {
            self.xField.stringValue = String(Int(rect.origin.x))
            self.yField.stringValue = String(Int(rect.origin.y))
            self.wField.stringValue = String(Int(rect.width))
            self.hField.stringValue = String(Int(rect.height))
        }
    }

    @objc private func startTapped() {
        guard
            let x    = Double(xField.stringValue),
            let y    = Double(yField.stringValue),
            let w    = Double(wField.stringValue),
            let h    = Double(hField.stringValue),
            let size = Double(sizeField.stringValue)
        else {
            let alert = NSAlert()
            alert.messageText = "Invalid input"
            alert.informativeText = "X, Y, W, H and Size must all be numbers."
            alert.runModal()
            return
        }
        let font  = NSFont(name: fontField.stringValue, size: size) ?? .boldSystemFont(ofSize: size)
        let color = colorWell.color
        onStart?(CGRect(x: x, y: y, width: w, height: h), font, color)
    }

    @objc private func stopTapped() { onStop?() }

    // MARK: - Layout helpers

    private func hrow(_ l1: String, _ f1: NSTextField,
                      _ l2: String, _ f2: NSTextField) -> NSStackView {
        let s = NSStackView(views: [NSTextField(labelWithString: l1), f1,
                                    NSTextField(labelWithString: l2), f2])
        s.spacing = 8
        f1.widthAnchor.constraint(equalToConstant: 110).isActive = true
        f2.widthAnchor.constraint(equalToConstant: 110).isActive = true
        return s
    }
}

// MARK: - Layout utilities

private func field(_ s: String) -> NSTextField { NSTextField(string: s) }

private func sectionLabel(_ s: String) -> NSTextField {
    let l = NSTextField(labelWithString: s.uppercased())
    l.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
    l.textColor = .secondaryLabelColor
    return l
}

private func button(_ title: String, action: Selector) -> NSButton {
    let b = NSButton(title: title, target: nil, action: action)
    b.bezelStyle = .rounded
    return b
}

private func vstack(spacing: CGFloat, insets: NSEdgeInsets) -> NSStackView {
    let s = NSStackView()
    s.orientation  = .vertical
    s.alignment    = .leading
    s.spacing      = spacing
    s.edgeInsets   = insets
    s.translatesAutoresizingMaskIntoConstraints = false
    return s
}

private func fill(_ view: NSView, in parent: NSView) {
    NSLayoutConstraint.activate([
        view.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
        view.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
        view.topAnchor.constraint(equalTo: parent.topAnchor),
        view.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
    ])
}

// MARK: - Coordinator

final class AppCoordinator {
    private let overlay  = OverlayWindow()
    private let controls = ControlWindow()
    private var timer:   Timer?
    private var region   = CGRect(x: 100, y: 100, width: 300, height: 120)
    private var font     = NSFont(name: "Avenir-Heavy", size: 64) ?? NSFont.boldSystemFont(ofSize: 64)
    private var color    = NSColor.systemGreen

    init() {
        controls.onStart = { [weak self] rect, font, color in
            self?.region = rect
            self?.font   = font
            self?.color  = color
            self?.startPolling()
        }
        controls.onStop = { [weak self] in self?.stopPolling() }
    }

    private func startPolling() {
        stopPolling()
        timer = .scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func stopPolling() { timer?.invalidate(); timer = nil }

    private func tick() {
        let (region, font, color) = (self.region, self.font, self.color)
        Task {
            guard let image = await captureRegion(region) else { return }
            let text = recognizeNumber(in: image)
            self.overlay.update(text: text, font: font, color: color)
        }
    }
}

// MARK: - Entry Point

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    func applicationDidFinishLaunching(_ n: Notification) { coordinator = AppCoordinator() }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

let app      = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()