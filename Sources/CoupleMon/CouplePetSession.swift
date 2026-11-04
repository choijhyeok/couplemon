import Foundation
import CryptoKit

enum CouplePetAction: String, Codable, CaseIterable, Identifiable {
    case kiss, hug, highFive
    var id: String { rawValue }
    var title: String { switch self { case .kiss: "뽀뽀"; case .hug: "포옹"; case .highFive: "하이파이브" } }
    var symbol: String { switch self { case .kiss: "heart.fill"; case .hug: "figure.2"; case .highFive: "hand.raised.fill" } }
}

struct CouplePetPerformance: Codable, Equatable {
    let id: UUID
    let action: CouplePetAction
    let startsAt: Double
    let isSender: Bool
}

struct CouplePetPacket: Codable {
    enum Kind: String, Codable { case manifest, request, chunk, ready, action, accepted, busy }
    var kind: Kind
    var sender: UUID
    var recipient: UUID?
    var hash: String?
    var name: String?
    var size: Int?
    var index: Int?
    var bytes: Data?
    var action: CouplePetAction?
    var eventID: UUID?
    var startsAt: Double?
}

/// Bounded, room-scoped file exchange over the existing paired realtime channel.
@MainActor
final class CouplePetSession: ObservableObject {
    static let maxBytes = 8 * 1024 * 1024
    static let chunkBytes = 24 * 1024
    let id = UUID()
    @Published private(set) var partnerURL: URL?
    @Published private(set) var partnerName = "상대 캐릭터"
    @Published private(set) var status = "상대가 연결되면 캐릭터를 불러옵니다."
    @Published private(set) var progress: Double?
    @Published private(set) var performance: CouplePetPerformance?
    @Published private(set) var isBusy = false
    @Published private(set) var canInteract = false
    var send: ((CouplePetPacket) async throws -> Void)?
    var suspended = false { didSet { updateAvailability() } }
    private let cache: URL
    private var scope = ""
    private var connected = false
    private var local: (data: Data, hash: String, name: String)?
    private var peer: UUID?
    private var peerHash: String?
    private var peerSize = 0
    private var peerHasLocal = false
    private var chunks: [Int: Data] = [:]
    private var lastSeen = Date.distantPast
    private var lastAnnounced = Date.distantPast
    private var requestedAt = Date.distantPast
    private var transfer: Task<Void, Never>?
    private var expiry: Task<Void, Never>?
    private var pending: CouplePetPacket?
    private var seen: [UUID: Date] = [:]
    private var generation = UUID()

    init(cache: URL = Pet3DLibrary.defaultDirectory.deletingLastPathComponent().appendingPathComponent("PartnerCharacters")) {
        self.cache = cache
    }

