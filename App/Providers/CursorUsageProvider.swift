import Foundation
import SQLite3

// Cursor keeps its session in the editor's own state store. The usage summary
// endpoint that the dashboard reads accepts that session as a cookie.
enum CursorUsageDecoder {
    static func decode(_ data: Data, now: Date = Date()) throws -> UsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.badResponse("top level is not an object")
        }
        let resets = (root["billingCycleEnd"] as? String).flatMap(ISO8601.parse)
        let usage = root["individualUsage"] as? [String: Any] ?? [:]
        let plan = usage["plan"] as? [String: Any] ?? [:]
        var windows: [UsageWindow] = []
        if let total = plan["totalPercentUsed"] as? Double {
            windows.append(UsageWindow(label: "Included", percentUsed: total, resetsAt: resets))
        }
        if let api = plan["apiPercentUsed"] as? Double, api > 0 {
            windows.append(UsageWindow(label: "API", percentUsed: api, resetsAt: resets))
        }
        if let onDemand = usage["onDemand"] as? [String: Any], onDemand["enabled"] as? Bool == true,
           let limit = onDemand["limit"] as? Double, limit > 0, let used = onDemand["used"] as? Double {
            windows.append(UsageWindow(label: "On demand", percentUsed: used / limit * 100, resetsAt: resets))
        }
        guard let primary = windows.first else {
            if root["isUnlimited"] as? Bool == true { throw ProviderError.noData("unlimited plan, nothing to meter") }
            throw ProviderError.noData("no metered usage in the summary")
        }
        return UsageSnapshot(primary: primary, secondary: Array(windows.dropFirst()), fetchedAt: now, planLabel: root["membershipType"] as? String)
    }
}

struct CursorUsageProvider: UsageProvider {
    let slot = ProviderSlot(id: "cursor", kind: .cursor, title: "Cursor")
    let storeURL: URL
    let endpoint = URL(string: "https://cursor.com/api/usage-summary")!

    static func defaultStoreURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    init(storeURL: URL = CursorUsageProvider.defaultStoreURL()) {
        self.storeURL = storeURL
    }

    // Only a Cursor that is installed and signed in gets a ring.
    static func discovered() -> CursorUsageProvider? {
        let provider = CursorUsageProvider()
        return (try? provider.sessionCookie()) == nil ? nil : provider
    }

    func fetchUsage() async throws -> UsageSnapshot {
        let cookie = try sessionCookie()
        var request = URLRequest(url: endpoint)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("devHUD/0.3", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            if http.statusCode == 401 || http.statusCode == 403 { throw ProviderError.missingCredentials("Cursor session rejected, sign in again in Cursor") }
            throw ProviderError.from(http)
        }
        return try CursorUsageDecoder.decode(data)
    }

    // Read-only open: Cursor may have the database open and in WAL mode.
    func sessionCookie() throws -> String {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            throw ProviderError.missingCredentials("Cursor state store not found")
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            throw ProviderError.missingCredentials("Cursor state store not readable")
        }
        defer { sqlite3_close(db) }
        guard let token = value(forKey: "cursorAuth/accessToken", in: db), !token.isEmpty,
              let account = value(forKey: "cursorAuth/stripeMembershipAuthId", in: db), !account.isEmpty else {
            throw ProviderError.missingCredentials("Cursor is not signed in")
        }
        return "WorkosCursorSessionToken=\(account)::\(token)"
    }

    private func value(forKey key: String, in db: OpaquePointer) -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key = ? LIMIT 1", -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: text)
    }
}
