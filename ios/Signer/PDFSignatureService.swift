import UIKit
import PDFKit

enum PDFSignatureService {
    /// Marker so we can find stamps even if PDFKit drops our subclass type.
    static let signatureMarker = "signer.app.signature"

    private static weak var lastSignatureAnnotation: PDFAnnotation?

    /// Removes every stamp we placed from all pages.
    static func removeAllSignatures(from document: PDFDocument) {
        if let last = lastSignatureAnnotation {
            last.page?.removeAnnotation(last)
            lastSignatureAnnotation = nil
        }

        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            // Copy array — mutating while iterating is unsafe.
            let annotations = page.annotations
            for annotation in annotations where isOurSignature(annotation) {
                page.removeAnnotation(annotation)
            }
        }
    }

    private static func isOurSignature(_ annotation: PDFAnnotation) -> Bool {
        if annotation is PDFImageAnnotation { return true }
        if annotation.userName == signatureMarker { return true }
        if annotation.contents == signatureMarker { return true }
        return false
    }

    /// Stamps `image` into `rect` on the PDF page (page coordinates, bottom-left origin).
    /// Replaces any previous signature stamps in the document.
    static func addSignature(_ image: UIImage, to page: PDFPage, in document: PDFDocument, rect: CGRect) {
        guard let cgImage = image.cgImage else { return }
        removeAllSignatures(from: document)

        let annotation = PDFImageAnnotation(image: cgImage, bounds: rect)
        annotation.userName = signatureMarker
        annotation.contents = signatureMarker
        page.addAnnotation(annotation)
        lastSignatureAnnotation = annotation
    }

    static func clearLastSignatureReference() {
        lastSignatureAnnotation = nil
    }

    static func writeTemporaryPDF(_ document: PDFDocument, suggestedName: String) throws -> URL {
        let safe = suggestedName
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (safe.isEmpty ? "signed" : safe) + "-signed.pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        guard document.write(to: url) else {
            throw NSError(
                domain: "Signer",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Не удалось записать PDF."]
            )
        }
        return url
    }
}

/// PDFKit has no public image annotation — custom stamp drawing.
final class PDFImageAnnotation: PDFAnnotation {
    private let cgImage: CGImage

    init(image: CGImage, bounds: CGRect) {
        self.cgImage = image
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
        userName = PDFSignatureService.signatureMarker
        contents = PDFSignatureService.signatureMarker
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        UIGraphicsPushContext(context)
        context.saveGState()
        // PDFKit draws with flipped coordinates relative to UIKit images.
        context.translateBy(x: bounds.origin.x, y: bounds.origin.y + bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(origin: .zero, size: bounds.size))
        context.restoreGState()
        UIGraphicsPopContext()
    }
}
