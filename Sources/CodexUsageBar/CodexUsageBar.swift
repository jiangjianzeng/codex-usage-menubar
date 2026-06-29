import AppKit
import CodexUsageCore
import Foundation

@MainActor
final class UsageApp: NSObject {
    private static let refreshInterval: TimeInterval = 120
    private static let initialStatusItemWidth: CGFloat = 60

    private let statusItem = NSStatusBar.system.statusItem(withLength: initialStatusItemWidth)
    private let statusView = StatusUsageView(frame: NSRect(x: 0, y: 0, width: initialStatusItemWidth, height: NSStatusBar.system.thickness))
    private let reader = CodexUsageReader()
    private let popover = NSPopover()
    private let viewController = UsageViewController()
    private var timer: Timer?
    private var latestSnapshot: CodexUsageSnapshot?
    private var latestError: Error?
    private var isRefreshing = false

    override init() {
        super.init()
        configureStatusButton()
        configurePopover()
        renderLoading()
        refreshAsync()

        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAsync()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func configureStatusButton() {
        statusView.target = self
        statusView.action = #selector(togglePopover)
        statusView.toolTip = "Codex usage"
        statusItem.view = statusView
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 292, height: 302)
        popover.contentViewController = viewController
    }

    private func refreshAsync() {
        guard !isRefreshing else { return }
        isRefreshing = true

        DispatchQueue.global(qos: .utility).async { [reader] in
            let result = Result { try reader.read() }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isRefreshing = false
                switch result {
                case .success(let snapshot):
                    self.latestSnapshot = snapshot
                    self.latestError = nil
                    self.render(snapshot: snapshot, error: nil)
                case .failure(let error):
                    self.latestError = error
                    if let snapshot = self.latestSnapshot {
                        self.render(snapshot: snapshot, error: error)
                    } else {
                        self.renderLoading(error: error)
                    }
                }
            }
        }
    }

    private func renderLoading(error: Error? = nil) {
        statusView.render(snapshot: nil, hasError: error != nil)
        resizeStatusItem()
        viewController.render(snapshot: nil, error: error, nextRefresh: Date().addingTimeInterval(Self.refreshInterval))
    }

    private func render(snapshot: CodexUsageSnapshot, error: Error?) {
        statusView.render(snapshot: snapshot, hasError: error != nil)
        resizeStatusItem()
        viewController.render(snapshot: snapshot, error: error, nextRefresh: Date().addingTimeInterval(Self.refreshInterval))
    }

    private func resizeStatusItem() {
        let width = statusView.preferredWidth
        statusItem.length = width
        statusView.frame.size.width = width
    }

    @objc private func togglePopover() {
        refreshAsync()
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: statusView.bounds, of: statusView, preferredEdge: .minY)
            activatePopoverWindow()
        }
    }

    private func activatePopoverWindow() {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let window = self.popover.contentViewController?.view.window
            else {
                return
            }

            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(self.popover.contentViewController?.view)
        }
    }
}

private final class StatusUsageView: NSControl {
    private static let font = NSFont.systemFont(ofSize: 9, weight: .regular)
    private static let iconX: CGFloat = 1
    private static let iconSize: CGFloat = 17
    private static let textGap: CGFloat = 4

    private var primaryText = "5h --%"
    private var secondaryText = "7d --%"
    private var textColor = NSColor.labelColor
    private var iconColor = NSColor.white.withAlphaComponent(0.92)

    override var isFlipped: Bool { true }

    var preferredWidth: CGFloat {
        let textWidth = max(Self.textWidth(primaryText), Self.textWidth(secondaryText))
        return ceil(Self.iconX + Self.iconSize + Self.textGap + textWidth)
    }

