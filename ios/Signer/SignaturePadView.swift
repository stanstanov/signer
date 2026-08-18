import SwiftUI

struct SignaturePadSheet: View {
    var onSave: (UIImage) -> Void
    var onCancel: () -> Void

    @State private var strokes: [[CGPoint]] = []
    @State private var currentStroke: [CGPoint] = []
    @State private var canvasSize: CGSize = CGSize(width: 350, height: 220)

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Нарисуйте подпись пальцем")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                SignatureCanvas(strokes: $strokes, currentStroke: $currentStroke, canvasSize: $canvasSize)
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                    )
                    .padding(.horizontal)

                HStack {
                    Button("Очистить") {
                        strokes = []
                        currentStroke = []
                    }
                    Spacer()
                }
                .padding(.horizontal)

                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .navigationTitle("Подпись")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        if let image = renderSignatureImage() {
                            onSave(image)
                        }
                    }
                    .disabled(strokes.isEmpty && currentStroke.isEmpty)
                }
            }
        }
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
            UIColor.black.setStroke()

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
}

private struct SignatureCanvas: View {
    @Binding var strokes: [[CGPoint]]
    @Binding var currentStroke: [CGPoint]
    @Binding var canvasSize: CGSize

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
                    with: .color(.black),
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
