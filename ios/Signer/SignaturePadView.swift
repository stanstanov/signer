import SwiftUI

struct SignaturePadSheet: View {
    var existingImage: UIImage?
    var onSave: (UIImage) -> Void
    var onCancel: () -> Void

    @State private var strokes: [[CGPoint]] = []
    @State private var currentStroke: [CGPoint] = []
    @State private var canvasSize: CGSize = CGSize(width: 350, height: 220)
    @State private var inkColor: Color = SignatureInk.black.color
    @State private var selectedSwatch: SignatureInk? = .black
    @State private var previewImage: UIImage?

    private var isShowingPreview: Bool {
        previewImage != nil && strokes.isEmpty && currentStroke.isEmpty
    }

    private var hasDrawableInk: Bool {
        !strokes.isEmpty || !currentStroke.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text(isShowingPreview
                     ? "Current signature. Tap Clear to draw it again."
                     : "Draw your signature with your finger")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                signatureEditor
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                    )
                    .padding(.horizontal)

                HStack(spacing: 12) {
                    Button("Clear") {
                        strokes = []
                        currentStroke = []
                        previewImage = nil
                    }
                    .disabled(!isShowingPreview && !hasDrawableInk)
                    Spacer(minLength: 8)
                    colorPickerRow
                }
                .padding(.horizontal)

                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .navigationTitle("Signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if hasDrawableInk, let image = renderSignatureImage() {
                            onSave(image)
                        } else if let previewImage {
                            onSave(previewImage)
                        }
                    }
                    .disabled(!isShowingPreview && !hasDrawableInk)
                }
            }
            .onAppear {
                if previewImage == nil {
                    previewImage = existingImage
                }
            }
        }
    }

    @ViewBuilder
    private var signatureEditor: some View {
        if isShowingPreview, let previewImage {
            Image(uiImage: previewImage)
                .resizable()
                .scaledToFit()
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(String(localized: "Signature preview"))
        } else {
            SignatureCanvas(
                strokes: $strokes,
                currentStroke: $currentStroke,
                canvasSize: $canvasSize,
                inkColor: inkColor
            )
        }
    }

    private var colorPickerRow: some View {
        HStack(spacing: 10) {
            ForEach(SignatureInk.allCases) { swatch in
                Button {
                    applyInk(swatch.color, swatch: swatch)
                } label: {
                    Circle()
                        .fill(swatch.color)
                        .frame(width: 28, height: 28)
                        .overlay {
                            Circle()
                                .strokeBorder(Color.white, lineWidth: 2)
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    selectedSwatch == swatch ? Color.accentColor : Color.secondary.opacity(0.35),
                                    lineWidth: selectedSwatch == swatch ? 2.5 : 1
                                )
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(swatch.accessibilityName)
            }

            ColorPicker(
                String(localized: "Custom color"),
                selection: Binding(
                    get: { inkColor },
                    set: { applyInk($0, swatch: nil) }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
            .frame(width: 28, height: 28)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Signature color"))
    }

    private func renderSignatureImage() -> UIImage? {
        var all = strokes
        if !currentStroke.isEmpty {
            all.append(currentStroke)
        }
        guard !all.isEmpty else { return nil }

        let size = CGSize(width: 600, height: 220)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.clear.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let path = UIBezierPath()
            path.lineWidth = 3.5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            UIColor(inkColor).setStroke()

            let scaleX = size.width / max(canvasSize.width, 1)
            let scaleY = size.height / max(canvasSize.height, 1)

            for stroke in all where stroke.count > 1 {
                path.move(to: CGPoint(x: stroke[0].x * scaleX, y: stroke[0].y * scaleY))
                for point in stroke.dropFirst() {
                    path.addLine(to: CGPoint(x: point.x * scaleX, y: point.y * scaleY))
                }
            }
            path.stroke()
        }
    }

    private func applyInk(_ color: Color, swatch: SignatureInk?) {
        inkColor = color
        selectedSwatch = swatch
        if isShowingPreview, let previewImage {
            self.previewImage = recolored(previewImage, with: UIColor(color))
        }
    }

    private func recolored(_ image: UIImage, with color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            color.setFill()
            let rect = CGRect(origin: .zero, size: image.size)
            UIRectFill(rect)
            image.draw(in: rect, blendMode: .destinationIn, alpha: 1)
        }
    }
}

private enum SignatureInk: String, CaseIterable, Identifiable {
    case black, gray, blue, navy, red, green

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .black: return .black
        case .gray: return Color(red: 0.38, green: 0.38, blue: 0.40)
        case .blue: return Color(red: 0.12, green: 0.34, blue: 0.76)
        case .navy: return Color(red: 0.08, green: 0.18, blue: 0.42)
        case .red: return Color(red: 0.76, green: 0.12, blue: 0.14)
        case .green: return Color(red: 0.10, green: 0.46, blue: 0.28)
        }
    }

    var accessibilityName: String {
        switch self {
        case .black: return String(localized: "Black")
        case .gray: return String(localized: "Gray")
        case .blue: return String(localized: "Blue")
        case .navy: return String(localized: "Navy")
        case .red: return String(localized: "Red")
        case .green: return String(localized: "Green")
        }
    }
}

private struct SignatureCanvas: View {
    @Binding var strokes: [[CGPoint]]
    @Binding var currentStroke: [CGPoint]
    @Binding var canvasSize: CGSize
    var inkColor: Color

    var body: some View {
        GeometryReader { geo in
            Canvas { context, _ in
                var path = Path()
                for stroke in strokes + (currentStroke.isEmpty ? [] : [currentStroke]) {
                    guard let first = stroke.first else { continue }
                    path.move(to: first)
                    for point in stroke.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                context.stroke(
                    path,
                    with: .color(inkColor),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let p = value.location
                        guard p.x >= 0, p.y >= 0, p.x <= geo.size.width, p.y <= geo.size.height else { return }
                        currentStroke.append(p)
                    }
                    .onEnded { _ in
                        if !currentStroke.isEmpty {
                            strokes.append(currentStroke)
                            currentStroke = []
                        }
                    }
            )
            .onAppear { canvasSize = geo.size }
            .onChange(of: geo.size) { _, newSize in
                canvasSize = newSize
            }
        }
    }
}
