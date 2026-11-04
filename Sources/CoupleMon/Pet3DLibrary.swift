import Foundation

enum Pet3DError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(value) = self { return value }; return nil }
}

struct Pet3DAsset: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let createdAt: Date
    let workspaceName: String?
}

struct Pet3DLibrary {
    let directory: URL
    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoupleMon/3DCharacters", isDirectory: true)
    }

    init(directory: URL = Self.defaultDirectory) { self.directory = directory }

    func modelURL(for asset: Pet3DAsset) -> URL {
        directory.appendingPathComponent(asset.id.uuidString).appendingPathComponent("model.glb")
    }

    func assets() throws -> [Pet3DAsset] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { UUID(uuidString: $0.lastPathComponent) != nil }
            .compactMap { folder -> Pet3DAsset? in
                guard let data = try? Data(contentsOf: folder.appendingPathComponent("character.json")),
                      let asset = try? JSONDecoder().decode(Pet3DAsset.self, from: data),
                      asset.id.uuidString == folder.lastPathComponent,
                      FileManager.default.fileExists(atPath: modelURL(for: asset).path) else { return nil }
                return asset
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func install(model data: Data, name: String, workspaceName: String? = nil) throws -> Pet3DAsset {
        try Self.validateGLB(data)
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        let asset = Pet3DAsset(id: UUID(), name: trimmed.isEmpty ? "내 3D 캐릭터" : trimmed,
                               createdAt: Date(), workspaceName: workspaceName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = directory.appendingPathComponent(".import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try data.write(to: staging.appendingPathComponent("model.glb"), options: .atomic)
        try JSONEncoder().encode(asset).write(to: staging.appendingPathComponent("character.json"), options: .atomic)
        try FileManager.default.moveItem(at: staging, to: directory.appendingPathComponent(asset.id.uuidString))
        return asset
    }

    static func validateGeneratedActions(_ data: Data) throws {
        try validateGLB(data)
        let length = data[12..<16].enumerated().reduce(0) { $0 | (Int($1.element) << ($1.offset * 8)) }
        let json = try JSONSerialization.jsonObject(with: data.subdata(in: 20..<20 + length)) as? [String: Any]
        let names = Set((json?["animations"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String })
        let missing = Set(Pet3DAction.allCases.map(\.rawValue)).subtracting(names)
        guard missing.isEmpty else { throw Pet3DError.message("생성된 GLB의 동작이 누락됐습니다: \(missing.sorted().joined(separator: ", "))") }
    }

    static func validateGLB(_ data: Data) throws {
        func invalid(_ message: String) -> Pet3DError { .message(message) }
        guard data.count >= 20, data.count <= 150 * 1024 * 1024 else {
            throw invalid("GLB 파일은 150MB 이하여야 합니다.")
        }
        func uint(_ offset: Int) -> UInt32 {
            data[offset..<offset + 4].enumerated().reduce(0) { $0 | (UInt32($1.element) << ($1.offset * 8)) }
        }
        guard uint(0) == 0x46546C67, uint(4) == 2, Int(uint(8)) == data.count,
              uint(16) == 0x4E4F534A else { throw invalid("유효한 GLB 2.0 파일이 아닙니다.") }
        let length = Int(uint(12))
        guard length > 0, length % 4 == 0, length <= data.count - 20,
              let json = try? JSONSerialization.jsonObject(with: data.subdata(in: 20..<20 + length)) as? [String: Any],
              let nodes = json["nodes"] as? [[String: Any]], !nodes.isEmpty,
              let meshes = json["meshes"] as? [[String: Any]], !meshes.isEmpty else {
            throw invalid("GLB에 표시할 캐릭터가 없습니다.")
        }
        let unsupported = Set(json["extensionsRequired"] as? [String] ?? [])
            .intersection(["KHR_draco_mesh_compression", "EXT_meshopt_compression", "KHR_texture_basisu"])
        guard unsupported.isEmpty else { throw invalid("압축하지 않은 GLB로 내보내 주세요: \(unsupported.sorted().joined(separator: ", "))") }
        for field in ["buffers", "images"] {
            for item in json[field] as? [[String: Any]] ?? [] {
                if let uri = item["uri"] as? String, !uri.hasPrefix("data:") {
                    throw invalid("텍스처와 버퍼를 파일 안에 포함한 GLB가 필요합니다.")
                }
            }
        }
        var offset = 20 + length
        while offset < data.count {
            guard data.count - offset >= 8 else { throw invalid("GLB 데이터가 잘렸습니다.") }
            let size = Int(uint(offset))
            guard size % 4 == 0, size <= data.count - offset - 8 else { throw invalid("GLB 데이터가 잘렸습니다.") }
            offset += 8 + size
        }
    }
}