    func render(snapshot: CodexUsageSnapshot?, hasError: Bool) {
        if let snapshot, snapshot.rateLimitsAvailable {
            primaryText = "5h \(Formatters.percent(snapshot.primary.remainingPercent))%"
            secondaryText = "7d \(Formatters.percent(snapshot.secondary.remainingPercent))%"
            textColor = hasError ? .systemOrange : Self.colorForRemaining(snapshot.primary.remainingPercent)
            iconColor = hasError ? .systemOrange : .white.withAlphaComponent(0.92)
        } else {
            primaryText = "5h --%"
            secondaryText = "7d --%"
            textColor = hasError ? .systemOrange : .secondaryLabelColor
            iconColor = hasError ? .systemOrange : .white.withAlphaComponent(0.75)
        }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let iconRect = NSRect(
            x: Self.iconX,
            y: (bounds.height - Self.iconSize) / 2,
            width: Self.iconSize,
            height: Self.iconSize
        )
        drawStatusIcon(in: iconRect)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byClipping
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.shadowBlurRadius = 0
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph,
            .shadow: shadow
        ]
        let lineHeight: CGFloat = 10
        let totalHeight = lineHeight * 2
        let top = max(1, floor((bounds.height - totalHeight) / 2))
        let textX = iconRect.maxX + Self.textGap
        let rect = NSRect(x: textX, y: top, width: bounds.width - textX, height: lineHeight)
        primaryText.draw(in: rect, withAttributes: attributes)
        secondaryText.draw(in: rect.offsetBy(dx: 0, dy: lineHeight), withAttributes: attributes)
    }

    private static func textWidth(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private func drawStatusIcon(in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.shadowBlurRadius = 0
        shadow.set()

        iconColor.setStroke()
        iconColor.setFill()

        let codexRing = NSBezierPath()
        codexRing.lineWidth = 2.05
        codexRing.lineCapStyle = .round
        codexRing.appendArc(withCenter: .zero, radius: 6.25, startAngle: 42, endAngle: 318, clockwise: false)

        let balanceArc = NSBezierPath()
        balanceArc.lineWidth = 1.8
        balanceArc.lineCapStyle = .round
        balanceArc.appendArc(withCenter: .zero, radius: 3.75, startAngle: 128, endAngle: 252, clockwise: false)

        let refreshTick = NSBezierPath()
        refreshTick.lineWidth = 1.7
        refreshTick.lineCapStyle = .round
        refreshTick.move(to: NSPoint(x: 3.2, y: -4.7))
        refreshTick.line(to: NSPoint(x: 5.8, y: -4.2))
        refreshTick.line(to: NSPoint(x: 5.1, y: -1.8))

        let centerDot = NSBezierPath(ovalIn: NSRect(x: -1.05, y: -1.05, width: 2.1, height: 2.1))
        let strokedPaths = [codexRing, balanceArc, refreshTick]
        let filledPaths = [centerDot]
        let iconBounds = Self.unionBounds(of: strokedPaths + filledPaths)
        let transform = AffineTransform(
            translationByX: rect.midX - iconBounds.midX,
            byY: rect.midY - iconBounds.midY
        )

        for path in strokedPaths {
            path.transform(using: transform)
            path.stroke()
        }
        for path in filledPaths {
            path.transform(using: transform)
            path.fill()
        }
    }

    private static func unionBounds(of paths: [NSBezierPath]) -> NSRect {
        paths.reduce(NSRect.null) { partial, path in
            partial.union(path.bounds)
        }
    }

    private static func colorForRemaining(_ remaining: Double) -> NSColor {
        switch remaining {
        case ..<10: .systemRed
        case ..<25: .systemOrange
        default: .labelColor
        }
    }
}

private final class UsageViewController: NSViewController {
    private let stack = NSStackView()
    private let titleLabel = NSTextField(labelWithString: "Codex Usage")
    private let primaryBar = UsageBar(label: "5h remaining")
    private let secondaryBar = UsageBar(label: "7d remaining")
    private let details = NSTextField(labelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private let quitButton = NSButton(title: "Quit", target: nil, action: #selector(NSApplication.terminate(_:)))

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 292, height: 302))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        details.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        details.textColor = .labelColor
        details.maximumNumberOfLines = 6
        status.font = .systemFont(ofSize: 11, weight: .regular)
        status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 2
        quitButton.bezelStyle = .rounded

