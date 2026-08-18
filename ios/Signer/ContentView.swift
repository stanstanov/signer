import SwiftUI
import PDFKit
import UniformTypeIdentifiers

/// Flow: open PDF → draw signature → tap page to place → drag to adjust → export signed PDF.
struct ContentView: View {
    @State private var pdfURL: URL?
    @State private var document: PDFDocument?
    @State private var signatureImage: UIImage?
    @State private var showImporter = false
    @State private var showSignaturePad = false
    @State private var showShare = false
    @State private var exportedURL: URL?
    @State private var statusMessage = "Откройте PDF, нарисуйте подпись и коснитесь места на странице."
    @State private var currentPageIndex = 0
    @State private var errorMessage: String?
    @State private var placedSignature: PlacedSignature?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let document {
                    PDFTapPlaceView(
                        document: document,
                        currentPageIndex: $currentPageIndex,
                        hasSignature: signatureImage != nil,
                        placedSignature: placedSignature,
                        onPlace: placeSignature,
                        onDragEnd: moveSignature
                    )
                } else {
                    ContentUnavailableView(
                        "Нет PDF",
                        systemImage: "doc.richtext",
                        description: Text("Нажмите «Открыть PDF», чтобы начать.")
                    )
                }

                statusBar
            }
            .navigationTitle("Signer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .sheet(isPresented: $showSignaturePad) {
                SignaturePadSheet(
                    onSave: { image in
                        signatureImage = image
                        if var placed = placedSignature {
                            placed.image = image
                            placed.rect.size.height = placed.rect.width * image.size.height / max(image.size.width, 1)
                            if let page = document?.page(at: placed.pageIndex) {
                                placed.rect = PDFSignatureService.clamp(placed.rect, to: page.bounds(for: .mediaBox))
                            }
                            placedSignature = placed
                            statusMessage = "Подпись обновлена. Перетащите пальцем или коснитесь другого места."
                        } else {
                            statusMessage = "Подпись готова. Коснитесь PDF, куда её поставить."
                        }
                        showSignaturePad = false
                    },
                    onCancel: { showSignaturePad = false }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showShare) {
                if let exportedURL {
                    ShareSheet(urls: [exportedURL])
                }
            }
            .alert("Ошибка", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if signatureImage != nil {
                HStack(spacing: 12) {
                    Text("Превью подписи")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(uiImage: signatureImage!)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 36)
                        .padding(4)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Spacer()
                    Button("Перерисовать") { showSignaturePad = true }
                        .font(.caption)
                }
            }
        }
        .padding(12)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Открыть PDF") { showImporter = true }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("Подпись") { showSignaturePad = true }
                .disabled(document == nil)
            Button("Сохранить") { exportPDF() }
                .disabled(document == nil)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                guard let doc = PDFDocument(data: data) else {
                    errorMessage = "Не удалось прочитать PDF."
                    return
                }
                pdfURL = url
                document = doc
                currentPageIndex = 0
                signatureImage = nil
                placedSignature = nil
                PDFSignatureService.clearLastSignatureReference()
                statusMessage = "PDF загружен. Нарисуйте подпись, затем коснитесь места на странице."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// `pointInPage` is in PDF page coordinates (bottom-left origin).
    private func placeSignature(pageIndex: Int, pointInPage: CGPoint) {
        guard let document, let signatureImage else {
            statusMessage = "Сначала нарисуйте подпись."
            showSignaturePad = true
            return
        }
        guard let page = document.page(at: pageIndex) else { return }

        let pageBounds = page.bounds(for: .mediaBox)
        let targetWidth = min(pageBounds.width * 0.28, 180)
        let aspect = signatureImage.size.height / max(signatureImage.size.width, 1)
        let targetHeight = targetWidth * aspect

        // Anchor: finger point = center-bottom of signature box.
        var rect = CGRect(
            x: pointInPage.x - targetWidth / 2,
            y: pointInPage.y,
            width: targetWidth,
            height: targetHeight
        )
        rect = PDFSignatureService.clamp(rect, to: pageBounds)

        placedSignature = PlacedSignature(pageIndex: pageIndex, rect: rect, image: signatureImage)
        statusMessage = "Подпись на стр. \(pageIndex + 1). Перетащите пальцем или коснитесь другого места."
    }

    private func moveSignature(pageIndex: Int, rect: CGRect) {
        guard var placed = placedSignature else { return }
        guard let document, let page = document.page(at: pageIndex) else { return }
        placed.pageIndex = pageIndex
        placed.rect = PDFSignatureService.clamp(rect, to: page.bounds(for: .mediaBox))
        placedSignature = placed
        statusMessage = "Подпись на стр. \(pageIndex + 1). Перетащите пальцем или коснитесь другого места."
    }

    private func exportPDF() {
        guard let document else { return }
        if let placed = placedSignature, let page = document.page(at: placed.pageIndex) {
            PDFSignatureService.addSignature(placed.image, to: page, in: document, rect: placed.rect)
        }
        defer { PDFSignatureService.removeAllSignatures(from: document) }
        do {
            let url = try PDFSignatureService.writeTemporaryPDF(document, suggestedName: pdfURL?.deletingPathExtension().lastPathComponent ?? "signed")
            exportedURL = url
            showShare = true
            statusMessage = "Готово — выберите, куда сохранить подписанный PDF."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Share

private struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
