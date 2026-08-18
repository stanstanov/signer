import SwiftUI
import PDFKit
import UniformTypeIdentifiers

/// Flow: open PDF → draw signature → tap page to place → export signed PDF.
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
    /// Bumps so PDFView reloads after replace (annotation remove needs a hard refresh).
    @State private var documentRevision = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let document {
                    PDFTapPlaceView(
                        document: document,
                        documentRevision: documentRevision,
                        currentPageIndex: $currentPageIndex,
                        hasSignature: signatureImage != nil,
                        onPlace: placeSignature
                    )
                    .id(documentRevision)
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
                        statusMessage = "Подпись готова. Коснитесь PDF, куда её поставить."
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
                documentRevision = 0
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
        rect.origin.x = max(pageBounds.minX, min(rect.origin.x, pageBounds.maxX - rect.width))
        rect.origin.y = max(pageBounds.minY, min(rect.origin.y, pageBounds.maxY - rect.height))

        PDFSignatureService.addSignature(signatureImage, to: page, in: document, rect: rect)
        documentRevision &+= 1
        statusMessage = "Подпись на стр. \(pageIndex + 1). Новый тап перенесёт её; затем сохраните."
    }

    private func exportPDF() {
        guard let document else { return }
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
