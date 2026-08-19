import UIKit
import PDFKit

enum PDFSignatureService {
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

    /// Writes a new PDF with signatures flattened into page content.
    /// Stamp annotations are not used: PDFKit draws them twice on save, once upside down.
    static func writeTemporaryPDF(
        _ document: PDFDocument,
        signatures: [PlacedSignature],
        suggestedName: String
    ) throws -> URL {
        let safe = suggestedName
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (safe.isEmpty ? "signed" : safe) + "-signed.pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw writeError
        }

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let pdfKitBox = page.bounds(for: .mediaBox)
            var pageBox = CGRect(origin: .zero, size: pdfKitBox.size)
            context.beginPage(mediaBox: &pageBox)
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(pageBox)

            context.saveGState()
            context.translateBy(x: -pdfKitBox.minX, y: -pdfKitBox.minY)
            drawOriginalPage(page, in: context, displayBox: pdfKitBox)
            for signature in signatures where signature.pageIndex == index {
                drawSignature(signature, in: context, pageHeight: pdfKitBox.height)
            }
            context.restoreGState()
            context.endPage()
        }

        context.closePDF()
        return url
    }

    private static var writeError: NSError {
        NSError(
            domain: "Signer",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: String(localized: "Couldn’t write the PDF.")]
        )
    }

    private static func drawOriginalPage(_ page: PDFPage, in context: CGContext, displayBox: CGRect) {
        guard let cgPage = page.pageRef else { return }
        let rotation = ((page.rotation % 360) + 360) % 360
        let sourceBox = cgPage.getBoxRect(.mediaBox)

        context.saveGState()
        context.translateBy(x: displayBox.minX, y: displayBox.minY)
        switch rotation {
        case 90:
            context.translateBy(x: displayBox.width, y: 0)
            context.rotate(by: .pi / 2)
        case 180:
            context.translateBy(x: displayBox.width, y: displayBox.height)
            context.rotate(by: .pi)
        case 270:
            context.translateBy(x: 0, y: displayBox.height)
            context.rotate(by: 3 * .pi / 2)
        default:
            break
        }
        context.translateBy(x: -sourceBox.minX, y: -sourceBox.minY)
        context.drawPDFPage(cgPage)
        context.restoreGState()
    }

    private static func drawSignature(_ signature: PlacedSignature, in context: CGContext, pageHeight: CGFloat) {
        let rect = signature.rect
        context.saveGState()
        // Flip the entire context to UIKit top-left-origin so UIImage.draw works correctly.
        context.translateBy(x: 0, y: pageHeight)
        context.scaleBy(x: 1, y: -1)
        let flippedRect = CGRect(x: rect.minX, y: pageHeight - rect.maxY, width: rect.width, height: rect.height)
        UIGraphicsPushContext(context)
        signature.image.draw(in: flippedRect)
        UIGraphicsPopContext()
        context.restoreGState()
    }
}
