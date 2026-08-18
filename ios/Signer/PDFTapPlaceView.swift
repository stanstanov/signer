import SwiftUI
import PDFKit

struct PlacedSignature {
    var pageIndex: Int
    var rect: CGRect
    var image: UIImage
}

/// PDF viewer: tap places the signature; an overlay lets you drag it with a finger.
struct PDFTapPlaceView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var currentPageIndex: Int
    var hasSignature: Bool
    var placedSignature: PlacedSignature?
    var onPlace: (_ pageIndex: Int, _ pointInPage: CGPoint) -> Void
    var onDragEnd: (_ pageIndex: Int, _ rect: CGRect) -> Void

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
        context.coordinator.syncPreview()
        DispatchQueue.main.async {
            context.coordinator.syncPreview()
        }
        return pdfView
    }

    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        coordinator.overlay.removeFromSuperview()
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        context.coordinator.hasSignature = hasSignature
        context.coordinator.onPlace = onPlace
        context.coordinator.onDragEnd = onDragEnd
        context.coordinator.currentPageIndex = $currentPageIndex
        context.coordinator.placedSignature = placedSignature
        context.coordinator.pdfView = pdfView

        if pdfView.document !== document {
            let pageIndex = currentPageIndex
            pdfView.document = document
            if pageIndex < document.pageCount, let page = document.page(at: pageIndex) {
                pdfView.go(to: page)
            }
            pdfView.layoutDocumentView()
        }

        if !context.coordinator.isDragging {
            context.coordinator.syncPreview()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            currentPageIndex: $currentPageIndex,
            hasSignature: hasSignature,
            placedSignature: placedSignature,
            onPlace: onPlace,
            onDragEnd: onDragEnd
        )
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var currentPageIndex: Binding<Int>
        var hasSignature: Bool
        var placedSignature: PlacedSignature?
        var onPlace: (_ pageIndex: Int, _ pointInPage: CGPoint) -> Void
        var onDragEnd: (_ pageIndex: Int, _ rect: CGRect) -> Void
        weak var pdfView: PDFView?
        var isDragging = false

        let overlay = SignatureOverlayView()

        init(
            currentPageIndex: Binding<Int>,
            hasSignature: Bool,
            placedSignature: PlacedSignature?,
            onPlace: @escaping (_ pageIndex: Int, _ pointInPage: CGPoint) -> Void,
            onDragEnd: @escaping (_ pageIndex: Int, _ rect: CGRect) -> Void
        ) {
            self.currentPageIndex = currentPageIndex
            self.hasSignature = hasSignature
            self.placedSignature = placedSignature
            self.onPlace = onPlace
            self.onDragEnd = onDragEnd
            super.init()

            overlay.isUserInteractionEnabled = true
            overlay.isExclusiveTouch = true
            overlay.accessibilityLabel = "Подпись"
            overlay.accessibilityHint = "Перетащите, чтобы переместить"
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleOverlayPan(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            overlay.addGestureRecognizer(pan)
        }

        @objc func pageChanged(_ note: Notification) {
            guard let pdfView = note.object as? PDFView,
                  let page = pdfView.currentPage,
                  let document = pdfView.document else { return }
            let index = document.index(for: page)
            if index != NSNotFound {
                currentPageIndex.wrappedValue = index
            }
            if !isDragging {
                syncPreview()
            }
        }

        @objc func layoutDidChange(_ note: Notification) {
            if !isDragging {
                syncPreview()
            }
        }

        func syncPreview() {
            guard let pdfView,
                  let placed = placedSignature,
                  let document = pdfView.document,
                  placed.pageIndex < document.pageCount,
                  let page = document.page(at: placed.pageIndex),
                  let documentView = pdfView.documentView else {
                overlay.removeFromSuperview()
                return
            }

            if overlay.superview !== documentView {
                overlay.removeFromSuperview()
                documentView.addSubview(overlay)
            }
            documentView.bringSubviewToFront(overlay)
            overlay.image = placed.image

            let rectInPDF = pdfView.convert(placed.rect, from: page)
            let rectInDocument = documentView.convert(rectInPDF, from: pdfView)
            overlay.layoutForSignatureFrame(rectInDocument)
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
            onPlace(index, pagePoint)
        }

        @objc func handleOverlayPan(_ gesture: UIPanGestureRecognizer) {
            guard let pdfView,
                  let documentView = overlay.superview else { return }

            switch gesture.state {
            case .began:
                isDragging = true
                overlay.setDragging(true)
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

            case .ended, .cancelled, .failed:
                findScrollView(in: pdfView)?.isScrollEnabled = true
                overlay.setDragging(false)
                commitOverlayPosition()
                isDragging = false

            default:
                break
            }
        }

        private func commitOverlayPosition() {
            guard let pdfView,
                  let document = pdfView.document,
                  let documentView = overlay.superview,
                  let placed = placedSignature else {
                syncPreview()
                return
            }

            let signatureFrame = overlay.signatureFrameInSuperview
            let frameInPDFView = pdfView.convert(signatureFrame, from: documentView)
            let centerInPDF = CGPoint(x: frameInPDFView.midX, y: frameInPDFView.midY)
            guard let page = pdfView.page(for: centerInPDF, nearest: true) else {
                syncPreview()
                return
            }

            var rect = pdfView.convert(frameInPDFView, to: page)
            rect.size = placed.rect.size
            rect = PDFSignatureService.clamp(rect, to: page.bounds(for: .mediaBox))

            let index = document.index(for: page)
            guard index != NSNotFound else {
                syncPreview()
                return
            }
            onDragEnd(index, rect)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if gestureRecognizer is UITapGestureRecognizer {
                if let view = touch.view, view === overlay || view.isDescendant(of: overlay) {
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
