import AppKit
import SwiftUI
import WebKit
import UniformTypeIdentifiers
@testable import CoupleMon

@MainActor
final class Pet3DCheck: NSObject, NSApplicationDelegate {
    enum Failure: Error { case failed(String) }
    private var window: NSWindow!
    private var temporary: URL!
    private var defaults: UserDefaults!
    private var suite = "CoupleMon.Pet3DCheck.\(UUID().uuidString)"

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                try await checks()
                if !CommandLine.arguments.contains("--image-input-only") && !CommandLine.arguments.contains("--motion-review") {
                    print("PASS: GLB validation, library, selection restore, offline WebGL, rotation, local generation")
                }
                cleanup()
                NSApp.terminate(nil)
            } catch {
                fputs("3D check failed: \(error)\n", stderr)
                cleanup()
                exit(1)
            }
        }
    }
    private func cleanup() {
        if let temporary { try? FileManager.default.removeItem(at: temporary) }
        defaults?.removePersistentDomain(forName: suite)
    }
    private func require(_ value: Bool, _ message: String) throws {
        if !value { throw Failure.failed(message) }
    }
    private func checks() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let screenshots = root.appendingPathComponent("dist/pet3d-review", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: true)
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent("pet3d-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: suite)!
        if let index = CommandLine.arguments.firstIndex(of: "--motion-review"), CommandLine.arguments.count > index + 1 {
            try await reviewMotion(modelURL: URL(fileURLWithPath: CommandLine.arguments[index + 1]), screenshots: screenshots)
            return
        }
        try await checkReferenceImages(root: root)
        if CommandLine.arguments.contains("--image-input-only") { return }
        let library = Pet3DLibrary(directory: temporary.appendingPathComponent("3DCharacters"))
        let fixture: Data
        if let index = CommandLine.arguments.firstIndex(of: "--model"), CommandLine.arguments.count > index + 1 {
            fixture = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        } else { fixture = try fixtureGLB() }
        let asset = try library.install(model: fixture, name: "테스트 캐릭터")
        try require(try library.assets() == [asset], "Library restore")
        for data in [Data(), Data("not glb".utf8), Data(fixture.dropLast())] {
            do { _ = try library.install(model: data, name: "invalid"); throw Failure.failed("Invalid model imported") }
            catch is Pet3DError { }
        }
        for uri in ["https://example.com/private.png", "file:///etc/passwd", "../texture.png"] {
            do { try Pet3DLibrary.validateGLB(fixtureGLB(imageURI: uri)); throw Failure.failed("External resource accepted") }
            catch is Pet3DError { }
        }
        let character = temporary.appendingPathComponent("character.png")
        let petDirectory = temporary.appendingPathComponent("pet")
        let bundled = root.appendingPathComponent("Resources/DefaultPet")
        let model = AppModel(characterURL: character, petDirectory: petDirectory, bundledPetDirectory: bundled, defaults: defaults)
        try checkExperience(model: model, character: character, petDirectory: petDirectory)
        try model.select3DCharacter(asset)

        model.setRandom3DInterval(3)
        model.setRandom3DEnabled(true)
        let restoredRandom = AppModel(characterURL: character, petDirectory: petDirectory, bundledPetDirectory: nil, defaults: defaults)
        try require(restoredRandom.isRandom3DEnabled && restoredRandom.random3DInterval == 3, "Random mode preferences were not restored")
        model.setRandom3DInterval(999)
        try require(model.random3DInterval == 3, "Invalid random interval accepted")
        model.setRandom3DEnabled(false)
        model.setTerminalMode(true)
        model.setRandom3DEnabled(true)
        try require(!model.isRandom3DEnabled, "Random mode enabled in terminal mode")
        model.setTerminalMode(false)
        let restored = AppModel(characterURL: character, petDirectory: petDirectory, bundledPetDirectory: nil, defaults: defaults)
        try require(restored.pet3D == asset, "Selected 3D asset not restored")
        try model.selectHatchPet(from: bundled)
        try require(model.pet3D == nil && model.hatchPet != nil, "2D switch failed")
        try model.select3DCharacter(asset)
        try model.resetCharacter()
        try require(model.pet3D == nil && (try library.assets()).count == 1, "Reset deleted 3D library")
        try model.select3DCharacter(asset)

        window = NSWindow(contentRect: NSRect(x: 200, y: 180, width: 260, height: 260),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        // Exercise the renderer independently; SwiftUI appearance updates would overwrite
        // the levels and random settings explicitly driven by this part of the check.
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(Pet3DSchemeHandler(modelURL: library.modelURL(for: asset)), forURLScheme: "couplemon-pet")
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 260, height: 260), configuration: configuration)
        web.setValue(false, forKey: "drawsBackground")
        window.contentView = web
        web.load(URLRequest(url: URL(string: "couplemon-pet://character/viewer.html")!))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        var ready = false
        for _ in 0..<100 {
            if let result = try? await js(web, "window.pet3D?.state.ready ?? false"), result as? Bool == true { ready = true; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        try require(ready, "Offline GLB renderer did not become ready")
        let transparent = try await js(web, "getComputedStyle(document.body).backgroundColor")
        try require((transparent as? String) == "rgba(0, 0, 0, 0)", "Renderer background is opaque")
        _ = try await js(web, """
        {const c=document.querySelector('canvas');
        c.dispatchEvent(new PointerEvent('pointerdown',{pointerId:1,clientX:30,clientY:80}));
        c.dispatchEvent(new PointerEvent('pointermove',{pointerId:1,clientX:150,clientY:90}));
        c.dispatchEvent(new PointerEvent('pointerup',{pointerId:1,clientX:150,clientY:90}));}
        """)
        let yaw = try await js(web, "window.pet3D.state.yaw")
        try require((yaw as? Double ?? 0) > 2, "Rotation did not update")
        let snapshot = try await web.takeSnapshot(configuration: nil)
        try save(snapshot, to: screenshots.appendingPathComponent("offline-renderer.png"))
        print("PASS: offline GLB display, transparency, pointer rotation")
        for (level, expected) in [(1, 0), (2, 1), (3, 2), (5, 3), (10, 4), (1, 0)] {
            _ = try await js(web, "window.pet3D.setLevel(\(level))")
            let unlocked = try await js(web, "window.pet3D.state.decorations") as? [String] ?? []
            try require(unlocked.count == expected, "LV \(level) decoration threshold")
        }
        for action in Pet3DAction.basicActions {
            _ = try await js(web, "window.pet3D.playAction('\(action.rawValue)')")
            try await Task.sleep(for: .milliseconds(100))
            try require(try await js(web, "window.pet3D.state.action") as? String == action.rawValue, "Action playback \(action)")
        }
        _ = try await js(web, "window.pet3D.playAction('jumping')")
        // Imported clips can be longer than the procedural fallback's 1.8 seconds.
        for _ in 0..<100 {
            if try await js(web, "window.pet3D.state.action") as? String == "idle" { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        try require(try await js(web, "window.pet3D.state.action") as? String == "idle", "One-shot action did not return to idle")
        _ = try await js(web, "window.pet3D.setReducedMotion(true); window.pet3D.playAction('waving', 'sendingLetter')")
        try await Task.sleep(for: .milliseconds(150))
        try require(try await js(web, "window.pet3D.state.action") as? String == "idle", "Reduced motion action")
        try require(try await js(web, "window.pet3D.state.letterVisible") as? Bool == false, "Reduced motion letter")
        _ = try await js(web, "window.pet3D.setReducedMotion(false); window.pet3D.setLevel(10); window.pet3D.playAction('waving', 'sendingLetter')")
        try await Task.sleep(for: .milliseconds(700))
        try require(try await js(web, "window.pet3D.state.letterVisible") as? Bool == true, "3D sending letter missing")
        try save(try await web.takeSnapshot(configuration: nil), to: screenshots.appendingPathComponent("level10-wave.png"))
        _ = try await js(web, "window.pet3D.setLevel(1); window.pet3D.setReward(null)")
        try require(try await js(web, "window.pet3D.playAction('castSpell')") as? Bool == false, "Locked interaction accepted")
        for rewardLevel in Array(2...11) + [50, 99, 100] {
            let reward = PetLevelReward.reward(at: rewardLevel)!
            _ = try await js(web, "window.pet3D.setLevel(\(rewardLevel)); window.pet3D.setReward(\(reward.javascript)); window.pet3D.playAction('\(reward.action.rawValue)')")
            try await Task.sleep(for: .milliseconds(120))
            try require(try await js(web, "window.pet3D.state.action") as? String == reward.action.rawValue, "Reward interaction \(rewardLevel)")
            try require(try await js(web, "window.pet3D.state.rewardLevel") as? Int == rewardLevel, "Reward inventory \(rewardLevel)")
        }
        try save(try await web.takeSnapshot(configuration: nil), to: screenshots.appendingPathComponent("level100-interaction.png"))
        _ = try await js(web, "window.pet3D.setLevel(1)")
        try require(try await js(web, "window.pet3D.state.rewardLevel") is NSNull, "Lower level retained locked reward")
        print("PASS: ten action requests, idle return, LV decorations, reduced motion, 3D envelope")
        print("PASS: per-level items, 11 interaction families, unlock guards, LV 100 trophy")
        let randomBefore = try await js(web, "window.pet3D.state.randomActionCount") as? Int ?? 0
        _ = try await js(web, "window.pet3D.playAction('idle'); window.pet3D.setRandomMode(true, 3)")
        var randomCount = randomBefore
        var previousRandom: String?
        var repeatsChecked = 0
        for _ in 0..<150 {
            let count = try await js(web, "window.pet3D.state.randomActionCount") as? Int ?? 0
            if count > randomCount {
                let action = try await js(web, "window.pet3D.state.lastRandomAction") as? String
                try require(action != nil && action != previousRandom, "Consecutive random actions repeated")
                previousRandom = action
                randomCount = count
                repeatsChecked += 1
                print("Random action \(count): \(action ?? "unknown")")
            }
            if randomCount >= randomBefore + 3 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let randomState = try await js(web, "JSON.stringify(window.pet3D.state)") as? String ?? "unknown"
        try require(repeatsChecked >= 3, "Random mode did not keep scheduling actions: \(randomState)")
        _ = try await js(web, "window.pet3D.setRandomMode(false, 3)")
        let stoppedCount = try await js(web, "window.pet3D.state.randomActionCount") as? Int
        try await Task.sleep(for: .milliseconds(3400))
        try require(try await js(web, "window.pet3D.state.randomActionCount") as? Int == stoppedCount, "Random actions continued after stopping")
        try require(try await js(web, "window.pet3D.state.action") as? String == "idle", "Stopping did not restore idle")
        _ = try await js(web, "window.pet3D.setReducedMotion(true); window.pet3D.setRandomMode(true, 3)")
        try await Task.sleep(for: .milliseconds(3300))
        try require(try await js(web, "window.pet3D.state.randomActionCount") as? Int == stoppedCount, "Reduced motion failed to pause random mode")
        _ = try await js(web, "window.pet3D.setRandomMode(false, 3); window.pet3D.setReducedMotion(false)")
        print("PASS: real-time repeating random actions, varied choices, stop, reduced motion")

        let overlay = OverlayPanelController(model: model)
        model.setTodoEnabled(true)
        model.clearMessage()
        overlay.show()
        let overlayWeb = try await findWeb(in: overlay.panel.contentView!)
        for _ in 0..<100 {
            if let ready = try? await js(overlayWeb, "window.pet3D?.state.ready ?? false"), ready as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        model.setRandom3DEnabled(true)
        try await Task.sleep(for: .milliseconds(150))
        try require(try await js(overlayWeb, "window.pet3D.state.randomEnabled") as? Bool == true, "Native random toggle did not reach renderer")
        try require(try await js(overlayWeb, "window.pet3D.state.randomInterval") as? Int == 3, "Native random interval did not reach renderer")
        model.play3DAction(.idle)
        try await Task.sleep(for: .milliseconds(150))
        let rendererRandomEnabled = try await js(overlayWeb, "window.pet3D.state.randomEnabled") as? Bool
        try require(!model.isRandom3DEnabled && rendererRandomEnabled == false, "Idle control did not stop random mode")
        let xpBeforeActions = model.petProgress.experience
        model.play3DAction(.jumping)
        try await Task.sleep(for: .milliseconds(200))
        try require(try await js(overlayWeb, "window.pet3D.state.action") as? String == "jumping", "Manual action did not reach 3D renderer")
        let actionID = model.petActivity?.id
        model.play3DAction(.castSpell)
        model.playRewardInteraction(at: 100)
        try require(model.petActivity?.id == actionID, "Manual controls bypassed reward lock")
        model.playRewardInteraction(at: 2)
        try await Task.sleep(for: .milliseconds(200))
        try require(try await js(overlayWeb, "window.pet3D.state.action") as? String == "playStar", "Unlocked tool action did not play")
        for _ in 0..<12 {
            model.playRandom3DAction()
            try require(model.petActivity.map { Pet3DAction.basicActions.contains($0.action3D) || model.equippedReward?.action == $0.action3D } == true,
                        "Random action selected locked interaction")
        }
        try require(model.petProgress.experience == xpBeforeActions, "Manual actions awarded XP")
        model.clearMessage()
        try await Task.sleep(for: .milliseconds(100))
        let existingWindows = Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
        // Bottom-center play button remains accessible while the chat bubble is hidden.
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: 160, y: 30), modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: overlay.panel.windowNumber,
                                          context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            overlay.panel.sendEvent(event)
        }
        var actionPopup: NSWindow?
        for _ in 0..<30 {
            actionPopup = NSApp.windows.first { $0.isVisible && !existingWindows.contains(ObjectIdentifier($0)) && $0.frame.width >= 240 && $0.frame.height >= 300 }
            if actionPopup != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        try require(actionPopup != nil, "Desktop action button did not open action panel")
        let characterFrame = overlay.panel.convertToScreen(overlayWeb.convert(overlayWeb.bounds, to: nil))
        if let popup = actionPopup {
            try require(!popup.frame.intersects(characterFrame.insetBy(dx: 8, dy: 8)), "Action panel covers the character")
            try require(popup.frame.width < 290 && popup.frame.height < 380, "Action panel is not compact")
        }
        let controlsTop = overlay.panel.frame.minY + 44
        try require(controlsTop < characterFrame.minY, "Controls overlap the character's feet")
        if let popup = actionPopup, let view = popup.contentView,
           let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: screenshots.appendingPathComponent("action-panel.png"))
        }
        print("PASS: desktop action button, manual/random actions, reward guards, no XP farming")
        let letter = DrawingMessage(strokes: [.init(color: .blue, width: 4, points: [.init(x: 0.5, y: 0.5)])])
        model.sendDrawing(letter)
        try await Task.sleep(for: .milliseconds(250))
        try require(try await js(overlayWeb, "window.pet3D.state.action") as? String == "waving", "Native drawing send did not trigger 3D wave")
        model.receiveDrawing(letter)
        try await Task.sleep(for: .milliseconds(250))
        try require(try await js(overlayWeb, "window.pet3D.state.action") as? String == "review", "Native drawing receive did not trigger 3D review")
        overlay.panel.close()
        print("PASS: SwiftUI bridge sends distinct 3D drawing actions")

        let generator = LocalPet3DGenerator(library: library)
        let studio = Pet3DStudioView(model: model, generator: generator)
        window.contentView = NSHostingView(rootView: studio)
        window.setContentSize(NSSize(width: 840, height: 740))
        try await Task.sleep(for: .seconds(2))
        if let bitmap = window.contentView?.bitmapImageRepForCachingDisplay(in: window.contentView!.bounds) {
            window.contentView!.cacheDisplay(in: window.contentView!.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: screenshots.appendingPathComponent("studio.png"))
        }
        // Exercise the actual process path without calling an AI account: this stub returns bpy,
        // then the real Blender binary runs the same sandboxed wrapper as the shipped app.
        guard CommandLine.arguments.count > 2 else {
            throw Failure.failed("Pass a Blender executable to verify local export")
        }
        let blender = URL(fileURLWithPath: CommandLine.arguments[2])
        let stub = temporary.appendingPathComponent("stub-agent")
        try Data(Self.stub.utf8).write(to: stub)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stub.path)
        for (mode, agent) in Pet3DGenerationMode.allCases.flatMap({ mode in Pet3DAgent.allCases.map { (mode, $0) } }) {
            let reference = try Data(contentsOf: root.appendingPathComponent("Sources/CoupleMon/Resources/Emoticons/otter.png"))
            try require(try PetImageMatte.prepare(reference) == reference, "Transparent original was altered")
            generator.start(image: try Data(contentsOf: root.appendingPathComponent("Sources/CoupleMon/Resources/Emoticons/otter.png")),
                            name: "\(mode.title) · \(agent.title) export check",
                            instructions: agent == .codex && mode == .volumetric ? "REPAIR_CHECK" : "", agent: agent,
                            executable: stub, blender: blender, mode: mode)
            try await awaitGeneration(generator)
            if generator.result == nil, let workspace = generator.workspace {
                let review = screenshots.appendingPathComponent("failed-\(UUID().uuidString)")
                try FileManager.default.copyItem(at: workspace, to: review)
                print("Failure artifacts:", review.path)
            }
            try require(generator.result != nil, "\(agent.title) pipeline: \(generator.error ?? "")\n\(generator.log.suffix(6000))")
            try require(generator.completedStages == 4, "Incomplete stages")
            if agent == .codex && mode == .volumetric { try require(generator.log.contains("오류 수정"), "Automatic repair not exercised") }
            guard let workspace = generator.workspace else { throw Failure.failed("No workspace") }
            for name in ["model.glb", "source.blend", "character.py", "preview.png"] {
                try require(FileManager.default.fileExists(atPath: workspace.appendingPathComponent(name).path), "Missing \(name)")
            }
            try Pet3DLibrary.validateGeneratedActions(Data(contentsOf: workspace.appendingPathComponent("model.glb")))
            print("PASS: \(mode.title), \(agent.title) protocol, sandboxed Blender, validated GLB, source, preview, save")
            if mode == .illustrated, let asset = generator.result {
                try require(try Data(contentsOf: workspace.appendingPathComponent("texture.png")) == reference, "Original texture not preserved")
                try await checkIllustratedRenderer(library.modelURL(for: asset), screenshots: screenshots)
            }
        }
        let slow = temporary.appendingPathComponent("slow-agent")
        try Data("#!/usr/bin/python3\nimport time\ntime.sleep(30)\n".utf8).write(to: slow)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: slow.path)
        generator.start(image: Data([0]), name: "cancel", instructions: "", agent: .codex, executable: slow, blender: blender)
        try await Task.sleep(for: .milliseconds(400))
        generator.cancel()
        try await awaitGeneration(generator)
        try require(generator.result == nil && generator.error == nil && !generator.isRunning, "Cancel should stop without saving a character")
        print("PASS: cancellation terminates process and leaves library unchanged")
        if CommandLine.arguments.contains("--live") {
            guard let executable = Pet3DTools.executable("codex") else { throw Failure.failed("Codex unavailable") }
            generator.start(image: try Data(contentsOf: root.appendingPathComponent("Sources/CoupleMon/Resources/Emoticons/otter.png")),
                            name: "수달 3D · Codex", instructions: "Keep the otter's friendly face and beige muzzle.",
                            agent: .codex, executable: executable, blender: blender)
            try await awaitGeneration(generator)
            try require(generator.result != nil, "Live generation: \(generator.error ?? generator.log)")
            let live = generator.workspace!
            try FileManager.default.copyItem(at: live, to: screenshots.appendingPathComponent("live-generation-\(UUID().uuidString)"))
            window.contentView = NSHostingView(rootView: Pet3DView(modelURL: library.modelURL(for: generator.result!)))
            window.setContentSize(NSSize(width: 420, height: 420))
            let liveWeb = try await findWeb(in: window.contentView!)
            var liveReady = false
            for _ in 0..<100 {
                if let result = try? await js(liveWeb, "window.pet3D?.state.ready ?? false"), result as? Bool == true { liveReady = true; break }
                try await Task.sleep(for: .milliseconds(100))
            }
            try require(liveReady, "Live GLB did not load in renderer")
            try await Task.sleep(for: .milliseconds(300))
            try save(try await liveWeb.takeSnapshot(configuration: nil), to: screenshots.appendingPathComponent("live-character.png"))
            print("PASS: live Codex image -> bpy -> Blender -> GLB")
        }
        window.close()
    }
    private func checkReferenceImages(root: URL) async throws {
        let source = try Data(contentsOf: root.appendingPathComponent("Sources/CoupleMon/Resources/Emoticons/otter.png"))
        let file = temporary.appendingPathComponent("참고 수달.png")
        try source.write(to: file)
        let fromFile = try PetReferenceImage.read(url: file)
        try require(fromFile.suggestedName == "참고 수달", "Image file name not retained")
        func verify(_ reference: PetReferenceImage) throws {
            let bitmap = NSBitmapImageRep(data: reference.png)
            try require(bitmap?.pixelsWide == 512 && bitmap?.pixelsHigh == 512, "Imported image canvas changed")
            try require((bitmap?.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.01, "Image alpha was lost")
        }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setData(source, forType: .png)
        try require(PetReferenceImage.canPaste(from: pasteboard), "PNG clipboard not recognized")
        try verify(PetReferenceImage.read(pasteboard: pasteboard))
        pasteboard.clearContents()
        pasteboard.setData(NSImage(data: source)!.tiffRepresentation!, forType: .tiff)
        try verify(PetReferenceImage.read(pasteboard: pasteboard))
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
        try require(PetReferenceImage.canPaste(from: pasteboard), "Finder image copy not recognized")
        try require(try PetReferenceImage.read(pasteboard: pasteboard).suggestedName == "참고 수달", "Finder name was lost")

        let inline = NSItemProvider(item: source as NSData, typeIdentifier: UTType.png.identifier)
        try verify(await PetReferenceImage.read(providers: [inline]))
        let bad = NSItemProvider(item: Data("invalid".utf8) as NSData, typeIdentifier: UTType.png.identifier)
        try verify(await PetReferenceImage.read(providers: [bad, inline]))
        let fileProvider = NSItemProvider(contentsOf: file)!
        try verify(await PetReferenceImage.read(providers: [fileProvider]))
        let text = NSItemProvider(item: "text" as NSString, typeIdentifier: UTType.plainText.identifier)
        try require(!PetReferenceImage.accepts(text), "Text drop accepted as an image")
        for invalid in [Data("not an image".utf8), Data(repeating: 0, count: PetReferenceImage.maximumBytes + 1)] {
            do { _ = try PetReferenceImage.read(data: invalid); throw Failure.failed("Invalid/oversized image accepted") }
            catch is Pet3DError { }
        }
        let large = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3072, pixelsHigh: 128,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let normalized = try PetReferenceImage.read(data: large.representation(using: .png, properties: [:])!)
        try require(NSBitmapImageRep(data: normalized.png)?.pixelsWide == 1536, "Import did not resize to 1536px")

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let target = PetImagePasteView(frame: .zero)
        target.pasteboard = pasteboard
        var pasted = 0
        target.onPaste = { _ in pasted += 1 }
        window.contentView = target
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                    windowNumber: window.windowNumber, context: nil, characters: "v",
                                    charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9)!
        try require(target.handle(event) == nil && pasted == 1, "Image Cmd-V not handled")
        target.isEnabled = false
        try require(target.handle(event) != nil && pasted == 1, "Paste bypasses disabled import")
        target.isEnabled = true
        pasteboard.clearContents()
        pasteboard.setString("캐릭터 이름", forType: .string)
        try require(!PetReferenceImage.canPaste(from: pasteboard), "Plain text clipboard treated as an image")
        try require(target.handle(event) != nil && pasted == 1, "Normal text paste was intercepted")
        do { _ = try PetReferenceImage.read(pasteboard: pasteboard); throw Failure.failed("Text clipboard accepted") }
        catch is Pet3DError { }
        window.contentView = nil
        window.close()
        // Exercise the real SwiftUI window and event monitor with a private clipboard.
        let model = AppModel(characterURL: temporary.appendingPathComponent("reference.png"),
                             petDirectory: temporary.appendingPathComponent("input-pet"),
                             bundledPetDirectory: nil, defaults: defaults)
        let generator = LocalPet3DGenerator(library: Pet3DLibrary(directory: temporary.appendingPathComponent("input-library")))
        window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 840, height: 740),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Pet3DStudioView(model: model, generator: generator))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try await Task.sleep(for: .milliseconds(300))
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        guard let shortcut = descendants(window.contentView!).compactMap({ $0 as? PetImagePasteView }).first else {
            throw Failure.failed("Studio did not mount image paste shortcut")
        }
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
        shortcut.pasteboard = pasteboard
        let paste = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                    context: nil, characters: "v", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9)!
        NSApp.postEvent(paste, atStart: false)
        try await Task.sleep(for: .milliseconds(500))
        let fields = descendants(window.contentView!).compactMap { $0 as? NSTextField }
        try require(fields.contains(where: { $0.stringValue == "참고 수달" }), "Studio Cmd-V did not update the selected image/name")
        window.close()
        print("PASS: PNG/TIFF clipboard, Finder copy, inline/file image drops, alpha, 1536px resize, invalid/20MB guards, Cmd-V and text fallback")
        print("PASS: native Studio Cmd-V event updates the selected reference image")
    }

    private func checkIllustratedRenderer(_ modelURL: URL, screenshots: URL) async throws {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(Pet3DSchemeHandler(modelURL: modelURL), forURLScheme: "couplemon-pet")
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 420, height: 420), configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        window.contentView = web
        window.setContentSize(NSSize(width: 420, height: 420))
        web.load(URLRequest(url: URL(string: "couplemon-pet://character/viewer.html")!))
        for _ in 0..<100 {
            if try await js(web, "window.pet3D?.state.ready ?? false") as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        try require(try await js(web, "window.pet3D?.state.illustrated ?? false") as? Bool == true, "2.5D metadata not recognized")
        try require(try await js(web, "window.pet3D.state.clips.length") as? Int == 21, "2.5D clips not loaded")
        try require(try await js(web, "window.pet3D.state.motion.eyeParts") as? Int == 8, "2.5D eye layers not loaded")
        let beforeBreath = try await js(web, "window.pet3D.state.motion.breath") as? Double ?? -1
        try await Task.sleep(for: .milliseconds(300))
        try require(try await js(web, "window.pet3D.state.motion.breath") as? Double != beforeBreath, "Breathing did not advance")
        try save(try await web.takeSnapshot(configuration: nil), to: screenshots.appendingPathComponent("illustrated-front.png"))
        _ = try await js(web, """
        {const c=document.querySelector('canvas');
        c.dispatchEvent(new PointerEvent('pointerdown',{pointerId:1,clientX:30,clientY:80}));
        c.dispatchEvent(new PointerEvent('pointermove',{pointerId:1,clientX:900,clientY:900}));
        c.dispatchEvent(new PointerEvent('pointerup',{pointerId:1,clientX:900,clientY:900}));}
        """)
        try require(abs(try await js(web, "window.pet3D.state.yaw") as? Double ?? 99) <= 0.38, "2.5D yaw exceeds front-view range")
        try require(abs(try await js(web, "window.pet3D.state.pitch") as? Double ?? 99) <= 0.2, "2.5D pitch exceeds front-view range")
        _ = try await js(web, "window.pet3D.playAction('waving')")
        try await Task.sleep(for: .milliseconds(650))
        try save(try await web.takeSnapshot(configuration: nil), to: screenshots.appendingPathComponent("illustrated-wave.png"))
        for _ in 0..<100 {
            if (try await js(web, "window.pet3D.state.motion.blinks") as? Int ?? 0) > 0 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try require((try await js(web, "window.pet3D.state.motion.blinks") as? Int ?? 0) > 0, "Automatic blink did not run")
        _ = try await js(web, "window.pet3D.setReducedMotion(true)")
        let still = try await js(web, "JSON.stringify(window.pet3D.state.motion)") as? String
        try await Task.sleep(for: .milliseconds(150))
        try require(try await js(web, "JSON.stringify(window.pet3D.state.motion)") as? String == still, "Reduced motion did not freeze 2.5D driver")
        print("PASS: offline 2.5D WebGL, 21 clips, bounded parallax, front and wave snapshots")
    }
    private func reviewMotion(modelURL: URL, screenshots: URL) async throws {
        window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 420, height: 420),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(Pet3DSchemeHandler(modelURL: modelURL), forURLScheme: "couplemon-pet")
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 420, height: 420), configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        window.contentView = web
        window.makeKeyAndOrderFront(nil)
        web.load(URLRequest(url: URL(string: "couplemon-pet://character/viewer.html")!))
        for _ in 0..<100 {
            if try await js(web, "window.pet3D?.state.ready ?? false") as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        _ = try await web.callAsyncJavaScript("""
        const THREE = await import('three');
        const { GLTFLoader } = await import('./vendor/GLTFLoader.js');
        const { IllustratedMotion } = await import('./illustrated-motion.js');
        const gltf = await new GLTFLoader().loadAsync('./model.glb');
        const model = gltf.scene, driver = new IllustratedMotion(model, () => 0.5);
        const scene = new THREE.Scene(); scene.add(model);
        const renderer = new THREE.WebGLRenderer({ alpha:true, antialias:true, preserveDrawingBuffer:true });
        renderer.setPixelRatio(devicePixelRatio); renderer.setSize(innerWidth,innerHeight);
        renderer.outputColorSpace = THREE.SRGBColorSpace;
        Object.assign(renderer.domElement.style,{position:'fixed',inset:0,zIndex:10});
        document.body.append(renderer.domElement);
        const box = new THREE.Box3().setFromObject(model), center = box.getCenter(new THREE.Vector3());
        const extent = Math.max(...box.getSize(new THREE.Vector3()).toArray()) * 0.6;
        const camera = new THREE.OrthographicCamera(-extent,extent,extent,-extent,0.01,100);
        camera.position.copy(center).add(new THREE.Vector3(0,0,5)); camera.lookAt(center);
        model.traverse(o => { for(const m of [o.material].flat().filter(Boolean)) m.toneMapped=false; });
        const render=()=>renderer.render(scene,camera);
        window.motionReview = { driver, render };
        driver.update(0,true); render();
        return driver.eyes.length;
        """, arguments: [:], in: nil, contentWorld: .page)
        try save(try await web.takeSnapshot(configuration: nil), to: screenshots.appendingPathComponent("motion-open.png"))
        _ = try await js(web, "motionReview.driver.updateEyes(1,0,0); motionReview.render()")
        try save(try await web.takeSnapshot(configuration: nil), to: screenshots.appendingPathComponent("motion-closed.png"))
        _ = try await js(web, "motionReview.driver.updateEyes(0,0.8,0); motionReview.render()")
        try save(try await web.takeSnapshot(configuration: nil), to: screenshots.appendingPathComponent("motion-gaze.png"))
        _ = try await js(web, "motionReview.driver.play('waving'); for(let i=0;i<60;i++) motionReview.driver.update(1/60); motionReview.driver.updateEyes(0,0,0); motionReview.render()")
        try save(try await web.takeSnapshot(configuration: nil), to: screenshots.appendingPathComponent("motion-wave.png"))
        window.close()
        print("PASS: native WebGL review of original eyes, closed lids, gaze and layered wave")
    }

    private func checkExperience(model: AppModel, character: URL, petDirectory: URL) throws {
        try require(model.petProgress.experience == 0, "Initial XP")
        model.send("   ")
        model.sendDrawing(DrawingMessage(strokes: []))
        try require(model.petProgress.experience == 0, "Invalid input awarded XP")
        model.send("안녕")
        try require(model.petProgress.experience == 10, "Chat XP")
        model.send("❤️🥰")
        try require(model.petProgress.experience == 15, "Unicode emoji XP")
        model.send(CoupleMonEmoticon.otter.messageValue)
        try require(model.petProgress.experience == 20, "Emoticon XP")
        let drawing = DrawingMessage(strokes: [.init(color: .blue, width: 4, points: [.init(x: 0.5, y: 0.5)])])
        model.sendDrawing(drawing)
        try require(model.petProgress.experience == 45, "Drawing XP")
        model.receive("상대 메시지")
        model.receiveDrawing(drawing)
        try require(model.petProgress.experience == 45, "Received activities should not award XP")
        model.setTerminalMode(true)
        model.send("터미널 메시지")
        model.setTerminalMode(false)
        try require(model.petProgress.experience == 55, "Terminal send XP")
        let restored = AppModel(characterURL: character, petDirectory: petDirectory, bundledPetDirectory: nil, defaults: defaults)
        try require(restored.petProgress.experience == 55, "XP not restored")
        for (xp, level) in [(0, 1), (99, 1), (100, 2), (249, 2), (250, 3), (700, 5), (2700, 10)] {
            try require(PetProgress(experience: xp).level == level, "XP threshold \(xp)")
        }
        try require(PetProgress(experience: Int.max).level == 100 && PetProgress(experience: -1).experience == 0, "Invalid persisted XP clamp")
        try require(!PetProgress.isEmojiOnly("123") && !PetProgress.isEmojiOnly("좋아 ❤️"), "Plain text misclassified as emoji")
        for _ in 0..<5 { model.send("레벨업") }
        try require(model.petProgress.level == 2 && model.equippedRewardLevel == 2, "Level up did not equip unlocked reward")
        model.equipReward(at: 100)
        try require(model.equippedRewardLevel == 2, "Locked reward equipped")
        let child = Process()
        child.executableURL = Bundle.main.executableURL!
        child.arguments = ["--read-progress", suite, "105", "2", "2"]
        try child.run()
        child.waitUntilExit()
        try require(child.terminationStatus == 0, "Progress lost across process restart")
        defaults.set(PetProgress.maximumExperience, forKey: "petExperience")
        defaults.set(99, forKey: "petEquippedRewardLevel")
        let maximum = AppModel(characterURL: character, petDirectory: petDirectory, bundledPetDirectory: nil, defaults: defaults)
        try require(maximum.petProgress.level == 100 && maximum.equippedRewardLevel == 99, "LV 100 restore")
        maximum.equipReward(at: 100)
        let maxChild = Process()
        maxChild.executableURL = Bundle.main.executableURL!
        maxChild.arguments = ["--read-progress", suite, String(PetProgress.maximumExperience), "100", "100"]
        try maxChild.run()
        maxChild.waitUntilExit()
        try require(maxChild.terminationStatus == 0, "LV 100 trophy did not persist across restart")
        defaults.set(model.petProgress.experience, forKey: "petExperience")
        defaults.set(model.equippedRewardLevel ?? 0, forKey: "petEquippedRewardLevel")
        let rewards = (2...100).compactMap(PetLevelReward.reward)
        try require(rewards.count == 99 && Set(rewards.map(\.id)).count == 99 && rewards.last?.kind == .trophy,
                    "Each level through 100 must unlock a unique inventory item")
        model.clearMessage()
        print("PASS: XP by send type, invalid/received input ignored, terminal mode, persistence, level thresholds")
    }
    private func awaitGeneration(_ generator: LocalPet3DGenerator) async throws {
        for _ in 0..<1400 {
            if !generator.isRunning { return }
            try await Task.sleep(for: .milliseconds(500))
        }
        generator.cancel()
        throw Failure.failed("Generation timeout")
    }
    private func findWeb(in view: NSView) async throws -> WKWebView {
        func find(_ view: NSView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            return view.subviews.compactMap(find).first
        }
        for _ in 0..<30 {
            if let result = find(view) { return result }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw Failure.failed("No WKWebView")
    }
    private func js(_ web: WKWebView, _ source: String) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            web.evaluateJavaScript(source) { value, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: value ?? NSNull()) }
            }
        }
    }
    private func save(_ image: NSImage, to url: URL) throws {
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
    private func fixtureGLB(imageURI: String? = nil) throws -> Data {
        var json: [String: Any] = [
            "asset": ["version": "2.0"], "scene": 0, "scenes": [["nodes": [0]]],
            "nodes": [["mesh": 0]], "meshes": [["primitives": [["attributes": ["POSITION": 0], "material": 0]]]],
            "materials": [["pbrMetallicRoughness": ["baseColorFactor": [0.9, 0.4, 0.2, 1], "metallicFactor": 0]]],
            "buffers": [["byteLength": 36]], "bufferViews": [["buffer": 0, "byteOffset": 0, "byteLength": 36]],
            "accessors": [["bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]]],
        ]
        if let imageURI { json["images"] = [["uri": imageURI]] }
        var text = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        while text.count % 4 != 0 { text.append(0x20) }
        var binary = Data()
        for value: Float in [-1, -1, 0, 1, -1, 0, 0, 1, 0] {
            var bits = value.bitPattern.littleEndian
            binary.append(Data(bytes: &bits, count: 4))
        }
        var data = Data()
        func append(_ value: UInt32) { var le = value.littleEndian; data.append(Data(bytes: &le, count: 4)) }
        append(0x46546c67); append(2); append(UInt32(12 + 8 + text.count + 8 + binary.count))
        append(UInt32(text.count)); append(0x4e4f534a); data.append(text)
        append(UInt32(binary.count)); append(0x004e4942); data.append(binary)
        return data
    }
    private static let stub = #"""
    #!/usr/bin/python3
    import json, pathlib, sys
    script = '''
    material = bpy.data.materials.new('Honey')
    material.diffuse_color = (0.95, 0.65, 0.25, 1)
    material.use_nodes = True
    material.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = material.diffuse_color
    for location, scale in [((0, 0, 1), (0.7, 0.4, 0.7)), ((-0.3, 0, 1.8), (0.15, 0.12, 0.6)), ((0.3, 0, 1.8), (0.15, 0.12, 0.6))]:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=16, location=location)
        obj = bpy.context.object
        obj.scale = scale
        obj.parent = root
        obj.data.materials.append(material)
    '''
    image_script = '''image_character(head=(0.49,0.26,0.22,0.19), neck=(0.49,0.44), face=(0.47,0.32), limbs=[
      {"name":"pet_arm_l","pivot":(0.33,0.45),"tip":(0.36,0.52),"radius":0.065},
      {"name":"pet_arm_r","pivot":(0.63,0.46),"tip":(0.57,0.52),"radius":0.065}],
      eyes=[(0.35,0.207,0.422,0.276),(0.533,0.239,0.596,0.306)])'''
    if 'exec' in sys.argv:
        if 'image_character(' in sys.argv[-1]:
            script = image_script
        path = sys.argv[sys.argv.index('--output-last-message') + 1]
        if 'REPAIR_CHECK' in sys.argv[-1] and not pathlib.Path('repair-marker').exists():
            pathlib.Path('repair-marker').touch()
            script = 'raise RuntimeError("Deliberate execution failure for repair test")'
        pathlib.Path(path).write_text(json.dumps({'script': script}))
    else:
        request = json.loads(sys.stdin.readline())
        assert request['message']['content'][0]['source']['media_type'] == 'image/png'
        if 'image_character(' in request['message']['content'][1]['text']:
            script = image_script
        print(json.dumps({'type': 'result', 'is_error': False, 'structured_output': {'script': script}}))
    """#
}

@main
struct Runner {
    @MainActor
    static func main() {
        if CommandLine.arguments.count == 6, CommandLine.arguments[1] == "--read-progress" {
            let defaults = UserDefaults(suiteName: CommandLine.arguments[2])!
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let restored = AppModel(characterURL: root.appendingPathComponent("character.png"),
                                    petDirectory: root.appendingPathComponent("pet"), bundledPetDirectory: nil, defaults: defaults)
            guard restored.petProgress.experience == Int(CommandLine.arguments[3]),
                  restored.equippedRewardLevel == Int(CommandLine.arguments[4]),
                  restored.petProgress.level == Int(CommandLine.arguments[5]) else { exit(1) }
            print("PASS: separate process restored XP, LV and equipped reward")
            return
        }
        let application = NSApplication.shared
        let delegate = Pet3DCheck()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) { }
    }
}
