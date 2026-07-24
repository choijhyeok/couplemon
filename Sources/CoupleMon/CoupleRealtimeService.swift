import Foundation
import Realtime

@MainActor
final class CoupleRealtimeService {
    private struct BroadcastMessage: Codable {
        let text: String
    }

    var onMessage: ((String) -> Void)?
    var onStateChange: ((CoupleRealtimeState) -> Void)?

    private var client: RealtimeClientV2?
    private var channel: RealtimeChannelV2?
    private var receiveTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var connectionID: UUID?
    private(set) var state: CoupleRealtimeState = .notConfigured {
        didSet { onStateChange?(state) }
    }

    func connect(to settings: RealtimeSettings) async {
        await stop()
        let connectionID = UUID()
        self.connectionID = connectionID
        state = .connecting

        do {
            let client = RealtimeClientV2(
                url: URL(string: settings.projectURL)!.appendingPathComponent("realtime/v1"),
                options: RealtimeClientOptions(
                    headers: ["apikey": settings.publishableKey]
                )
            )
            let channel = client.channel("couplemon:\(settings.normalizedRoomCode.lowercased())") {
                $0.broadcast.acknowledgeBroadcasts = true
            }
            let stream = channel.broadcastStream(event: "message")

            self.client = client
            self.channel = channel
            receiveTask = Task { [weak self] in
                for await envelope in stream {
                    guard
                        !Task.isCancelled,
                        let text = envelope["payload"]?.objectValue?["text"]?.stringValue
                    else { continue }
                    self?.onMessage?(text)
                }
            }

            try await channel.subscribeWithError()
            guard self.connectionID == connectionID else { return }
            state = .connected
            statusTask = Task { [weak self] in
                for await status in channel.statusChange {
                    guard self?.connectionID == connectionID else { return }
                    switch status {
                    case .subscribed:
                        self?.state = .connected
                    case .subscribing:
                        self?.state = .connecting
                    case .unsubscribed, .unsubscribing:
                        self?.state = .failed("실시간 채널 연결이 끊겼습니다.")
                    }
                }
            }
        } catch {
            guard self.connectionID == connectionID else { return }
            await stop()
            state = .failed(error.localizedDescription)
        }
    }

    func send(_ text: String) {
        guard state == .connected, let channel else { return }

        Task { [weak self] in
            do {
                try await channel.broadcast(
                    event: "message",
                    message: BroadcastMessage(text: text)
                )
            } catch {
                self?.state = .failed(error.localizedDescription)
            }
        }
    }

    private func stop() async {
        connectionID = nil
        receiveTask?.cancel()
        receiveTask = nil
        statusTask?.cancel()
        statusTask = nil
        if let client, let channel {
            await client.removeChannel(channel)
        }
        channel = nil
        client = nil
    }
}
