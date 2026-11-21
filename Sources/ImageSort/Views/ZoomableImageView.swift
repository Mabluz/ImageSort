import SwiftUI
import AppKit

enum ZoomAction: Equatable { case zoomIn, zoomOut, fit, actualSize }

struct ZoomCommand: Equatable {
    var action: ZoomAction
    var id = UUID()
}

/// NSScrollView-basert bildevisning med knip-zoom, scroll/panorering og dobbeltklikk for 100 %.
/// Zoom og posisjon beholdes når man bytter til et bilde med samme størrelse (bildeserier),
/// så man kan sammenligne samme område i flere bilder.
struct ZoomableImageView: NSViewRepresentable {
    let image: NSImage?
    /// Bildets egentlige pikselstørrelse (også når `image` er en forhåndsvisning).
    let pixelSize: CGSize?
    let command: ZoomCommand?
    var onZoomChange: (CGFloat) -> Void = { _ in }

    func makeNSView(context: Context) -> ZoomScrollView {
        let v = ZoomScrollView()
        v.onZoomChange = onZoomChange
        return v
    }

    func updateNSView(_ v: ZoomScrollView, context: Context) {
        v.onZoomChange = onZoomChange
        v.show(image: image, pixelSize: pixelSize)
        if let command, command != v.lastCommand {
            v.lastCommand = command
            v.perform(command.action)
        }
    }
}

final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposed: NSRect) -> NSRect {
        var r = super.constrainBoundsRect(proposed)
        guard let doc = documentView else { return r }
        if r.width > doc.frame.width { r.origin.x = (doc.frame.width - r.width) / 2 }
        if r.height > doc.frame.height { r.origin.y = (doc.frame.height - r.height) / 2 }
        return r
    }
}

final class ZoomScrollView: NSScrollView {
    private let imageView = NSImageView()
    private var docSize: CGSize = .zero
    private var fitMode = true
    var lastCommand: ZoomCommand?
    var onZoomChange: (CGFloat) -> Void = { _ in }

    init() {
        super.init(frame: .zero)
        contentView = CenteringClipView()
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        allowsMagnification = true
        backgroundColor = .black
        drawsBackground = true
        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageAlignment = .alignCenter
        documentView = imageView

        let dbl = NSClickGestureRecognizer(target: self, action: #selector(doubleClicked(_:)))
        dbl.numberOfClicksRequired = 2
        imageView.addGestureRecognizer(dbl)

        NotificationCenter.default.addObserver(self, selector: #selector(userMagnified),
                                               name: NSScrollView.didEndLiveMagnifyNotification, object: self)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var backingScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    func show(image: NSImage?, pixelSize: CGSize?) {
        if imageView.image !== image { imageView.image = image }
        guard let px = pixelSize ?? image.map({ CGSize(width: $0.size.width, height: $0.size.height) }) else { return }
        // 100 % = én bildepiksel per skjermpiksel.
        let newSize = CGSize(width: px.width / backingScale, height: px.height / backingScale)
        if newSize != docSize {
            docSize = newSize
            imageView.frame = CGRect(origin: .zero, size: newSize)
            fitMode = true
            fit()
        }
    }

    private var fitMagnification: CGFloat {
        let clip = contentView.bounds.size.applying(.init(scaleX: magnification, y: magnification))
        guard docSize.width > 0, docSize.height > 0, clip.width > 0 else { return 1 }
        return min(clip.width / docSize.width, clip.height / docSize.height)
    }

    private func updateLimits() {
        minMagnification = max(0.02, min(fitMagnification, 1) * 0.5)
        maxMagnification = 8
    }

    func fit() {
        updateLimits()
        fitMode = true
        magnification = fitMagnification
        report()
    }

    func perform(_ action: ZoomAction) {
        updateLimits()
        let center = NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        switch action {
        case .fit: fit(); return
        case .actualSize: setMagnification(1, centeredAt: center)
        case .zoomIn: setMagnification(min(maxMagnification, magnification * 1.5), centeredAt: center)
        case .zoomOut: setMagnification(max(minMagnification, magnification / 1.5), centeredAt: center)
        }
        fitMode = false
        report()
    }

    @objc private func doubleClicked(_ g: NSClickGestureRecognizer) {
        updateLimits()
        if fitMode || abs(magnification - fitMagnification) < 0.01 {
            setMagnification(1, centeredAt: g.location(in: imageView))
            fitMode = false
            report()
        } else {
            fit()
        }
    }

    @objc private func userMagnified() {
        fitMode = false
        report()
    }

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        report()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if fitMode { fit() } else { updateLimits() }
    }

    private func report() {
        let m = magnification
        DispatchQueue.main.async { [weak self] in self?.onZoomChange(m) }
    }
}
