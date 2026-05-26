{\rtf1\ansi\ansicpg1252\cocoartf2869
\cocoatextscaling0\cocoaplatform0{\fonttbl\f0\fswiss\fcharset0 Helvetica;}
{\colortbl;\red255\green255\blue255;}
{\*\expandedcolortbl;;}
\margl1440\margr1440\vieww11520\viewh8400\viewkind0
\pard\tx720\tx1440\tx2160\tx2880\tx3600\tx4320\tx5040\tx5760\tx6480\tx7200\tx7920\tx8640\pardirnatural\partightenfactor0

\f0\fs24 \cf0 import AppKit\
import Vision\
import CoreGraphics\
\
// MARK: - OCR Engine\
final class NumberOCR \{\
    private let request: VNRecognizeTextRequest\
\
    init() \{\
        request = VNRecognizeTextRequest()\
        request.recognitionLevel = .accurate\
        request.usesLanguageCorrection = false\
        request.recognitionLanguages = ["en-US"]\
    \}\
\
    func readNumber(from cgImage: CGImage) -> String \{\
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])\
        do \{\
            try handler.perform([request])\
        \} catch \{\
            return ""\
        \}\
\
        guard let results = request.results else \{ return "" \}\
\
        let joined = results\
            .compactMap \{ $0.topCandidates(1).first?.string \}\
            .joined(separator: " ")\
\
        // Keep only digits, minus, dot\
        let filtered = joined.filter \{ "0123456789.-".contains($0) \}\
\
        // Optional: keep first valid number-like token\
        if let token = filtered.split(whereSeparator: \{ $0 == " " \}).first \{\
            return String(token)\
        \}\
\
        return filtered\
    \}\
\}\
\
// MARK: - Overlay Window\
final class OverlayWindowController: NSWindowController \{\
    let label = NSTextField(labelWithString: "--")\
\
    convenience init() \{\
        let screenFrame = NSScreen.main?.frame ?? .zero\
        let window = NSWindow(\
            contentRect: NSRect(x: 100, y: 100, width: 420, height: 120),\
            styleMask: [.borderless],\
            backing: .buffered,\
            defer: false\
        )\
        window.level = .floating\
        window.isOpaque = false\
        window.backgroundColor = .clear\
        window.ignoresMouseEvents = true\
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]\
        window.hasShadow = false\
\
        self.init(window: window)\
\
        label.frame = NSRect(x: 10, y: 20, width: 400, height: 80)\
        label.alignment = .center\
        label.font = NSFont(name: "Avenir-Heavy", size: 60) ?? NSFont.systemFont(ofSize: 60, weight: .bold)\
        label.textColor = .systemGreen\
        label.backgroundColor = .clear\
        window.contentView?.addSubview(label)\
\
        window.setFrameOrigin(NSPoint(x: screenFrame.midX - 210, y: screenFrame.midY - 60))\
        window.makeKeyAndOrderFront(nil)\
    \}\
\
    func updateText(_ text: String, fontName: String, fontSize: CGFloat, color: NSColor) \{\
        label.stringValue = text.isEmpty ? "--" : text\
        label.font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: .bold)\
        label.textColor = color\
    \}\
