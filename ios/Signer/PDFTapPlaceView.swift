import SwiftUI
import PDFKit

/// PDF viewer: tap places the signature at the finger location on the current page.
struct PDFTapPlaceView: UIViewRepresentable {
    let document: PDFDocument
    /// Increment after annotation changes so the preview reloads (PDFView caches stamp drawing).
    var documentRevision: Int
    @Binding var currentPageIndex: Int
    var hasSignature: Bool
    var onPlace: (_ pageIndex: Int, _ pointInPage: CGPoint) -> Void

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
        pdfView.addGestureRecognizer(tap)

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        context.coordinator.pdfView = pdfView
        context.coordinator.appliedRevision = documentRevision
        return pdfView
    }

    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        context.coordinator.hasSignature = hasSignature
        context.coordinator.onPlace = onPlace
        context.coordinator.currentPageIndex = $currentPageIndex

        let needsReload = pdfView.document !== document || context.coordinator.appliedRevision != documentRevision
        guard needsReload else { return }

        let pageIndex = currentPageIndex
        // Hard reload clears cached annotation drawing layers.
        pdfView.document = nil
        pdfView.document = document
        if pageIndex < document.pageCount, let page = document.page(at: pageIndex) {
            pdfView.go(to: page)
        }
        pdfView.layoutDocumentView()
        context.coordinator.appliedRevision = documentRevision
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            currentPageIndex: $currentPageIndex,
            hasSignature: hasSignature,
            onPlace: onPlace
        )
    }

    final class Coordinator: NSObject {
        var currentPageIndex: Binding<Int>
        var hasSignature: Bool
        var onPlace: (_ pageIndex: Int, _ pointInPage: CGPoint) -> Void
        weak var pdfView: PDFView?
        var appliedRevision: Int = -1

        init(
            currentPageIndex: Binding<Int>,
            hasSignature: Bool,
            onPlace: @escaping (_ pageIndex: Int, _ pointInPage: CGPoint) -> Void
        ) {
            self.currentPageIndex = currentPageIndex
            self.hasSignature = hasSignature
            self.onPlace = onPlace
        }

        @objc func pageChanged(_ note: Notification) {
            guard let pdfView = note.object as? PDFView,
                  let page = pdfView.currentPage,
                  let document = pdfView.document else { return }
            let index = document.index(for: page)
            if index != NSNotFound {
                currentPageIndex.wrappedValue = index
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard hasSignature else { return }
            guard let pdfView,
                  let page = pdfView.currentPage,
                  let document = pdfView.document else { return }

            let viewPoint = gesture.location(in: pdfView)
            let pagePoint = pdfView.convert(viewPoint, to: page)
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.contains(pagePoint) else { return }

            let index = document.index(for: page)
            guard index != NSNotFound else { return }
            onPlace(index, pagePoint)
        }
    }
}
