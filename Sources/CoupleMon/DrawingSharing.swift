import AppKit
import SwiftUI

@MainActor
enum DrawingImageExporter {
    enum ExportError: LocalizedError {
        case invalidDrawing, renderingFailed, copyFailed

        var errorDescription: String? {
            switch self {
            case .invalidDrawing: "그림을 먼저 그려 주세요."
            case .renderingFailed: "그림 이미지를 만들지 못했습니다. 다시 시도해 주세요."
            case .copyFailed: "이미지를 복사하지 못했습니다. 다시 시도해 주세요."
            }
        }
    }

    static func pngData(for drawing: DrawingMessage) throws -> Data {
        guard drawing.isValid else { throw ExportError.invalidDrawing }
        // Reuse the on-screen renderer, including dot strokes and the white eraser.
        // An opaque background keeps white ink and the rounded corners readable in chat apps.
        let renderer = ImageRenderer(content: DrawingPreview(drawing: drawing)
            .frame(width: 280, height: 200)
            .background(.white))
        renderer.scale = 3
        renderer.isOpaque = true
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw ExportError.renderingFailed
        }
        return data
    }

    static func copy(_ drawing: DrawingMessage, to pasteboard: NSPasteboard = .general) throws {
        let data = try pngData(for: drawing)
        let item = NSPasteboardItem()
        item.setData(data, forType: .png)
        if let tiff = NSImage(data: data)?.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { throw ExportError.copyFailed }
    }
}

struct DrawingShareActions: View {
    let drawing: DrawingMessage
    var isEnabled = true
    @State private var feedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                DrawingShareButton(drawing: drawing, isEnabled: isEnabled && drawing.isValid) {
                    feedback = $0
                }
                .disabled(!isEnabled || !drawing.isValid)
                .fixedSize()
                Spacer()
                Button("이미지 복사", systemImage: "doc.on.doc") {
                    do {
                        try DrawingImageExporter.copy(drawing)
                        feedback = "복사했어요. 카카오톡 대화방에서 ⌘V로 붙여넣으세요."
                    } catch { feedback = error.localizedDescription }
                }
                .disabled(!isEnabled || !drawing.isValid)
            }
            Text(feedback ?? "공유 메뉴에서 카카오톡을 선택하세요. 없으면 이미지 복사를 이용하세요.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: drawing) { _, _ in feedback = nil }
    }
}

private struct DrawingShareButton: NSViewRepresentable {
    let drawing: DrawingMessage
    let isEnabled: Bool
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(drawing: drawing, onError: onError) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "카카오톡 공유", target: context.coordinator,
                              action: #selector(Coordinator.share(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.toolTip = "공유 메뉴에서 카카오톡을 선택해 손그림을 보내세요."
        button.setAccessibilityLabel("손그림 카카오톡 공유")
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.isEnabled = isEnabled
        context.coordinator.drawing = drawing
        context.coordinator.onError = onError
    }

    @MainActor
    final class Coordinator: NSObject {
        var drawing: DrawingMessage
        var onError: (String) -> Void
        private var picker: NSSharingServicePicker?

        init(drawing: DrawingMessage, onError: @escaping (String) -> Void) {
            self.drawing = drawing
            self.onError = onError
        }

        @objc func share(_ sender: NSButton) {
            do {
                let data = try DrawingImageExporter.pngData(for: drawing)
                guard let image = NSImage(data: data) else { throw DrawingImageExporter.ExportError.renderingFailed }
                let picker = NSSharingServicePicker(items: [image])
                self.picker = picker
                picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            } catch { onError(error.localizedDescription) }
        }
    }
}
