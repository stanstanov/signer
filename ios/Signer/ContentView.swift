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
    @State private var placedSignatures: [PlacedSignature] = []
    @State private var allowsMultipleSignatures = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Group {
                    if let document {
                        PDFTapPlaceView(
                            document: document,
                            currentPageIndex: $currentPageIndex,
                            hasSignature: signatureImage != nil,
                            placedSignatures: placedSignatures,
                            onPlace: placeSignature,
                            onDragEnd: moveSignature
                        )
                        .ignoresSafeArea()
                    } else {
                        ContentUnavailableView(
                            "Нет PDF",
                            systemImage: "doc.richtext",
                            description: Text("Нажмите «Открыть PDF», чтобы начать.")
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                statusBar
            }
            .navigationTitle("Signer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .toolbarBackground(.hidden, for: .navigationBar)
            .statusBarHidden(true)
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .sheet(isPresented: $showSignaturePad) {
                SignaturePadSheet(
                    existingImage: signatureImage,
                    onSave: { image in
                        signatureImage = image
                        if allowsMultipleSignatures {
                            statusMessage = placedSignatures.isEmpty
                                ? "Подпись готова. Коснитесь PDF, чтобы поставить. Каждое касание добавит ещё одну."
                                : "Подпись обновлена. Коснитесь PDF, чтобы поставить ещё одну."
                        } else if var placed = placedSignatures.first {
                            placed.image = image
                            placed.rect.size.height = placed.rect.width * image.size.height / max(image.size.width, 1)
                            if let page = document?.page(at: placed.pageIndex) {
                                placed.rect = PDFSignatureService.clamp(placed.rect, to: page.bounds(for: .mediaBox))
                            }
                            placedSignatures = [placed]
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
            .sheet(isPresented: $showSettings) {
                SettingsSheet(
                    allowsMultipleSignatures: $allowsMultipleSignatures,
                    hasDocument: document != nil,
                    onClose: { showSettings = false }
                )
                .presentationDetents([.medium])
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
            .onChange(of: allowsMultipleSignatures) { _, isOn in
                applySignatureMode(isOn)
            }
        }
    }

    private var statusBar: some View {
        Text(statusMessage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .background(.ultraThinMaterial)
            .ignoresSafeArea(edges: .bottom)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Открыть PDF", systemImage: "doc") {
                showImporter = true
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Настройки", systemImage: "gearshape") {
                showSettings = true
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("Подпись", systemImage: "signature") {
                showSignaturePad = true
            }
            .disabled(document == nil)
            Button("Сохранить", systemImage: "square.and.arrow.down") {
                exportPDF()
            }
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
                placedSignatures = []
                allowsMultipleSignatures = false
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

        let placed = PlacedSignature(pageIndex: pageIndex, rect: rect, image: signatureImage)
        if allowsMultipleSignatures {
            placedSignatures.append(placed)
            statusMessage = "Подписей: \(placedSignatures.count). Коснитесь, чтобы добавить ещё; каждую можно двигать отдельно."
        } else {
            placedSignatures = [placed]
            statusMessage = "Подпись на стр. \(pageIndex + 1). Перетащите пальцем или коснитесь другого места."
        }
    }

    private func moveSignature(id: UUID, pageIndex: Int, rect: CGRect) {
        guard let index = placedSignatures.firstIndex(where: { $0.id == id }) else { return }
        guard let document, let page = document.page(at: pageIndex) else { return }
        placedSignatures[index].pageIndex = pageIndex
        placedSignatures[index].rect = PDFSignatureService.clamp(rect, to: page.bounds(for: .mediaBox))
        if allowsMultipleSignatures {
            statusMessage = "Подписей: \(placedSignatures.count). Каждую можно двигать отдельно."
        } else {
            statusMessage = "Подпись на стр. \(pageIndex + 1). Перетащите пальцем или коснитесь другого места."
        }
    }

    private func applySignatureMode(_ isOn: Bool) {
        if isOn {
            statusMessage = placedSignatures.isEmpty
                ? "Режим нескольких подписей. Коснитесь PDF, чтобы поставить."
                : "Режим нескольких подписей. Коснитесь, чтобы добавить ещё; каждую можно двигать отдельно."
        } else {
            if placedSignatures.count > 1 {
                placedSignatures = Array(placedSignatures.suffix(1))
                statusMessage = "Режим одной подписи — оставлена последняя. Перетащите или коснитесь другого места."
            } else if placedSignatures.count == 1 {
                statusMessage = "Режим одной подписи. Перетащите пальцем или коснитесь другого места."
            } else {
                statusMessage = "Режим одной подписи. Коснитесь PDF, куда поставить подпись."
            }
        }
    }

    private func exportPDF() {
        guard let document else { return }
        PDFSignatureService.stampSignatures(placedSignatures, in: document)
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

// MARK: - Settings

private struct SettingsSheet: View {
    @Binding var allowsMultipleSignatures: Bool
    var hasDocument: Bool
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Несколько подписей", isOn: $allowsMultipleSignatures)
                        .disabled(!hasDocument)
                } footer: {
                    Text(hasDocument
                         ? "В этом режиме каждое касание ставит новую подпись, и каждую можно двигать отдельно."
                         : "Сначала откройте PDF.")
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово", action: onClose)
                }
            }
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