    func setLocal(url: URL?, name: String = "캐릭터") {
        transfer?.cancel()
        local = nil
        peerHasLocal = false
        if let url {
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= Self.maxBytes else { throw Pet3DError.message("함께하기는 8MB 이하의 3D 캐릭터를 지원합니다.") }
                let data = try Data(contentsOf: url)
                try Pet3DLibrary.validateGLB(data)
                local = (data, Self.digest(data), String(name.prefix(80)))
            } catch { status = error.localizedDescription }
        } else { status = "3D 캐릭터를 선택하면 함께할 수 있어요." }
        performance = nil
        isBusy = false
        pending = nil
        updateAvailability()
        announce(force: true)
    }

    func setConnection(_ value: Bool, room: String) {
        guard value != connected || scope != room else { return }
        connected = value
        scope = room
        generation = UUID()
        transfer?.cancel()
        expiry?.cancel()
        peer = nil
        peerHash = nil
        partnerURL = nil
        peerHasLocal = false
        chunks.removeAll()
        progress = nil
        pending = nil
        isBusy = false
        performance = nil
        seen.removeAll()
        status = value ? "상대의 3D 캐릭터를 기다리고 있어요." : "상대가 연결되면 캐릭터를 불러옵니다."
        updateAvailability()
        announce(force: true)
    }

    func announce(force: Bool = false) {
        guard connected, force || Date().timeIntervalSince(lastAnnounced) > 3 else { return }
        lastAnnounced = Date()
        if Date().timeIntervalSince(lastSeen) > 35 {
            peerHasLocal = false; updateAvailability()
            status = "상대의 연결을 기다리고 있어요."
        }
        var packet = packet(.manifest)
        packet.hash = local?.hash
        packet.size = local?.data.count
        packet.name = local?.name
        emit(packet)
    }

    func receive(_ message: CouplePetPacket) {
        guard connected, message.sender != id, message.recipient == nil || message.recipient == id else { return }
        if let peer, peer != message.sender, Date().timeIntervalSince(lastSeen) < 35 { return }
        if message.kind == .manifest {
            if peer != message.sender { peerHasLocal = false; peerHash = nil; partnerURL = nil }
            peer = message.sender
        }
        guard peer == message.sender else { return }
        lastSeen = Date()
        switch message.kind {
        case .manifest:
            guard let hash = message.hash, Self.validHash(hash), let size = message.size, size > 20, size <= Self.maxBytes else {
                peerHash = nil; partnerURL = nil; progress = nil; chunks.removeAll()
                status = "상대도 8MB 이하의 3D 캐릭터를 선택해 주세요."
                updateAvailability(); return
            }
            partnerName = String((message.name ?? "상대 캐릭터").prefix(80))
            if peerHash != hash {
                peerHash = hash; peerSize = size; chunks.removeAll(); partnerURL = nil
                requestedAt = .distantPast
                let url = cachedURL(hash)
                if let data = try? Data(contentsOf: url), data.count == size, Self.digest(data) == hash,
                   (try? Pet3DLibrary.validateGLB(data)) != nil { partnerURL = url }
            }
            if partnerURL != nil {
                var ready = packet(.ready); ready.hash = hash; emit(ready)
            } else if Date().timeIntervalSince(requestedAt) > 15 {
                requestedAt = Date(); progress = Double(chunks.count * Self.chunkBytes) / Double(size)
                status = "상대 캐릭터 불러오는 중…"
                var request = packet(.request); request.hash = hash; emit(request)
            }
            updateAvailability()
        case .request:
            guard let local, message.hash == local.hash, transfer == nil else { return }
            let token = generation
            transfer = Task { [weak self] in
                guard let self else { return }
                defer { self.transfer = nil }
                do {
                    for offset in stride(from: 0, to: local.data.count, by: Self.chunkBytes) {
                        try Task.checkCancellation()
                        guard self.generation == token else { return }
                        var chunk = self.packet(.chunk)
                        chunk.hash = local.hash; chunk.index = offset / Self.chunkBytes
                        chunk.bytes = local.data.subdata(in: offset..<min(offset + Self.chunkBytes, local.data.count))
                        try await self.send?(chunk)
                        try await Task.sleep(for: .milliseconds(60))
                    }
                } catch { if !Task.isCancelled { self.status = "캐릭터 공유를 다시 시도하고 있어요." } }
            }
        case .chunk:
            guard partnerURL == nil, let expectedHash = peerHash, message.hash == expectedHash,
                  let index = message.index, let bytes = message.bytes,
                  index >= 0, index < (peerSize + Self.chunkBytes - 1) / Self.chunkBytes,
                  bytes.count == min(Self.chunkBytes, peerSize - index * Self.chunkBytes) else { return }
            chunks[index] = bytes
            progress = Double(chunks.values.reduce(0) { $0 + $1.count }) / Double(peerSize)
            if chunks.count == (peerSize + Self.chunkBytes - 1) / Self.chunkBytes, let hash = peerHash {
                var data = Data()
                for i in 0..<chunks.count { data.append(chunks[i]!) }
                do {
                    guard Self.digest(data) == hash else { throw Pet3DError.message("캐릭터 파일 검증에 실패했습니다.") }
                    try Pet3DLibrary.validateGLB(data)
                    let url = cachedURL(hash)
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: url, options: .atomic)
                    partnerURL = url; progress = nil; chunks.removeAll()
                    var ready = packet(.ready); ready.hash = hash; emit(ready)
                    updateAvailability()
                } catch { chunks.removeAll(); requestedAt = .distantPast; status = error.localizedDescription }
            }
        case .ready:
            guard local != nil, message.hash == local?.hash else { return }
            peerHasLocal = true; updateAvailability()
        case .action:
            guard let eventID = message.eventID, let action = message.action, let time = message.startsAt,
                  time.isFinite, abs(time - Date().timeIntervalSince1970) < 10 else { return }
            seen = seen.filter { Date().timeIntervalSince($0.value) < 60 }
            guard seen[eventID] == nil else { return }
            seen[eventID] = Date()
            var reply = packet(canInteract ? .accepted : .busy); reply.eventID = eventID
            if canInteract { begin(.init(id: eventID, action: action, startsAt: time, isSender: false)) }
            emit(reply)
        case .accepted:
            guard let pending, pending.eventID == message.eventID, let eventID = pending.eventID,
                  let action = pending.action, let startsAt = pending.startsAt,
                  Date().timeIntervalSince1970 - startsAt < 4 else { return }
            self.pending = nil
            begin(.init(id: eventID, action: action, startsAt: startsAt, isSender: true))
        case .busy:
            guard let eventID = message.eventID, pending?.eventID == eventID else { return }
            pending = nil; isBusy = false; updateAvailability()
            status = "상대가 지금 함께할 수 없어요. 잠시 후 다시 눌러 주세요."
        }
    }

    func perform(_ action: CouplePetAction) {
        guard canInteract else { return }
        var message = packet(.action)
        message.eventID = UUID(); message.action = action
        message.startsAt = Date().timeIntervalSince1970 + 0.7
        pending = message; isBusy = true; updateAvailability()
        status = "상대에게 \(action.title) 보내는 중…"
        emit(message)
        let eventID = message.eventID
        expiry?.cancel()
        expiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard let self, self.pending?.eventID == eventID else { return }
            self.pending = nil; self.isBusy = false; self.updateAvailability()
            self.status = "상대의 응답이 없어요. 연결을 확인해 주세요."
        }
    }

    private func begin(_ value: CouplePetPerformance) {
        expiry?.cancel()
        performance = value; isBusy = true; updateAvailability(); status = "함께 \(value.action.title) 💛"
        expiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(7)) } catch { return }
            guard let self else { return }
            self.isBusy = false; self.performance = nil; self.updateAvailability()
        }
    }

    private func updateAvailability() {
        canInteract = connected && local != nil && partnerURL != nil && peerHasLocal && !isBusy && !suspended
        if canInteract { status = "\(partnerName)와 함께할 수 있어요." }
    }
    private func packet(_ kind: CouplePetPacket.Kind) -> CouplePetPacket {
        CouplePetPacket(kind: kind, sender: id, recipient: kind == .manifest ? nil : peer)
    }
    private func emit(_ packet: CouplePetPacket) {
        let token = generation
        Task { [weak self] in
            guard let self, self.generation == token else { return }
            do { try await self.send?(packet) }
            catch { if self.generation == token { self.status = "연결이 끊겼어요. 다시 연결해 주세요." } }
        }
    }
    private func cachedURL(_ hash: String) -> URL {
        cache.appendingPathComponent(Self.digest(Data(scope.utf8))).appendingPathComponent(hash + ".glb")
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func validHash(_ value: String) -> Bool {
        value.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