        [titleLabel, primaryBar, secondaryBar, details, status, quitButton].forEach(stack.addArrangedSubview)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -14),
            primaryBar.widthAnchor.constraint(equalTo: stack.widthAnchor),
            secondaryBar.widthAnchor.constraint(equalTo: stack.widthAnchor),
            details.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    func render(snapshot: CodexUsageSnapshot?, error: Error?, nextRefresh: Date) {
        let hasRateLimits = snapshot?.rateLimitsAvailable == true
        primaryBar.render(remaining: hasRateLimits ? snapshot?.primary.remainingPercent : nil)
        secondaryBar.render(remaining: hasRateLimits ? snapshot?.secondary.remainingPercent : nil)

        let primaryReset = hasRateLimits ? snapshot?.primary.resetsAt.map { Formatters.dateTime.string(from: $0) } ?? "-" : "-"
        let secondaryReset = hasRateLimits ? snapshot?.secondary.resetsAt.map { Formatters.dateTime.string(from: $0) } ?? "-" : "-"
        let updated = snapshot?.lastUpdated.map { Formatters.time.string(from: $0) } ?? "-"
        let account = snapshot?.accountLabel ?? "Unknown"
        let todayTokens = snapshot.map { Formatters.number.string(from: NSNumber(value: $0.todayTokens)) ?? "\($0.todayTokens)" } ?? "-"
        let totalTokens = snapshot.map { Formatters.number.string(from: NSNumber(value: $0.totalTokens)) ?? "\($0.totalTokens)" } ?? "-"
        details.stringValue = """
        Account: \(account)
        5h reset: \(primaryReset)
        7d reset: \(secondaryReset)
        Today tokens: \(todayTokens)
        Total in thread: \(totalTokens)
        Last event: \(updated)
        Plan: \(snapshot?.planType ?? "-")
        """

        if let error {
            status.stringValue = "Status: \(error.localizedDescription)"
            status.textColor = .systemOrange
        } else {
            status.stringValue = "Refresh: \(Formatters.time.string(from: nextRefresh))"
            status.textColor = .secondaryLabelColor
        }
    }
}

private final class UsageBar: NSView {
    private let labelField = NSTextField(labelWithString: "")
    private let valueField = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()

    init(label: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        labelField.stringValue = label
        labelField.font = .systemFont(ofSize: 11, weight: .regular)
        labelField.textColor = .secondaryLabelColor
        valueField.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        valueField.alignment = .right
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 100
        bar.controlSize = .small

        [labelField, valueField, bar].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            labelField.leadingAnchor.constraint(equalTo: leadingAnchor),
            labelField.topAnchor.constraint(equalTo: topAnchor),
            valueField.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueField.firstBaselineAnchor.constraint(equalTo: labelField.firstBaselineAnchor),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.topAnchor.constraint(equalTo: labelField.bottomAnchor, constant: 5)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func render(remaining: Double?) {
        guard let remaining else {
            valueField.stringValue = "--%"
            bar.doubleValue = 0
            valueField.textColor = .secondaryLabelColor
            return
        }

        valueField.stringValue = "\(Formatters.percent(remaining))%"
        bar.doubleValue = max(0, min(100, remaining))
        valueField.textColor = switch remaining {
        case ..<10: .systemRed
        case ..<25: .systemOrange
        default: .labelColor
        }
    }
}

private enum Formatters {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static let number: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    static func percent(_ value: Double) -> Int {
        let clamped = max(0, min(100, value))
        if clamped >= 100 {
            return 100
        }
        return Int(clamped.rounded(.down))
    }
}

@main
struct CodexUsageBarMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let controller = UsageApp()
        withExtendedLifetime(controller) {
            app.run()
        }
    }
}
