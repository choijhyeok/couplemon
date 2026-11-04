import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class Pet3DWindowController {
    let window: NSWindow
    let generator: LocalPet3DGenerator
    init(model: AppModel) {
        generator = LocalPet3DGenerator(library: model.pet3DLibrary)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "CoupleMon · 3D 캐릭터"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 780, height: 620)
        window.contentView = NSHostingView(rootView: Pet3DStudioView(model: model, generator: generator))
        window.center()
    }
    func show() { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }
    func cancelGeneration() { generator.cancel() }
}

struct Pet3DStudioView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var generator: LocalPet3DGenerator
    @State private var agent = Pet3DAgent.codex
    @State private var image: NSImage?
    @State private var imageData: Data?
    @State private var name = ""
    @State private var instructions = ""
    @State private var assets: [Pet3DAsset] = []
    @State private var selection: UUID?
    @State private var previewReady = false
    @State private var error: String?
    @State private var showLog = false
    @State private var blenderURL = Pet3DTools.blender
    @State private var agentURL = Pet3DTools.executable("codex")
    @State private var previewAction = Pet3DAction.idle
    @State private var previewRequest = UUID()
    @State private var previewEvent: String?
    @State private var previewLevel: Int? = nil

    var body: some View {
        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    Text("이미지로 3D 캐릭터 만들기").font(.title2.bold())
                    Text("Claude/Codex가 이미지를 보고 모델링 코드를 작성하고, Blender가 이 Mac에서 3D 캐릭터를 만듭니다.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button(action: chooseImage) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14).fill(Color.accentColor.opacity(0.06))
                            if let image {
                                Image(nsImage: image).resizable().scaledToFit().padding(10)
                            } else {
                                VStack(spacing: 8) {
                                    Image(systemName: "photo.badge.plus").font(.system(size: 30))
                                    Text("캐릭터 이미지 선택")
                                    Text("PNG · JPEG · WebP, 최대 20MB").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.frame(height: 140)
                    }
                    .buttonStyle(.plain).disabled(generator.isRunning)
                    TextField("캐릭터 이름", text: $name).textFieldStyle(.roundedBorder).disabled(generator.isRunning)
                    Picker("생성 도구", selection: $agent) {
                        ForEach(Pet3DAgent.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).disabled(generator.isRunning)
                    HStack {
                        Label(agentURL == nil ? "\(agent.title) CLI 필요" : "\(agent.title) CLI 확인됨",
                              systemImage: agentURL == nil ? "exclamationmark.circle" : "checkmark.circle")
                        Spacer()
                        Button("실행 파일 선택") { chooseTool(isBlender: false) }
                    }.font(.caption).disabled(generator.isRunning)
                    HStack {
                        Label(blenderURL == nil ? "Blender 설치 필요" : "Blender 확인됨",
                              systemImage: blenderURL == nil ? "exclamationmark.circle" : "checkmark.circle")
                        Spacer()
                        Button("Blender 선택") { chooseTool(isBlender: true) }
                    }.font(.caption).disabled(generator.isRunning)
                    HStack {
                        Link("Blender 다운로드", destination: URL(string: "https://www.blender.org/download/")!)
                        Spacer()
                        Button("설치 다시 확인") { refreshTools() }
                    }.font(.caption).disabled(generator.isRunning)
                    TextField("추가 요청 (선택): 귀를 짧게, 원본 색 유지…", text: $instructions, axis: .vertical)
                        .lineLimit(2...3).textFieldStyle(.roundedBorder).disabled(generator.isRunning)
                    HStack {
                        Button("3D 생성 시작", systemImage: "sparkles") {
                            guard let imageData, let agentURL, let blenderURL else { return }
                            error = nil
                            generator.start(image: imageData, name: name, instructions: instructions,
                                            agent: agent, executable: agentURL, blender: blenderURL)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(generator.isRunning || imageData == nil || agentURL == nil || blenderURL == nil)
                        if generator.isRunning { Button("중지") { generator.cancel() } }
                    }
                    if generator.isRunning || generator.workspace != nil {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(generator.stage).font(.callout)
                            ProgressView(value: Double(generator.completedStages), total: 4)
                            HStack {
                                if generator.isRunning { ProgressView().controlSize(.small) }
                                Text("4단계 중 \(generator.completedStages)단계 완료").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button(showLog ? "로그 접기" : "생성 로그") { showLog.toggle() }.font(.caption)
                            }
                            if showLog {
                                ScrollView {
                                    Text(generator.log).font(.system(size: 10, design: .monospaced))
                                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                }.frame(height: 100).padding(6).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                            }
                            if let workspace = generator.workspace {
                                Button("코드·원본·로그 폴더 열기") { NSWorkspace.shared.open(workspace) }.font(.caption)
                            }
                        }
                    }
                    if let message = error ?? generator.error {
                        Text(message).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    }
                    Text("이미지는 선택한 AI 서비스로 전송됩니다. CLI 로그인과 이용 한도가 적용됩니다. 결과는 원본을 참고한 3D 재해석이며, 보이지 않는 부분은 추정합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }.frame(minWidth: 400, idealWidth: 420)
            ScrollView {
              VStack(alignment: .leading, spacing: 12) {
                Text("로컬 3D 보관함").font(.headline)
                HStack {
                    Button("GLB 불러오기…", systemImage: "square.and.arrow.down", action: importGLB)
                    Spacer()
                    Button("새로고침", systemImage: "arrow.clockwise") { refreshAssets() }
                }
                if let asset = selectedAsset {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(Color.accentColor.opacity(0.06))
                        Pet3DView(modelURL: model.pet3DLibrary.modelURL(for: asset), activityID: previewRequest,
                                  action: previewAction, event: previewEvent, level: previewLevel ?? model.petProgress.level,
                                  rewardLevel: previewLevel ?? model.equippedRewardLevel,
                                  onStatus: { previewReady = $0 })
                            .id(asset.id).clipShape(RoundedRectangle(cornerRadius: 16))
                    }.frame(height: 210)
                    Text(asset.name).font(.headline)
                    HStack {
                        Picker("동작", selection: $previewAction) {
                            ForEach(Pet3DAction.basicActions) { Text($0.title).tag($0) }
                            if let reward = PetLevelReward.reward(at: previewLevel ?? model.equippedRewardLevel ?? 1) {
                                Text(reward.action.title).tag(reward.action)
                            }
                        }
                        Button("재생") { previewEvent = nil; previewRequest = UUID() }
                    }.disabled(!previewReady)
                    HStack {
                        Button("편지 보내기") { previewAction = .waving; previewEvent = "sendingLetter"; previewRequest = UUID() }
                        Button("편지 받기") { previewAction = .review; previewEvent = "receivingLetter"; previewRequest = UUID() }
                    }.font(.caption).disabled(!previewReady)
                    Picker("장식 미리보기", selection: $previewLevel) {
                        Text("실제 LV \(model.petProgress.level)").tag(Int?.none)
                        ForEach(1...100, id: \.self) { Text("LV \($0)").tag(Optional($0)) }
                    }.font(.caption)
                    Text("장식 미리보기는 실제 경험치를 바꾸지 않습니다.").font(.caption2).foregroundStyle(.secondary)
                    if let reward = PetLevelReward.reward(at: previewLevel ?? model.equippedRewardLevel ?? 1) {
                        Button("\(reward.kind.title) · \(reward.action.title)") {
                            previewAction = reward.action; previewEvent = nil; previewRequest = UUID()
                        }.disabled(!previewReady)
                    } else {
                        Text("LV 2부터 아이템·상호작용이 해금됩니다.").font(.caption).foregroundStyle(.secondary)
                    }
                    if !model.unlockedRewards.isEmpty {
                        Menu("장착 아이템: \(model.equippedReward?.kind.title ?? "없음")") {
                            ForEach(model.unlockedRewards) { reward in
                                Button(reward.title) { model.equipReward(at: reward.level) }
                            }
                        }
                    }
                    Button(model.pet3D?.id == asset.id ? "사용 중인 캐릭터" : "이 캐릭터 적용") {
                        do { try model.select3DCharacter(asset) } catch { self.error = error.localizedDescription }
                    }.buttonStyle(.borderedProminent).disabled(!previewReady || model.pet3D?.id == asset.id)
                    if let workspaceName = asset.workspaceName, UUID(uuidString: workspaceName) != nil {
                        Button("Blender 원본·생성 코드 열기") {
                            NSWorkspace.shared.open(model.pet3DLibrary.directory.deletingLastPathComponent()
                                .appendingPathComponent("3DWorkspaces").appendingPathComponent(workspaceName))
                        }.font(.caption)
                    }
                } else {
                    ContentUnavailableView("저장된 3D 캐릭터 없음", systemImage: "cube.transparent",
                                           description: Text("생성을 마치거나 GLB 파일을 불러오세요."))
                        .frame(height: 280)
                }
                List(assets, selection: $selection) { asset in
                    HStack {
                        Image(systemName: "cube.fill").foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading) {
                            Text(asset.name)
                            Text(asset.createdAt, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.pet3D?.id == asset.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    }.tag(asset.id)
                }.listStyle(.inset).frame(height: 150)
                Button("보관함 폴더 열기") {
                    do {
                        try FileManager.default.createDirectory(at: model.pet3DLibrary.directory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(model.pet3DLibrary.directory)
                    } catch { self.error = error.localizedDescription }
                }.font(.caption)
              }.padding(20)
            }.frame(minWidth: 310, idealWidth: 350)
        }
        .onAppear {
            refreshAssets()
            refreshTools()
        }
        .onChange(of: agent) { _, _ in refreshTools() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            refreshAssets()
            refreshTools()
        }
        .onChange(of: selection) { _, _ in previewReady = false }
        .onChange(of: previewAction) { _, _ in previewRequest = UUID() }
        .onChange(of: previewLevel) { _, _ in previewAction = .idle; previewEvent = nil; previewRequest = UUID() }
        .onChange(of: model.equippedRewardLevel) { _, _ in previewAction = .idle; previewEvent = nil; previewRequest = UUID() }
        .onChange(of: generator.result) { _, result in
            refreshAssets()
            selection = result?.id ?? selection
        }
    }

    private var selectedAsset: Pet3DAsset? { assets.first { $0.id == selection } }
    private func refreshAssets() {
        do {
            assets = try model.pet3DLibrary.assets()
            if !assets.contains(where: { $0.id == selection }) { selection = model.pet3D?.id ?? assets.first?.id }
        } catch { self.error = error.localizedDescription }
    }
    private func refreshTools() {
        let defaults = UserDefaults.standard
        func saved(_ key: String) -> URL? {
            defaults.string(forKey: key).map { URL(fileURLWithPath: $0) }
                .flatMap { FileManager.default.isExecutableFile(atPath: $0.path) ? $0 : nil }
        }
        agentURL = saved("pet3DExecutable.\(agent.rawValue)") ?? Pet3DTools.executable(agent.rawValue)
        blenderURL = saved("pet3DBlender") ?? Pet3DTools.blender
    }
    private func chooseTool(isBlender: Bool) {
        let picker = NSOpenPanel()
        picker.canChooseDirectories = isBlender
        picker.canChooseFiles = true
        picker.message = isBlender ? "Blender.app 또는 blender 실행 파일을 선택하세요." : "\(agent.title) CLI 실행 파일을 선택하세요."
        picker.directoryURL = URL(fileURLWithPath: isBlender ? "/Applications" : "/opt/homebrew/bin")
        guard picker.runModal() == .OK, var url = picker.url else { return }
        if isBlender && url.pathExtension == "app" { url.appendPathComponent("Contents/MacOS/Blender") }
        guard FileManager.default.isExecutableFile(atPath: url.path) else { error = "실행 가능한 파일을 선택하세요."; return }
        UserDefaults.standard.set(url.path, forKey: isBlender ? "pet3DBlender" : "pet3DExecutable.\(agent.rawValue)")
        refreshTools()
    }
    private func chooseImage() {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.png, .jpeg, .webP]
        guard picker.runModal() == .OK, let url = picker.url else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 20 * 1024 * 1024 else { throw Pet3DError.message("20MB 이하 이미지를 선택하세요.") }
            let data = try Data(contentsOf: url)
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1536,
                  ] as CFDictionary),
                  let png = NSBitmapImageRep(cgImage: thumbnail).representation(using: .png, properties: [:]) else {
                throw Pet3DError.message("이미지를 읽을 수 없습니다.")
            }
            imageData = png
            image = NSImage(data: png)
            name = url.deletingPathExtension().lastPathComponent
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func importGLB() {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [UTType(filenameExtension: "glb") ?? .data]
        guard picker.runModal() == .OK, let url = picker.url else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 150 * 1024 * 1024 else { throw Pet3DError.message("150MB 이하 GLB를 선택하세요.") }
            let asset = try model.pet3DLibrary.install(model: Data(contentsOf: url), name: url.deletingPathExtension().lastPathComponent)
            refreshAssets()
            selection = asset.id
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
