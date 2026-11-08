import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct PetReferenceImage {
    let png: Data
    let suggestedName: String?

    static let maximumBytes = 20 * 1024 * 1024

    static func read(data: Data, name: String? = nil) throws -> Self {
        guard data.count <= maximumBytes else { throw Pet3DError.message("20MB 이하 이미지를 사용하세요.") }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1536,
              ] as CFDictionary),
              let png = NSBitmapImageRep(cgImage: thumbnail).representation(using: .png, properties: [:]) else {
            throw Pet3DError.message("이미지를 읽을 수 없습니다. 이미지나 이미지 파일을 사용하세요.")
        }
        return Self(png: png, suggestedName: name)
    }

    static func read(url: URL) throws -> Self {
        guard url.isFileURL else { throw Pet3DError.message("이미지 파일이나 복사한 이미지를 사용하세요.") }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumBytes else { throw Pet3DError.message("20MB 이하 이미지를 사용하세요.") }
        return try read(data: Data(contentsOf: url), name: url.deletingPathExtension().lastPathComponent)
    }

    static func canPaste(from pasteboard: NSPasteboard) -> Bool {
        if !(pasteboard.types ?? []).filter({ UTType($0.rawValue)?.conforms(to: .image) == true }).isEmpty { return true }
        return fileURLs(from: pasteboard).contains { url in
            UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
        }
    }

    static func read(pasteboard: NSPasteboard) throws -> Self {
        // Finder file copies must use the original file, rather than its preview icon.
        var failure: Error?
        for url in fileURLs(from: pasteboard) {
            do { return try read(url: url) } catch { failure = error }
        }
        if let failure { throw failure }
        let types = pasteboard.types ?? []
        let preferred = [NSPasteboard.PasteboardType.png, .init(UTType.jpeg.identifier), .init(UTType.webP.identifier), .tiff]
        let images = preferred.filter(types.contains) + types.filter {
            !preferred.contains($0) && UTType($0.rawValue)?.conforms(to: .image) == true
        }
        for type in images {
            guard let data = pasteboard.data(forType: type) else { continue }
            do { return try read(data: data) } catch { failure = error }
        }
        throw failure ?? Pet3DError.message("클립보드에 이미지가 없습니다. 이미지를 복사한 뒤 붙여넣으세요.")
    }

    private static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    static func accepts(_ provider: NSItemProvider) -> Bool {
        provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
            || provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
    }

    static func read(providers: [NSItemProvider]) async throws -> Self {
        var failure: Error?
        for provider in providers where accepts(provider) {
            do {
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    let data = try await representation(provider, type: UTType.fileURL.identifier)
                    guard let url = URL(dataRepresentation: data, relativeTo: nil) else {
                        throw Pet3DError.message("드롭한 파일의 주소를 읽을 수 없습니다.")
                    }
                    return try read(url: url)
                }
                for type in provider.registeredTypeIdentifiers where UTType(type)?.conforms(to: .image) == true {
                    do { return try read(data: await representation(provider, type: type)) }
                    catch { failure = error }
                }
            } catch { failure = error }
        }
        throw failure ?? Pet3DError.message("이미지나 이미지 파일을 끌어놓으세요.")
    }

    private static func representation(_ provider: NSItemProvider, type: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: error ?? Pet3DError.message("이미지 데이터를 가져오지 못했습니다.")) }
            }
        }
    }
}

/// Handles image paste anywhere in this window, including while a text field has focus.
/// Text-only paste events continue to the normal responder chain.
struct PetImagePasteShortcut: NSViewRepresentable {
    let isEnabled: Bool
    let onPaste: (NSPasteboard) -> Void

    func makeNSView(context: Context) -> PetImagePasteView { PetImagePasteView() }
    func updateNSView(_ view: PetImagePasteView, context: Context) {
        view.isEnabled = isEnabled
        view.onPaste = onPaste
    }
}

final class PetImagePasteView: NSView {
    var isEnabled = true
    var onPaste: ((NSPasteboard) -> Void)?
    var pasteboard: NSPasteboard = .general
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        if window != nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }
    }

    func handle(_ event: NSEvent) -> NSEvent? {
        guard isEnabled, let window, event.window === window,
              event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
              event.charactersIgnoringModifiers?.lowercased() == "v",
              PetReferenceImage.canPaste(from: pasteboard) else { return event }
        onPaste?(pasteboard)
        return nil
    }

    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}
