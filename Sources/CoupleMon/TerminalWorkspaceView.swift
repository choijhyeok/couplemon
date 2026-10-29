import AppKit
import SwiftUI

struct TerminalWorkspaceView: View {
    @ObservedObject var model: AppModel
    @State private var isDrawingPresented = false
    @State private var selectedAttachment: AppModel.ConversationMessage?
    @State private var isWorking = false
    @FocusState private var inputIsFocused: Bool

    private let background = Color(red: 0.145, green: 0.157, blue: 0.184)
    private let muted = Color(red: 0.57, green: 0.60, blue: 0.65)

    var body: some View {
        VStack(spacing: 0) {
            tabs
            HStack(spacing: 0) {
                sidebar
                Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
                VStack(spacing: 0) {
                    transcript
                    composer
                    statusBar
                }
            }
        }
        .background(background)
        .foregroundStyle(Color(white: 0.88))
        .font(.system(size: 13, design: .monospaced))
        .preferredColorScheme(.dark)
        .frame(minWidth: 760, minHeight: 480)
        .onAppear { inputIsFocused = true }
        .onChange(of: model.terminalFocusRequest) { _, _ in inputIsFocused = true }
        .onChange(of: model.isTerminalMode) { _, enabled in
            if !enabled {
                isDrawingPresented = false
                selectedAttachment = nil
                inputIsFocused = false
            }
        }
        .task(id: model.terminalHistory.last?.id) {
            guard !model.terminalHistory.isEmpty else { return }
            isWorking = true
            do { try await Task.sleep(for: .milliseconds(850)) } catch { return }
            isWorking = false
        }
        .popover(item: $selectedAttachment) { message in
            attachmentPreview(message)
        }
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                Text("workspace")
                Spacer()
            }
            .foregroundStyle(muted)
            .padding(.horizontal, 14)
            .frame(width: 180)

