import Foundation

protocol UsageProvider: Sendable {
    var slot: ProviderSlot { get }
    func fetchUsage() async throws -> UsageSnapshot
}

enum ProviderError: Error, LocalizedError {
    case missingCredentials(String)
    case http(Int)
    case rateLimited(retryAfter: TimeInterval)
    case badResponse(String)
    case noData(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials(let s): return "missing credentials: \(s)"
        case .http(let code): return "HTTP \(code)"
        case .rateLimited(let after): return "rate limited, retry in \(Int(after / 60)) min"
        case .badResponse(let s): return "bad response: \(s)"
        case .noData(let s): return "no data: \(s)"
        }
    }

    // A 429 with Retry-After becomes a schedule, not a failure count. Without
    // the header, ten minutes is a safe guess for a usage endpoint.
    static func from(_ http: HTTPURLResponse) -> ProviderError {
        guard http.statusCode == 429 else { return .http(http.statusCode) }
        let header = http.value(forHTTPHeaderField: "Retry-After") ?? ""
        return .rateLimited(retryAfter: retryAfterSeconds(header) ?? 600)
    }

    static func retryAfterSeconds(_ header: String) -> TimeInterval? {
        if let seconds = TimeInterval(header.trimmingCharacters(in: .whitespaces)), seconds >= 0 { return seconds }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: header) { return max(date.timeIntervalSinceNow, 0) }
        return nil
    }
}

enum Backoff {
    static let base: TimeInterval = 120
    static let cap: TimeInterval = 1800

    static func delay(failures: Int) -> TimeInterval {
        min(base * pow(2, Double(max(failures, 0))), cap)
    }
}

enum ISO8601 {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ raw: String) -> Date? {
        if let d = plain.date(from: raw) { return d }
        if let d = fractional.date(from: raw) { return d }
        // Trim a long fraction (Python emits six digits) down to three.
        let trimmed = raw.replacingOccurrences(of: #"\.(\d{3})\d+"#, with: ".$1", options: .regularExpression)
        return fractional.date(from: trimmed)
    }
}

enum Shell {
    struct Result {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    static let timeout: TimeInterval = 10

    // Both pipes drain concurrently so a chatty stderr cannot deadlock stdout,
    // and a watchdog terminates a child that hangs (lsof on a dead mount).
    static func run(_ executable: String, _ arguments: [String]) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        // SIGTERM at the timeout, SIGKILL two seconds later, and close our
        // read ends so a stubborn child cannot pin this thread forever.
        let watchdog = DispatchWorkItem {
            guard process.isRunning else { return }
            process.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                try? out.fileHandleForReading.close()
                try? err.fileHandleForReading.close()
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let group = DispatchGroup()
        var errData = Data()
        DispatchQueue.global(qos: .utility).async(group: group) {
            errData = err.fileHandleForReading.readDataToEndOfFile()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        watchdog.cancel()
        return Result(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }

    // Fixed, trusted locations only. The login PATH is user-editable and this
    // binary is asked for a token.
    static func find(_ name: String) -> String? {
        let dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin"]
        for dir in dirs {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}
