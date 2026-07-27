import Foundation
import PostgREST

@MainActor
final class CoupleTodoService {
    enum TodoError: LocalizedError {
        case notConfigured

        var errorDescription: String? { "Todo DB가 연결되지 않았습니다." }
    }

    private struct TodoRecord: Codable {
        let id: UUID
        let roomCode: String
        let scope: AppModel.TodoScope
        let ownerID: UUID?
        let text: String
        let isCompleted: Bool

        enum CodingKeys: String, CodingKey {
            case id, scope, text
            case roomCode = "room_code"
            case ownerID = "owner_id"
            case isCompleted = "is_completed"
        }

        init(item: AppModel.TodoItem, roomCode: String) {
            id = item.id
            self.roomCode = roomCode
            scope = item.scope
            ownerID = item.ownerID
            text = item.text
            isCompleted = item.isCompleted
        }

        var item: AppModel.TodoItem {
            AppModel.TodoItem(
                id: id,
                text: text,
                isCompleted: isCompleted,
                scope: scope,
                ownerID: ownerID
            )
        }
    }

    private var client: PostgrestClient?
    private var roomCode: String?

    func configure(settings: RealtimeSettings, ownerID: UUID) {
        guard let projectURL = URL(string: settings.projectURL) else {
            client = nil
            roomCode = nil
            return
        }
        let code = settings.normalizedRoomCode
        client = PostgrestClient(
            url: projectURL.appendingPathComponent("rest/v1"),
            headers: [
                "apikey": settings.publishableKey,
                "Authorization": "Bearer \(settings.publishableKey)",
                "X-CoupleMon-Room": code,
                "X-CoupleMon-Owner": ownerID.uuidString.lowercased(),
            ],
            logger: nil
        )
        roomCode = code
    }

    func fetchTodos() async throws -> [AppModel.TodoItem] {
        guard let client else { throw TodoError.notConfigured }
        let records: [TodoRecord] = try await client
            .from("couplemon_todos")
            .select("id,room_code,scope,owner_id,text,is_completed")
            .eq("room_code", value: roomCode)
            .order("created_at")
            .execute()
            .value
        return records.map(\.item)
    }

    func upsert(_ items: [AppModel.TodoItem]) async throws {
        guard let client, let roomCode else { throw TodoError.notConfigured }
        guard !items.isEmpty else { return }
        try await client
            .from("couplemon_todos")
            .upsert(items.map { TodoRecord(item: $0, roomCode: roomCode) }, onConflict: "id")
            .execute()
    }

    func delete(id: UUID) async throws {
        guard let client, let roomCode else { throw TodoError.notConfigured }
        try await client
            .from("couplemon_todos")
            .delete()
            .eq("id", value: id)
            .eq("room_code", value: roomCode)
            .execute()
    }
}
