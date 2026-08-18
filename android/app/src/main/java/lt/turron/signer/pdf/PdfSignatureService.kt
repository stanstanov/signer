package lt.turron.signer.pdf

import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.graphics.image.LosslessFactory
import lt.turron.signer.PlacedSignature
import java.io.File

object PdfSignatureService {
    fun stamp(
        source: File,
        destination: File,
        signatures: List<PlacedSignature>,
    ) {
        PDDocument.load(source).use { document ->
            signatures.forEach { signature ->
                if (signature.pageIndex !in 0 until document.numberOfPages) return@forEach
                val page = document.getPage(signature.pageIndex)
                val image = LosslessFactory.createFromImage(document, signature.image)
                PDPageContentStream(
                    document,
                    page,
                    PDPageContentStream.AppendMode.APPEND,
                    true,
                    true,
                ).use { stream ->
                    stream.drawImage(
                        image,
                        signature.left,
                        signature.bottom,
                        signature.width,
                        signature.height,
                    )
                }
            }
            if (destination.exists()) destination.delete()
            document.save(destination)
        }
    }

    fun pageSize(file: File, pageIndex: Int): Pair<Float, Float>? {
        PDDocument.load(file).use { document ->
            if (pageIndex !in 0 until document.numberOfPages) return null
            val box = document.getPage(pageIndex).mediaBox
            return box.width to box.height
        }
    }
}
