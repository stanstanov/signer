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

    /// Stamps every signature into the document (page coordinates, bottom-left origin).
    /// Replaces any previous signature stamps we placed.
    static func stampSignatures(_ signatures: [PlacedSignature], in document: PDFDocument) {
        removeAllSignatures(from: document)
        for signature in signatures {
            guard let page = document.page(at: signature.pageIndex),
                  let cgImage = signature.image.cgImage else { continue }
            let annotation = PDFImageAnnotation(image: cgImage, bounds: signature.rect)
            annotation.userName = signatureMarker
            annotation.contents = signatureMarker
            page.addAnnotation(annotation)
            lastSignatureAnnotation = annotation
        }
    }

    static func clearLastSignatureReference() {
        lastSignatureAnnotation = nil
    }

    static func clamp(_ rect: CGRect, to pageBounds: CGRect) -> CGRect {
        var r = rect
        if r.width > pageBounds.width {
            r.size.width = pageBounds.width
            r.origin.x = pageBounds.minX
        } else {
            r.origin.x = max(pageBounds.minX, min(r.origin.x, pageBounds.maxX - r.width))
        }
        if r.height > pageBounds.height {
            r.size.height = pageBounds.height
            r.origin.y = pageBounds.minY
        } else {
            r.origin.y = max(pageBounds.minY, min(r.origin.y, pageBounds.maxY - r.height))
        }
        return r
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
