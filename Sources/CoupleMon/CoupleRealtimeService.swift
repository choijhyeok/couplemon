import Foundation
import Realtime

@MainActor
final class CoupleRealtimeService {
    private struct BroadcastMessage: Codable {
        let text: String
        let id: UUID
    }

    private struct DrawingEnvelope: Codable {
        let drawing: DrawingMessage
        let id: UUID
    }

    private struct PeerProbe: Codable {
        let sender: UUID
        let reply: Bool
    }

    private struct Receipt: Codable {
        let id: UUID
    }

    var onMessage: ((String) -> Void)?
    var onDrawing: ((DrawingMessage) -> Void)?
    var onTodoChanged: (() -> Void)?
    var onStateChange: ((CoupleRealtimeState) -> Void)?
    var onPartnerChange: ((Bool) -> Void)?
    var onSendError: ((String?) -> Void)?

    private var client: RealtimeClientV2?
    private var channel: RealtimeChannelV2?
    private var tasks: [Task<Void, Never>] = []
    private var retryTask: Task<Void, Never>?
    private var receipts: [UUID: Task<Void, Never>] = [:]
    private var connectionID: UUID?
    private var settings: RealtimeSettings?
    private var retryAttempt = 0
    private let senderID = UUID()
    private var lastPartnerSeen: Date?
    private let makeClient: (URL, RealtimeClientOptions) -> RealtimeClientV2
    private(set) var state: CoupleRealtimeState = .notConfigured {
        didSet { onStateChange?(state) }
    }

    init(makeClient: @escaping (URL, RealtimeClientOptions) -> RealtimeClientV2 = {
        RealtimeClientV2(url: $0, options: $1)
    }) {
        self.makeClient = makeClient
    }

    func connect(to settings: RealtimeSettings) async {
        self.settings = settings
        retryAttempt = 0
        retryTask?.cancel()
        retryTask = nil
        let id = UUID()
        connectionID = id
        await establish(settings, id: id)
    }

    func reconnect() async {
        guard let settings else { return }
        await connect(to: settings)
    }

    func disconnect() async {
        connectionID = nil
        settings = nil
        retryTask?.cancel()
        retryTask = nil
        await stopTransport()
        state = .notConfigured
    }

