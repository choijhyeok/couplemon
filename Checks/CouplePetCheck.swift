import AppKit
import SwiftUI
import WebKit
import Realtime
@testable import CoupleMon

struct PairPreview: View {
    let url: URL
    @ObservedObject var session: CouplePetSession
    var body: some View {
        Pet3DView(modelURL: url, randomEnabled: true, randomInterval: 3,
                  partnerURL: session.partnerURL, performance: session.performance)
            .frame(width: 360, height: 260)
    }
}

@MainActor
final class CouplePetCheck: NSObject, NSApplicationDelegate {
    enum Failure: Error { case failed(String) }
    var windows: [NSWindow] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do { try await run(); print("PASS: two native windows and two realtime peers, together interactions"); NSApp.terminate(nil) }
            catch { fputs("Couple check failed: \(error)\n", stderr); exit(1) }
        }
    }
    func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure.failed(message) }
    }
    func wait(_ name: String, seconds: Double = 35, _ condition: () async throws -> Bool) async throws {
        let end = Date().addingTimeInterval(seconds)
        while try await !condition() {
            if Date() >= end { throw Failure.failed(name) }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
    func web(_ view: NSView) -> WKWebView? {
        if let result = view as? WKWebView { return result }
        return view.subviews.compactMap(web).first
    }
    func js(_ web: WKWebView, _ script: String) async throws -> Any {
        try await web.evaluateJavaScript(script)
    }
    func run() async throws {
        let endpoint = URL(string: CommandLine.arguments[1])!
        let localA = URL(fileURLWithPath: CommandLine.arguments[2])
        let localB = URL(fileURLWithPath: CommandLine.arguments[3])
        let output = URL(fileURLWithPath: CommandLine.arguments[4])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("couple-check-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let a = CouplePetSession(cache: root.appendingPathComponent("a"))
        let b = CouplePetSession(cache: root.appendingPathComponent("b"))
        let ta = CoupleRealtimeService { _, options in RealtimeClientV2(url: endpoint, options: options) }
        let tb = CoupleRealtimeService { _, options in RealtimeClientV2(url: endpoint, options: options) }
        var sentA: [CouplePetPacket] = []
        a.send = { sentA.append($0); try await ta.sendPetPacket($0) }
        b.send = { try await tb.sendPetPacket($0) }
        ta.onPetPacket = { a.receive($0) }; tb.onPetPacket = { b.receive($0) }
        ta.onPetConnection = { a.setConnection($0, room: $1) }; tb.onPetConnection = { b.setConnection($0, room: $1) }
        ta.onPetTick = { a.announce() }; tb.onPetTick = { b.announce() }
        a.setLocal(url: localA, name: "내 수달")
        b.setLocal(url: localB, name: "상대 수달")
        for (index, pair) in [(localA, a), (localB, b)].enumerated() {
            let window = NSWindow(contentRect: NSRect(x: 400 + index * 380, y: 350, width: 360, height: 260),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.title = index == 0 ? "함께하기 · 보낸 화면" : "함께하기 · 받은 화면"
            window.isReleasedWhenClosed = false; window.level = .floating
            window.contentView = NSHostingView(rootView: PairPreview(url: pair.0, session: pair.1))
            window.makeKeyAndOrderFront(nil); windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        let settings = RealtimeSettings(projectURL: "https://example.supabase.co", publishableKey: "sb_publishable_example", roomCode: "ABCDEFGHJKLMNPQR")
        await ta.connect(to: settings); await tb.connect(to: settings)
        try await wait("Partner transfer/ready handshake") { a.canInteract && b.canInteract }
        try require(try Data(contentsOf: a.partnerURL!) == Data(contentsOf: localB), "A did not receive B's model")
        try require(try Data(contentsOf: b.partnerURL!) == Data(contentsOf: localA), "B did not receive A's model")
        print("PASS: chunked bidirectional GLB transfer, SHA-256 validation and local caching")
        try await wait("Web views") { self.windows.allSatisfy { self.web($0.contentView!) != nil } }
        let wa = web(windows[0].contentView!)!, wb = web(windows[1].contentView!)!
        for view in [wa, wb] {
            try await wait("Partner render") { (try? await self.js(view, "window.pet3D?.state.partnerReady")) as? Bool == true }
        }
        for action in CouplePetAction.allCases {
            let sender = action == .hug ? b : a
            sender.perform(action)
            try await wait("Pair event delivery") { a.performance != nil && a.performance?.id == b.performance?.id }
            try require(a.performance?.isSender != b.performance?.isSender, "Sender/receiver roles")
            for view in [wa, wb] {
                try await wait("Together renderer action") { try await self.js(view, "window.pet3D.state.togetherAction") as? String == action.rawValue }
            }
            try await Task.sleep(for: .milliseconds(2500))
            for (index, view) in [wa, wb].enumerated() {
                let image = try await view.takeSnapshot(configuration: nil)
                let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(action.rawValue)-\(index).png"))
            }
            try await wait("Pair finish") { a.canInteract && b.canInteract }
            for view in [wa, wb] {
                try await wait("Random resume") { try await self.js(view, "window.pet3D.state.randomEnabled") as? Bool == true }
            }
            print("PASS: \(action.rawValue) on both windows, finish and random resume")
        }
        if let replay = sentA.last(where: { $0.kind == .action }) {
            b.receive(replay)
            try require(b.performance == nil, "Duplicate event replayed")
        }
        b.suspended = true
        a.perform(.kiss)
        try await wait("Busy rejection") { !a.isBusy }
        try require(a.performance == nil && b.performance == nil, "Suspended partner performed action")
        b.suspended = false
        print("PASS: duplicate suppression and suspended recipient")
        let saved = a.partnerURL!
        await ta.reconnect()
        try await wait("Cached reconnect") { a.canInteract && b.canInteract }
        try require(a.partnerURL == saved, "Reconnect lost cached character")
        let other = RealtimeSettings(projectURL: settings.projectURL, publishableKey: settings.publishableKey, roomCode: "ZZZZZZZZZZZZZZZZ")
        await ta.connect(to: other)
        try require(a.partnerURL == nil && !a.canInteract, "Partner leaked into another room")
        await ta.disconnect(); await tb.disconnect()
        try require(!a.canInteract && !b.canInteract, "Disconnected action still enabled")
        print("PASS: cached reconnect, room isolation and disconnect")
        windows.forEach { $0.close() }
    }
}

@main struct CouplePetCheckApp {
    @MainActor static func main() {
        setbuf(stdout, nil)
        let app = NSApplication.shared
        let delegate = CouplePetCheck(); app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
