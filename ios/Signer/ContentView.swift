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
    @State private var statusMessage = String(localized: "Open a PDF, draw a signature, then tap the page to place it.")
    @State private var currentPageIndex = 0
    @State private var errorMessage: String?
    @State private var placedSignatures: [PlacedSignature] = []
    @State private var allowsMultipleSignatures = false
    @State private var showSettings = false
    @State private var menuSignatureID: UUID?
    @State private var zoomSignatureID: UUID?
    @State private var zoomBaseRect: CGRect = .zero
    @State private var zoomScale: Double = 1

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
                        onDragEnd: moveSignature,
                        onSignatureTap: { id in
                            zoomSignatureID = nil
                            menuSignatureID = id
                        }
                        )
                        .ignoresSafeArea()
                    } else {
                        ContentUnavailableView(
                            String(localized: "No PDF"),
                            systemImage: "doc.richtext",
                            description: Text("Tap Open to get started.")
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if zoomSignatureID != nil {
                    zoomPanel
                } else {
                    statusBar
                }
            }
            .navigationTitle("")
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
                                ? String(localized: "Signature is ready. Tap the PDF to place it. Each tap adds another.")
                                : String(localized: "Signature updated. Tap the PDF to place another.")
                        } else if var placed = placedSignatures.first {
                            placed.image = image
                            placed.rect.size.height = placed.rect.width * image.size.height / max(image.size.width, 1)
                            if let page = document?.page(at: placed.pageIndex) {
                                placed.rect = PDFSignatureService.clamp(placed.rect, to: page.bounds(for: .mediaBox))
                            }
                            placedSignatures = [placed]
                            statusMessage = String(localized: "Signature updated. Drag it or tap another spot.")
                        } else {
                            statusMessage = String(localized: "Signature is ready. Tap the PDF where you want it.")
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
            .alert(String(localized: "Error"), isPresented: Binding(
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
            .confirmationDialog(
                String(localized: "Signature"),
                isPresented: Binding(
                    get: { menuSignatureID != nil },
                    set: { if !$0 { menuSignatureID = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(String(localized: "Zoom")) {
                    let id = menuSignatureID
                    menuSignatureID = nil
                    beginZoom(id)
                }
                Button(String(localized: "Delete"), role: .destructive) {
                    let id = menuSignatureID
                    menuSignatureID = nil
                    deleteSignature(id)
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            }
        }
    }

    private var statusBar: some View {
        Text(statusMessage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .modifier(GlassPanelBackground())
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .animation(nil, value: statusMessage)
    }

    private var zoomPanel: some View {
        HStack(spacing: 12) {
            Image(systemName: "minus.magnifyingglass")
                .foregroundStyle(.secondary)
            Slider(value: $zoomScale, in: 0.5...2.5)
                .onChange(of: zoomScale) { _, scale in
                    applyZoom(CGFloat(scale))
                }
            Image(systemName: "plus.magnifyingglass")
                .foregroundStyle(.secondary)
            Button("Done") {
                zoomSignatureID = nil
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .modifier(GlassPanelBackground())
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            OpenToolbarButton(title: String(localized: "Open"), systemImage: "doc") {
                showImporter = true
            }
            .fixedSize()
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Settings", systemImage: "gearshape") {
                showSettings = true
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("Signature", systemImage: "signature") {
                showSignaturePad = true
            }
            .disabled(document == nil)
            Button("Save", systemImage: "square.and.arrow.down") {
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
                    errorMessage = String(localized: "Couldn’t read the PDF.")
                    return
                }
                pdfURL = url
                document = doc
                currentPageIndex = 0
                signatureImage = nil
                placedSignatures = []
                menuSignatureID = nil
                zoomSignatureID = nil
                allowsMultipleSignatures = false
                PDFSignatureService.clearLastSignatureReference()
                statusMessage = String(localized: "PDF loaded. Draw a signature, then tap the page.")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// `pointInPage` is in PDF page coordinates (bottom-left origin).
    private func placeSignature(pageIndex: Int, pointInPage: CGPoint) {
        guard let document, let signatureImage else {
            statusMessage = String(localized: "Draw a signature first.")
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
            statusMessage = String(localized: "Signatures: \(placedSignatures.count). Tap to add another; drag each one separately.")
        } else {
            placedSignatures = [placed]
            statusMessage = String(localized: "Signature on page \(pageIndex + 1). Drag it or tap another spot.")
        }
    }

    private func moveSignature(id: UUID, pageIndex: Int, rect: CGRect) {
        guard let index = placedSignatures.firstIndex(where: { $0.id == id }) else { return }
        guard let document, let page = document.page(at: pageIndex) else { return }
        placedSignatures[index].pageIndex = pageIndex
        placedSignatures[index].rect = PDFSignatureService.clamp(rect, to: page.bounds(for: .mediaBox))
        if allowsMultipleSignatures {
            statusMessage = String(localized: "Signatures: \(placedSignatures.count). Drag each one separately.")
        } else {
            statusMessage = String(localized: "Signature on page \(pageIndex + 1). Drag it or tap another spot.")
        }
    }

    private func beginZoom(_ id: UUID?) {
        guard let id,
              let placed = placedSignatures.first(where: { $0.id == id }) else { return }
        zoomBaseRect = placed.rect
        zoomScale = 1
        zoomSignatureID = id
    }

    private func applyZoom(_ scale: CGFloat) {
        guard let id = zoomSignatureID,
              let index = placedSignatures.firstIndex(where: { $0.id == id }),
              let document,
              let page = document.page(at: placedSignatures[index].pageIndex) else { return }

        let base = zoomBaseRect
        let center = CGPoint(x: base.midX, y: base.midY)
        let size = CGSize(width: base.width * scale, height: base.height * scale)
        var rect = CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        rect = PDFSignatureService.clamp(rect, to: page.bounds(for: .mediaBox))
        placedSignatures[index].rect = rect
    }

    private func deleteSignature(_ id: UUID?) {
        guard let id else { return }
        placedSignatures.removeAll { $0.id == id }
        if zoomSignatureID == id {
            zoomSignatureID = nil
        }
        if placedSignatures.isEmpty {
            statusMessage = String(localized: "Signature removed. Tap the PDF to place it again.")
        } else if allowsMultipleSignatures {
            statusMessage = String(localized: "Signatures: \(placedSignatures.count). Tap to add another.")
        } else {
            statusMessage = String(localized: "Signature removed. Tap the PDF to place it again.")
        }
    }

    private func applySignatureMode(_ isOn: Bool) {
        if isOn {
            statusMessage = placedSignatures.isEmpty
                ? String(localized: "Multiple signature mode. Tap the PDF to place one.")
                : String(localized: "Multiple signature mode. Tap to add another; drag each one separately.")
        } else {
            if placedSignatures.count > 1 {
                let kept = Array(placedSignatures.suffix(1))
                if let zoomID = zoomSignatureID, kept.first?.id != zoomID {
                    zoomSignatureID = nil
                }
                placedSignatures = kept
                statusMessage = String(localized: "Single signature mode — kept the last one. Drag it or tap another spot.")
            } else if placedSignatures.count == 1 {
                statusMessage = String(localized: "Single signature mode. Drag it or tap another spot.")
            } else {
                statusMessage = String(localized: "Single signature mode. Tap the PDF to place the signature.")
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
            statusMessage = String(localized: "Done — choose where to save the signed PDF.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct OpenToolbarButton: UIViewRepresentable {
    var title: String
    var systemImage: String
    var action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.image = UIImage(systemName: systemImage)
        config.imagePadding = 6
        config.imagePlacement = .leading
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 8)
        let button = UIButton(configuration: config)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.accessibilityLabel = title
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.action = action
        var config = button.configuration ?? .plain()
        config.title = title
        config.image = UIImage(systemName: systemImage)
        button.configuration = config
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tap() { action() }
    }
}

// MARK: - Glass status panel

private struct GlassPanelBackground: ViewModifier {
    private let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(Color(.secondarySystemBackground).opacity(0.92))
            }
            .overlay {
                shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
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
                    Toggle("Multiple signatures", isOn: $allowsMultipleSignatures)
                        .disabled(!hasDocument)
                } footer: {
                    Text(hasDocument
                         ? "In this mode each tap places a new signature, and you can drag each one separately."
                         : "Open a PDF first.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
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