\}\
\
// MARK: - Control Window\
final class ControlWindowController: NSWindowController \{\
    let xField = NSTextField(string: "100")\
    let yField = NSTextField(string: "100")\
    let wField = NSTextField(string: "300")\
    let hField = NSTextField(string: "120")\
\
    let fontField = NSTextField(string: "Avenir-Heavy")\
    let sizeField = NSTextField(string: "60")\
    let startButton = NSButton(title: "Start OCR", target: nil, action: nil)\
    let stopButton = NSButton(title: "Stop OCR", target: nil, action: nil)\
\
    var onStart: ((CGRect, String, CGFloat) -> Void)?\
    var onStop: (() -> Void)?\
\
    convenience init() \{\
        let window = NSWindow(\
            contentRect: NSRect(x: 200, y: 200, width: 420, height: 250),\
            styleMask: [.titled, .closable, .miniaturizable],\
            backing: .buffered,\
            defer: false\
        )\
        window.title = "Number OCR Controls"\
        self.init(window: window)\
\
        let content = NSView(frame: window.contentRect(forFrameRect: window.frame))\
        window.contentView = content\
\
        func addLabel(_ text: String, _ x: CGFloat, _ y: CGFloat) \{\
            let l = NSTextField(labelWithString: text)\
            l.frame = NSRect(x: x, y: y, width: 120, height: 22)\
            content.addSubview(l)\
        \}\
\
        func place(_ field: NSTextField, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 80) \{\
            field.frame = NSRect(x: x, y: y, width: w, height: 24)\
            content.addSubview(field)\
        \}\
\
        addLabel("Region X:", 20, 200); place(xField, 110, 198)\
        addLabel("Region Y:", 210, 200); place(yField, 300, 198)\
\
        addLabel("Width:", 20, 165); place(wField, 110, 163)\
        addLabel("Height:", 210, 165); place(hField, 300, 163)\
\
        addLabel("Font Name:", 20, 125); place(fontField, 110, 123, 270)\
        addLabel("Font Size:", 20, 90); place(sizeField, 110, 88)\
\
        startButton.frame = NSRect(x: 40, y: 30, width: 150, height: 32)\
        stopButton.frame = NSRect(x: 220, y: 30, width: 150, height: 32)\
\
        startButton.target = self\
        startButton.action = #selector(startTapped)\
        stopButton.target = self\
        stopButton.action = #selector(stopTapped)\
\
        content.addSubview(startButton)\
        content.addSubview(stopButton)\
\
        window.makeKeyAndOrderFront(nil)\
    \}\
\
    @objc private func startTapped() \{\
        guard\
            let x = Double(xField.stringValue),\
            let y = Double(yField.stringValue),\
            let w = Double(wField.stringValue),\
            let h = Double(hField.stringValue),\
            let size = Double(sizeField.stringValue)\
        else \{ return \}\
\
        let rect = CGRect(x: x, y: y, width: w, height: h)\
        onStart?(rect, fontField.stringValue, CGFloat(size))\
    \}\
\
    @objc private func stopTapped() \{\
        onStop?()\
    \}\
\}\
\
// MARK: - App Coordinator\
final class AppCoordinator \{\
    let ocr = NumberOCR()\
    let overlay = OverlayWindowController()\
    let controls = ControlWindowController()\
\
    var timer: Timer?\
    var targetRect: CGRect = CGRect(x: 100, y: 100, width: 300, height: 120)\
    var fontName: String = "Avenir-Heavy"\
    var fontSize: CGFloat = 60\
\
    init() \{\
        controls.onStart = \{ [weak self] rect, font, size in\
            self?.targetRect = rect\
            self?.fontName = font\
            self?.fontSize = size\
            self?.start()\
        \}\
        controls.onStop = \{ [weak self] in\
            self?.stop()\
        \}\
    \}\
\
    func start() \{\
        stop()\
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) \{ [weak self] _ in\
            self?.tick()\
        \}\
    \}\
\
    func stop() \{\
        timer?.invalidate()\
        timer = nil\
    \}\
\
    private func tick() \{\
        guard let image = capture(rect: targetRect) else \{ return \}\
        let numberText = ocr.readNumber(from: image)\
        overlay.updateText(numberText, fontName: fontName, fontSize: fontSize, color: .systemGreen)\
    \}\
\
    private func capture(rect: CGRect) -> CGImage? \{\
        // Note: coordinates are in global display space.\
        // You may need to tweak Y if using multiple monitors.\
        return CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, .bestResolution)\
    \}\
\}\
\
// MARK: - App Entry\
final class AppDelegate: NSObject, NSApplicationDelegate \{\
    var coordinator: AppCoordinator?\
\
    func applicationDidFinishLaunching(_ notification: Notification) \{\
        coordinator = AppCoordinator()\
    \}\
\
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool \{\
        true\
    \}\
\}\
\
let app = NSApplication.shared\
let delegate = AppDelegate()\
app.delegate = delegate\
app.setActivationPolicy(.regular)\
app.activate(ignoringOtherApps: true)\
app.run()}