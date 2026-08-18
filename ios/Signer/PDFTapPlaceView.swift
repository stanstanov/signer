import SwiftUI
import PDFKit

struct PlacedSignature: Identifiable {
    let id: UUID
    var pageIndex: Int
    var rect: CGRect
    var image: UIImage

    init(id: UUID = UUID(), pageIndex: Int, rect: CGRect, image: UIImage) {
        self.id = id
        self.pageIndex = pageIndex
        self.rect = rect
        self.image = image
    }
}

/// PDF viewer: tap places a signature; overlays let you drag each one with a finger.
struct PDFTapPlaceView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var currentPageIndex: Int
    var hasSignature: Bool
    var placedSignatures: [PlacedSignature]
    var onPlace: (_ pageIndex: Int, _ pointInPage: CGPoint) -> Void
    var onDragEnd: (_ id: UUID, _ pageIndex: Int, _ rect: CGRect) -> Void
    var onSignatureTap: (_ id: UUID) -> Void

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .secondarySystemBackground
        pdfView.document = document
        if currentPageIndex < document.pageCount,
           let page = document.page(at: currentPageIndex) {
            pdfView.go(to: page)
        } else {
            pdfView.goToFirstPage(nil)
        }

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.numberOfTapsRequired = 1
        tap.delegate = context.coordinator
        pdfView.addGestureRecognizer(tap)

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.layoutDidChange(_:)),
            name: .PDFViewScaleChanged,
            object: pdfView
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.layoutDidChange(_:)),
            name: .PDFViewVisiblePagesChanged,
            object: pdfView
        )

        context.coordinator.pdfView = pdfView
        context.coordinator.syncOverlays()
        DispatchQueue.main.async {
            context.coordinator.syncOverlays()
        }
        return pdfView
    }

    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        coordinator.removeAllOverlays()
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        context.coordinator.hasSignature = hasSignature
        context.coordinator.onPlace = onPlace
        context.coordinator.onDragEnd = onDragEnd
        context.coordinator.onSignatureTap = onSignatureTap
        context.coordinator.currentPageIndex = $currentPageIndex
        context.coordinator.placedSignatures = placedSignatures
        context.coordinator.pdfView = pdfView

        if pdfView.document !== document {
            let pageIndex = currentPageIndex
            pdfView.document = document
            if pageIndex < document.pageCount, let page = document.page(at: pageIndex) {
                pdfView.go(to: page)
            }
            pdfView.layoutDocumentView()
        }

        if context.coordinator.draggingID == nil {
            context.coordinator.syncOverlays()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            currentPageIndex: $currentPageIndex,
            hasSignature: hasSignature,
            placedSignatures: placedSignatures,
            onPlace: onPlace,
            onDragEnd: onDragEnd,
            onSignatureTap: onSignatureTap
        )
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var currentPageIndex: Binding<Int>
        var hasSignature: Bool
        var placedSignatures: [PlacedSignature]
        var onPlace: (_ pageIndex: Int, _ pointInPage: CGPoint) -> Void
        var onDragEnd: (_ id: UUID, _ pageIndex: Int, _ rect: CGRect) -> Void
        var onSignatureTap: (_ id: UUID) -> Void
        weak var pdfView: PDFView?
        var draggingID: UUID?

        private var overlays: [UUID: SignatureOverlayView] = [:]
        private let haptics = UIImpactFeedbackGenerator(style: .light)

        init(
            currentPageIndex: Binding<Int>,
            hasSignature: Bool,
            placedSignatures: [PlacedSignature],
            onPlace: @escaping (_ pageIndex: Int, _ pointInPage: CGPoint) -> Void,
            onDragEnd: @escaping (_ id: UUID, _ pageIndex: Int, _ rect: CGRect) -> Void,
            onSignatureTap: @escaping (_ id: UUID) -> Void
        ) {
            self.currentPageIndex = currentPageIndex
            self.hasSignature = hasSignature
            self.placedSignatures = placedSignatures
            self.onPlace = onPlace
            self.onDragEnd = onDragEnd
            self.onSignatureTap = onSignatureTap
            super.init()
            haptics.prepare()
        }

        @objc func pageChanged(_ note: Notification) {
            guard let pdfView = note.object as? PDFView,
                  let page = pdfView.currentPage,
                  let document = pdfView.document else { return }
            let index = document.index(for: page)
            if index != NSNotFound {
                currentPageIndex.wrappedValue = index
            }
            if draggingID == nil {
                syncOverlays()
            }
        }

        @objc func layoutDidChange(_ note: Notification) {
            if draggingID == nil {
                syncOverlays()
            }
        }

        func removeAllOverlays() {
            overlays.values.forEach { $0.removeFromSuperview() }
            overlays.removeAll()
        }

        func syncOverlays() {
            guard let pdfView,
                  let document = pdfView.document,
                  let documentView = pdfView.documentView else {
                removeAllOverlays()
                return
            }

            let activeIDs = Set(placedSignatures.map(\.id))
            for (id, overlay) in overlays where !activeIDs.contains(id) {
                overlay.removeFromSuperview()
                overlays.removeValue(forKey: id)
            }

            for placed in placedSignatures {
                if placed.id == draggingID { continue }
                guard placed.pageIndex < document.pageCount,
                      let page = document.page(at: placed.pageIndex) else { continue }

                let overlay = overlays[placed.id] ?? makeOverlay(id: placed.id)
                if overlay.superview !== documentView {
                    overlay.removeFromSuperview()
                    documentView.addSubview(overlay)
                }
                overlay.image = placed.image

                let rectInPDF = pdfView.convert(placed.rect, from: page)
                let rectInDocument = documentView.convert(rectInPDF, from: pdfView)
                overlay.layoutForSignatureFrame(rectInDocument)
            }

            for placed in placedSignatures {
                if let overlay = overlays[placed.id] {
                    documentView.bringSubviewToFront(overlay)
                }
            }
        }

        private func makeOverlay(id: UUID) -> SignatureOverlayView {
            let overlay = SignatureOverlayView()
            overlay.signatureID = id
            overlay.isUserInteractionEnabled = true
            overlay.isExclusiveTouch = true
            overlay.accessibilityLabel = String(localized: "Signature")
            overlay.accessibilityHint = String(localized: "Drag to move. Tap for the menu.")
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleOverlayPan(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            overlay.addGestureRecognizer(pan)
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleOverlayTap(_:)))
            tap.numberOfTapsRequired = 1
            tap.delegate = self
            overlay.addGestureRecognizer(tap)
            overlays[id] = overlay
            return overlay
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard hasSignature else { return }
            guard let pdfView,
                  let document = pdfView.document else { return }

            let viewPoint = gesture.location(in: pdfView)
            guard let page = pdfView.page(for: viewPoint, nearest: false) else { return }

            let pagePoint = pdfView.convert(viewPoint, to: page)
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.contains(pagePoint) else { return }

            let index = document.index(for: page)
            guard index != NSNotFound else { return }
            playHaptic()
            onPlace(index, pagePoint)
        }

        @objc func handleOverlayTap(_ gesture: UITapGestureRecognizer) {
            guard let overlay = gesture.view as? SignatureOverlayView else { return }
            playHaptic()
            onSignatureTap(overlay.signatureID)
        }

        @objc func handleOverlayPan(_ gesture: UIPanGestureRecognizer) {
            guard let overlay = gesture.view as? SignatureOverlayView,
                  let pdfView,
                  let documentView = overlay.superview else { return }

            switch gesture.state {
            case .began:
                draggingID = overlay.signatureID
                overlay.setDragging(true)
                overlay.superview?.bringSubviewToFront(overlay)
                playHaptic()
                if let scroll = findScrollView(in: pdfView) {
                    scroll.setContentOffset(scroll.contentOffset, animated: false)
                    scroll.isScrollEnabled = false
                }

            case .changed:
                let translation = gesture.translation(in: documentView)
                overlay.center = CGPoint(
                    x: overlay.center.x + translation.x,
                    y: overlay.center.y + translation.y
                )
                gesture.setTranslation(.zero, in: documentView)

            case .ended, .cancelled:
                findScrollView(in: pdfView)?.isScrollEnabled = true
                overlay.setDragging(false)
                playHaptic()
                commitOverlayPosition(overlay)
                draggingID = nil

            case .failed:
                findScrollView(in: pdfView)?.isScrollEnabled = true
                overlay.setDragging(false)
                commitOverlayPosition(overlay)
                draggingID = nil

            default:
                break
            }
        }

        private func playHaptic() {
            haptics.impactOccurred(intensity: 0.8)
            haptics.prepare()
        }

        private func commitOverlayPosition(_ overlay: SignatureOverlayView) {
            guard let pdfView,
                  let document = pdfView.document,
                  let documentView = overlay.superview,
                  let placed = placedSignatures.first(where: { $0.id == overlay.signatureID }) else {
                syncOverlays()
                return
            }

            let signatureFrame = overlay.signatureFrameInSuperview
            let frameInPDFView = pdfView.convert(signatureFrame, from: documentView)
            let centerInPDF = CGPoint(x: frameInPDFView.midX, y: frameInPDFView.midY)
            guard let page = pdfView.page(for: centerInPDF, nearest: true) else {
                syncOverlays()
                return
            }

            var rect = pdfView.convert(frameInPDFView, to: page)
            rect.size = placed.rect.size
            rect = PDFSignatureService.clamp(rect, to: page.bounds(for: .mediaBox))

            let index = document.index(for: page)
            guard index != NSNotFound else {
                syncOverlays()
                return
            }
            onDragEnd(placed.id, index, rect)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if gestureRecognizer.view is PDFView, gestureRecognizer is UITapGestureRecognizer {
                if let view = touch.view, overlays.values.contains(where: { view === $0 || view.isDescendant(of: $0) }) {
                    return false
                }
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            false
        }

        private func findScrollView(in view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView { return scroll }
            for subview in view.subviews {
                if let scroll = findScrollView(in: subview) { return scroll }
            }
            return nil
        }
    }
}

/// Larger hit target around the stamp so it is easy to grab with a finger.
final class SignatureOverlayView: UIView {
    static let hitPadding: CGFloat = 18

    var signatureID = UUID()

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleToFill
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.22
        view.layer.shadowRadius = 3
        view.layer.shadowOffset = CGSize(width: 0, height: 1)
        return view
    }()

    var image: UIImage? {
        get { imageView.image }
        set { imageView.image = newValue }
    }

    var signatureFrameInSuperview: CGRect {
        imageView.convert(imageView.bounds, to: superview)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func layoutForSignatureFrame(_ frame: CGRect) {
        self.frame = frame.insetBy(dx: -Self.hitPadding, dy: -Self.hitPadding)
        imageView.frame = bounds.insetBy(dx: Self.hitPadding, dy: Self.hitPadding)
    }

    func setDragging(_ dragging: Bool) {
        imageView.alpha = dragging ? 0.88 : 1
        imageView.layer.shadowOpacity = dragging ? 0.4 : 0.22
        imageView.layer.shadowRadius = dragging ? 8 : 3
    }
}
