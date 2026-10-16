import Foundation
import Network

enum MailError: LocalizedError {
    case notSetUp, signIn, notFound, timeout
    case server(String)
    case connection(String)

    var errorDescription: String? {
        switch self {
        case .notSetUp: "Add your hub Gmail address and app password in Settings to open emails here."
        case .signIn: "Gmail didn't accept the address or app password. Check them in Settings."
        case .notFound: "This email isn't in the hub mailbox anymore (it may have been deleted)."
        case .timeout: "Gmail took too long to answer. Check your connection and try again."
        case .server(let text): "Gmail said: \(text)"
        case .connection(let text): "Couldn't reach Gmail. \(text)"
        }
    }
}

/// Just enough IMAP (over TLS) to sign in, find one message by its
/// Message-ID and download it. Read-only: the mailbox is opened with
/// EXAMINE and fetched with BODY.PEEK, so nothing is ever marked read.
///
/// One connection is used by one task at a time, so the buffer needs no lock.
final class IMAPConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "com.navadia.commandcenter.imap")
    private var buffer = Data()
    private var tagCounter = 0
    private static let crlf = Data([13, 10])

    init(host: String = "imap.gmail.com", port: UInt16 = 993) {
        connection = NWConnection(host: NWEndpoint.Host(host),
                                  port: NWEndpoint.Port(rawValue: port) ?? .imaps,
                                  using: .tls)
    }

    // MARK: - High level

    func open() async throws {
        let once = Once()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.run { cont.resume() }
                case .failed(let error), .waiting(let error):
                    once.run { cont.resume(throwing: MailError.connection(error.localizedDescription)) }
                case .cancelled:
                    once.run { cont.resume(throwing: MailError.timeout) }
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
        let greeting = String(decoding: try await readLine(), as: UTF8.self)
        guard greeting.hasPrefix("* OK") else { throw MailError.server(greeting) }
    }

    func close() {
        connection.cancel()
    }

    func login(_ address: String, _ password: String) async throws {
        do {
            try await command("LOGIN \(Self.quote(address)) \(Self.quote(password))")
        } catch MailError.server(_) {
            throw MailError.signIn
        }
    }

    /// Downloads the raw message (up to `maxBytes`) with this Message-ID.
    func fetch(messageID: String, maxBytes: Int = 4_000_000) async throws -> Data {
        try await command("EXAMINE \(Self.quote(try await allMailName()))")
        let search = try await command("UID SEARCH X-GM-RAW \(Self.quote("rfc822msgid:\(messageID)"))")
        let uids = search.lines
            .filter { $0.hasPrefix("* SEARCH") }
            .flatMap { $0.split(separator: " ").dropFirst(2) }
            .compactMap { Int($0) }
        guard let uid = uids.max() else { throw MailError.notFound }
        let reply = try await command("UID FETCH \(uid) (BODY.PEEK[]<0.\(maxBytes)>)")
        guard let raw = reply.literals.first, !raw.isEmpty else { throw MailError.notFound }
        return raw
    }

    func logout() async {
        _ = try? await command("LOGOUT")
    }

    /// Gmail's "All Mail" folder (its name changes with the account language),
    /// found by its \All attribute.
    private func allMailName() async throws -> String {
        let reply = try await command(#"LIST "" "*""#)
        for line in reply.lines where line.contains("\\All") {
            if let name = Self.lastQuoted(line) { return name }
        }
        return "[Gmail]/All Mail"
    }

    // MARK: - Protocol

    struct Reply {
        var lines: [String] = []
        var literals: [Data] = []
    }

    @discardableResult
    func command(_ text: String) async throws -> Reply {
        tagCounter += 1
        let tag = "a\(tagCounter)"
        try await send("\(tag) \(text)\r\n")
        var reply = Reply()
        while true {
            var line = String(decoding: try await readLine(), as: UTF8.self)
            // A line ending in {n} is followed by n raw bytes, then the rest of the line.
            while let size = Self.literalSize(line) {
                reply.literals.append(try await readBytes(size))
                line += String(decoding: try await readLine(), as: UTF8.self)
            }
            if line.hasPrefix(tag + " ") {
                let status = line.dropFirst(tag.count + 1)
                if status.hasPrefix("OK") { return reply }
                throw MailError.server(status.split(separator: " ", maxSplits: 1).last.map(String.init) ?? String(status))
            }
            reply.lines.append(line)
        }
    }

    private func send(_ text: String) async throws {
        let data = Data(text.utf8)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: MailError.connection(error.localizedDescription))
                } else {
                    cont.resume()
                }
            })
        }
    }

    private func receiveMore() async throws {
        let chunk: Data = try await withCheckedThrowingContinuation { cont in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { data, _, isComplete, error in
                if let data, !data.isEmpty {
                    cont.resume(returning: data)
                } else if let error {
                    cont.resume(throwing: MailError.connection(error.localizedDescription))
                } else if isComplete {
                    cont.resume(throwing: MailError.connection("The connection closed."))
                } else {
                    cont.resume(returning: Data())
                }
            }
        }
        buffer.append(chunk)
    }

    private func readLine() async throws -> Data {
        while true {
            if let range = buffer.range(of: Self.crlf) {
                let line = Data(buffer[buffer.startIndex..<range.lowerBound])
                buffer = Data(buffer[range.upperBound...])
                return line
            }
            try await receiveMore()
        }
    }

    private func readBytes(_ count: Int) async throws -> Data {
        while buffer.count < count { try await receiveMore() }
        let out = Data(buffer.prefix(count))
        buffer = Data(buffer.dropFirst(count))
        return out
    }

    // MARK: - Helpers

    static func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func literalSize(_ line: String) -> Int? {
        guard line.hasSuffix("}"), let open = line.lastIndex(of: "{") else { return nil }
        return Int(line[line.index(after: open)..<line.index(before: line.endIndex)])
    }

    static func lastQuoted(_ line: String) -> String? {
        guard line.hasSuffix("\"") else { return nil }
        let body = line.dropLast()
        guard let start = body.lastIndex(of: "\"") else { return nil }
        return String(body[body.index(after: start)...])
    }
}

/// Runs a block at most once, from any thread.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
    }
}

/// Opens emails from the hub. Keeps the ones already opened in memory.
actor MailService {
    static let shared = MailService()

    private var cache: [String: EmailMessage] = [:]

    func message(id: String) async throws -> EmailMessage {
        if let hit = cache[id] { return hit }
        guard let creds = GmailCredentials.load() else { throw MailError.notSetUp }
        let raw = try await Self.withConnection { imap in
            try await imap.login(creds.address, creds.password)
            let data = try await imap.fetch(messageID: id)
            await imap.logout()
            return data
        }
        let message = EmailMessage(raw: raw)
        cache[id] = message
        return message
    }

    func checkSignIn(address: String, password: String) async throws {
        try await Self.withConnection { imap in
            try await imap.login(address, password)
            await imap.logout()
        }
    }

    /// Opens a connection, runs `work`, and gives up after `timeout`.
    private static func withConnection<T: Sendable>(
        timeout: Duration = .seconds(25),
        _ work: @escaping @Sendable (IMAPConnection) async throws -> T
    ) async throws -> T {
        let imap = IMAPConnection()
        defer { imap.close() }
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await imap.open()
                return try await work(imap)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                imap.close()          // ends any read still waiting
                throw MailError.timeout
            }
            guard let first = try await group.next() else { throw MailError.timeout }
            group.cancelAll()
            return first
        }
    }
}