    private func establish(_ settings: RealtimeSettings, id: UUID) async {
        await stopTransport()
        guard connectionID == id, !Task.isCancelled else { return }
        state = .connecting

        do {
            let settings = try settings.validated()
            let client = makeClient(
                URL(string: settings.projectURL)!.appendingPathComponent("realtime/v1"),
                RealtimeClientOptions(
                    headers: ["apikey": settings.publishableKey],
                    // Use JSON broadcasts with both older and newer Realtime servers.
                    vsn: .v1
                )
            )
            // Peer receipts verify delivery. SDK broadcast acks do not report transport errors
            // and can leave channel cleanup waiting on an acknowledgement from a dead socket.
            let channel = client.channel("couplemon:\(settings.normalizedRoomCode.lowercased())")
            self.client = client
            self.channel = channel

            // Register every stream before joining so the first messages cannot be missed.
            let messages = channel.broadcastStream(event: "message")
            let drawings = channel.broadcastStream(event: "drawing")
            let todos = channel.broadcastStream(event: "todo_changed")
            let peers = channel.broadcastStream(event: "peer_probe")
            let acknowledgements = channel.broadcastStream(event: "receipt")

            tasks.append(Task { [weak self] in
                for await envelope in messages {
                    guard let self, self.connectionID == id, !Task.isCancelled else { return }
                    guard let payload = envelope["payload"]?.objectValue,
                          let text = payload["text"]?.stringValue else { continue }
                    self.markPartnerSeen()
                    self.onMessage?(text)
                    if let value = payload["id"]?.stringValue, let messageID = UUID(uuidString: value) {
                        self.sendReceipt(messageID, channel: channel)
                    }
                }
            })
            tasks.append(Task { [weak self] in
                for await envelope in drawings {
                    guard let self, self.connectionID == id, !Task.isCancelled else { return }
                    guard let payload = envelope["payload"],
                          let data = try? JSONEncoder().encode(payload),
                          data.count <= DrawingMessage.maxPayloadBytes + 256,
                          let message = try? JSONDecoder().decode(DrawingEnvelope.self, from: data),
                          message.drawing.isValid else { continue }
                    self.markPartnerSeen()
                    self.onDrawing?(message.drawing)
                    self.sendReceipt(message.id, channel: channel)
                }
            })
            tasks.append(Task { [weak self] in
                for await _ in todos {
                    guard let self, self.connectionID == id, !Task.isCancelled else { return }
                    self.onTodoChanged?()
                }
            })
            tasks.append(Task { [weak self] in
                for await envelope in peers {
                    guard let self, self.connectionID == id, !Task.isCancelled else { return }
                    guard let payload = envelope["payload"]?.objectValue,
                          let sender = payload["sender"]?.stringValue,
                          sender != self.senderID.uuidString else { continue }
                    self.markPartnerSeen()
                    if payload["reply"]?.boolValue == false {
                        try? await channel.broadcast(event: "peer_probe", message: PeerProbe(
                            sender: self.senderID, reply: true
                        ))
                    }
                }
            })
            tasks.append(Task { [weak self] in
                for await envelope in acknowledgements {
                    guard let self, self.connectionID == id, !Task.isCancelled else { return }
                    guard let value = envelope["payload"]?.objectValue?["id"]?.stringValue,
                          let messageID = UUID(uuidString: value),
                          let pending = self.receipts.removeValue(forKey: messageID) else { continue }
                    pending.cancel()
                    self.markPartnerSeen()
                    self.onSendError?(nil)
                }
            })

            try await channel.subscribeWithError()
            guard connectionID == id, !Task.isCancelled else { return }
            state = .connected
            retryAttempt = 0

            tasks.append(Task { [weak self] in
                for await status in channel.statusChange {
                    guard let self, self.connectionID == id, !Task.isCancelled else { return }
                    switch status {
                    case .subscribed:
                        guard client.status == .connected else {
                            self.state = .connecting
                            continue
                        }
                        self.retryTask?.cancel()
                        self.retryTask = nil
                        self.state = .connected
                    case .subscribing:
                        self.state = .connecting
                    case .unsubscribed, .unsubscribing:
                        self.fail("실시간 채널 연결이 끊겼습니다.", id: id)
                    }
                }
            })
            // A channel can still say 'subscribed' after its underlying socket has gone away.
            tasks.append(Task { [weak self] in
                for await status in client.statusChange {
                    guard let self, self.connectionID == id, !Task.isCancelled else { return }
                    switch status {
                    case .disconnected:
                        self.fail("서버 연결이 끊겼습니다. 인터넷과 Supabase 프로젝트 상태를 확인하세요.", id: id)
                    case .connecting:
                        self.state = .connecting
                        self.lastPartnerSeen = nil
                        self.onPartnerChange?(false)
                    case .connected:
                        if channel.status == .subscribed {
                            self.retryTask?.cancel()
                            self.retryTask = nil
                            self.state = .connected
                        }
                    }
                }
            })
            tasks.append(Task { [weak self] in
                for await heartbeat in client.heartbeat {
                    guard let self, self.connectionID == id, !Task.isCancelled else { return }
                    switch heartbeat {
                    case .timeout, .error, .disconnected:
                        self.fail("서버 응답이 없습니다. 인터넷과 Supabase 프로젝트 상태를 확인하세요.", id: id)
                    case .sent, .ok: break
                    }
                }
            })
            tasks.append(Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, self.connectionID == id else { return }
                    if self.state == .connected {
                        self.onPartnerChange?(self.lastPartnerSeen.map { Date().timeIntervalSince($0) < 35 } ?? false)
                        try? await channel.broadcast(event: "peer_probe", message: PeerProbe(
                            sender: self.senderID, reply: false
                        ))
                    }
                    do { try await Task.sleep(for: .seconds(10)) } catch { return }
                }
            })
        } catch {
            guard connectionID == id, !Task.isCancelled else { return }
            await stopTransport()
            guard connectionID == id else { return }
            fail(error.localizedDescription, id: id)
        }
    }

    func send(_ text: String) {
        let messageID = UUID()
        send(event: "message", message: BroadcastMessage(text: text, id: messageID), id: messageID)
    }

    func sendDrawing(_ drawing: DrawingMessage) {
        guard drawing.isValid else { return }
        let messageID = UUID()
        send(event: "drawing", message: DrawingEnvelope(drawing: drawing, id: messageID), id: messageID)
    }

    private func send(event: String, message: some Codable, id: UUID) {
        guard state == .connected, let channel else {
            onSendError?("연결되지 않아 내 화면에만 표시됐습니다. 연결 후 다시 보내 주세요.")
            return
        }
        let connectionID = self.connectionID
        receipts[id] = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            guard let self, self.connectionID == connectionID else { return }
            self.receipts.removeValue(forKey: id)
            self.onSendError?("상대 수신이 확인되지 않았습니다. 양쪽 앱 버전과 연결 설정을 확인하세요.")
        }
        Task { [weak self] in
            do {
                try await channel.broadcast(event: event, message: message)
            } catch {
                guard let self, self.connectionID == connectionID else { return }
                self.receipts.removeValue(forKey: id)?.cancel()
                self.onSendError?(error.localizedDescription)
            }
        }
    }

    func sendTodoChanged() {
        guard state == .connected, let channel else { return }
        Task { try? await channel.broadcast(event: "todo_changed", message: ["changed": true]) }
    }

    private func sendReceipt(_ id: UUID, channel: RealtimeChannelV2) {
        Task { try? await channel.broadcast(event: "receipt", message: Receipt(id: id)) }
    }

    private func markPartnerSeen() {
        lastPartnerSeen = Date()
        onPartnerChange?(true)
    }

    private func fail(_ reason: String, id: UUID) {
        guard connectionID == id else { return }
        state = .failed(reason)
        lastPartnerSeen = nil
        onPartnerChange?(false)
        guard retryTask == nil, let settings else { return }
        let delay = min(60, 2 * pow(2, Double(min(retryAttempt, 5))))
        retryAttempt += 1
        retryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, self.connectionID == id else { return }
            self.retryTask = nil
            let nextID = UUID()
            self.connectionID = nextID
            await self.establish(settings, id: nextID)
        }
    }

    private func stopTransport() async {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        if !receipts.isEmpty {
            onSendError?("연결이 바뀌어 상대 수신을 확인하지 못했습니다. 필요하면 다시 보내 주세요.")
        }
        receipts.values.forEach { $0.cancel() }
        receipts.removeAll()
        lastPartnerSeen = nil
        onPartnerChange?(false)
        let oldClient = client
        let oldChannel = channel
        client = nil
        channel = nil
        if let oldClient, let oldChannel {
            await oldClient.removeChannel(oldChannel)
            oldClient.disconnect()
        }
    }
}