            HStack(spacing: 9) {
                Circle().fill(isWorking ? Color.orange : Color.green).frame(width: 6, height: 6)
                Text(isWorking ? "Codex working" : "Codex ready")
                Spacer(minLength: 20)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(muted)
            }
            .padding(.horizontal, 14)
            .frame(width: 220, height: 35)
            .background(background)
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.35)).frame(height: 1) }

            Text("session.swift")
                .foregroundStyle(muted)
                .padding(.horizontal, 18)
            Spacer()
            Button { model.setTerminalMode(false) } label: {
                Image(systemName: "arrow.up.left.square")
                    .frame(width: 36, height: 35)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("기본 화면으로 돌아가기")
            .help("기본 화면으로 돌아가기")
        }
        .font(.system(size: 12, design: .monospaced))
        .frame(height: 35)
        .background(.black.opacity(0.15))
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("EXPLORER")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(muted)
                .padding(.top, 18)
            HStack(spacing: 7) {
                Image(systemName: "chevron.down").font(.system(size: 9))
                Text("workspace").fontWeight(.semibold)
            }
            VStack(alignment: .leading, spacing: 13) {
                fileRow("Sources", icon: "folder")
                fileRow("Tests", icon: "folder")
                fileRow("Package.swift", icon: "swift")
                fileRow("README.md", icon: "doc.text")
            }
            .padding(.leading, 9)
            Spacer()
            HStack(spacing: 7) {
                Image(systemName: "arrow.triangle.branch")
                Text("main")
            }
            .foregroundStyle(muted)
            .padding(.bottom, 15)
        }
        .padding(.horizontal, 16)
        .frame(width: 180, alignment: .leading)
        .background(.black.opacity(0.08))
    }

    private func fileRow(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(muted)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("╭─ Codex ─────────────────────────╮")
                        Text("│  workspace  ~/workspace        │")
                        Text("╰────────────────────────────────╯")
                    }
                    .foregroundStyle(muted)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.bottom, 6)

                    ForEach(model.terminalHistory) { message in
                        transcriptEntry(message)
                            .id(message.id)
                    }
                    if isWorking {
                        Text("• Working…")
                            .foregroundStyle(muted)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear { scrollToLatest(using: proxy) }
            .onChange(of: model.terminalHistory.last?.id) { _, _ in scrollToLatest(using: proxy) }
        }
    }

    private func transcriptEntry(_ message: AppModel.ConversationMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(message.isLocal ? "›" : "•")
                .foregroundStyle(message.isLocal ? Color.white : Color.green.opacity(0.8))
            VStack(alignment: .leading, spacing: 8) {
                if message.isImageAttachment {
                    Text(message.isLocal ? "Added image context" : "Received image output")
                        .foregroundStyle(muted)
                    HStack(spacing: 8) {
                        Text("└").foregroundStyle(muted)
                        Button { selectedAttachment = message } label: {
                            Text(attachmentLabel(message))
                                .foregroundStyle(Color(red: 0.50, green: 0.70, blue: 1))
                                .underline()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(attachmentLabel(message)) 열기")
                    }
                } else {
                    Text(message.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(message.isLocal ? 12 : 0)
        .background(message.isLocal ? Color.white.opacity(0.04) : .clear,
                    in: RoundedRectangle(cornerRadius: 5))
    }

    private var composer: some View {
        VStack(spacing: 9) {
            HStack(alignment: .center, spacing: 10) {
                Text("›").foregroundStyle(.white)
                TextField("Describe a task…", text: $model.messageDraft)
                    .textFieldStyle(.plain)
                    .focused($inputIsFocused)
                    .onSubmit { model.sendDraft() }
                    .accessibilityLabel("터미널 메시지 입력")
                Button { isDrawingPresented.toggle() } label: {
                    Image(systemName: "paperclip")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("이미지 그려 보내기")
                .help("이미지 그려 보내기")
                .popover(isPresented: $isDrawingPresented, arrowEdge: .top) {
                    DrawingComposerView { drawing in
                        model.sendDrawing(drawing)
                        isDrawingPresented = false
                        inputIsFocused = true
                    }
                }
                Button { model.sendDraft() } label: {
                    Image(systemName: "arrow.up")
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .disabled(MessageText.normalize(model.messageDraft).isEmpty)
                .accessibilityLabel("터미널 메시지 보내기")
            }
            .padding(12)
            .background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
            HStack {
                Text("agent · local")
                Spacer()
                Text("↵ send  ·  ⌃⌥Space focus")
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(muted)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    private var statusBar: some View {
        HStack(spacing: 7) {
            Circle().fill(model.realtimeState == .connected && model.sendError == nil ? .green : .orange)
                .frame(width: 5, height: 5)
            Text(connectionStatus)
                .help(model.connectionNotice ?? "Session connected")
            Spacer()
            Text("workspace-write   UTF-8")
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(muted)
        .padding(.horizontal, 16)
        .frame(height: 25)
        .background(.black.opacity(0.12))
    }

    private var connectionStatus: String {
        if model.sendError != nil { return "delivery unconfirmed" }
        switch model.realtimeState {
        case .notConfigured: return "not connected"
        case .connecting: return "connecting…"
        case .failed: return "reconnecting…"
        case .connected: return model.isPartnerReachable ? "session connected" : "waiting for peer"
        }
    }

    private func attachmentLabel(_ message: AppModel.ConversationMessage) -> String {
        "[Image #\(message.attachmentNumber ?? 1)]"
    }

    private func attachmentPreview(_ message: AppModel.ConversationMessage) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(attachmentLabel(message))
                Spacer()
                Button { selectedAttachment = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("이미지 닫기")
            }
            .font(.system(size: 12, design: .monospaced))
            if let drawing = message.drawing {
                DrawingPreview(drawing: drawing)
                    .frame(width: 420, height: 300)
            } else if let image = CoupleMonAnimatedEmoticon(messageValue: message.text)?.emoticon.image
                        ?? CoupleMonEmoticon(messageValue: message.text)?.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300, height: 300)
            }
        }
        .padding(16)
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        guard let id = model.terminalHistory.last?.id else { return }
        DispatchQueue.main.async { proxy.scrollTo(id, anchor: .bottom) }
    }
}
