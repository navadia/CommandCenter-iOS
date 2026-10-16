import Foundation

/// A downloaded email, decoded into what the reader needs: who, when,
/// subject, and the HTML or plain-text body.
struct EmailMessage: Sendable {
    var subject = ""
    var fromName = ""
    var fromAddress = ""
    var date: Date?
    var html: String?
    var text: String?

    init(raw: Data) {
        // ISO-8859-1 maps every byte to one character, so the message can be
        // cut up as a string and turned back into the exact bytes later.
        let top = MIMEPart(String(data: raw, encoding: .isoLatin1) ?? "")
        subject = MIME.decodeHeader(top.headers["subject"] ?? "")
        (fromName, fromAddress) = MIME.splitAddress(MIME.decodeHeader(top.headers["from"] ?? ""))
        date = top.headers["date"].flatMap(MIME.parseDate)
        var html: String?
        var text: String?
        top.collect(html: &html, text: &text, depth: 0)
        self.html = html
        self.text = text
    }

    var hasRemoteImages: Bool {
        guard let html else { return false }
        return html.range(of: #"<img[^>]+src\s*=\s*["']?https?:"#,
                          options: [.regularExpression, .caseInsensitive]) != nil
            || html.range(of: #"url\(\s*["']?https?:"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// A self-contained page. Remote content (tracking pixels, images, fonts)
    /// is blocked by a Content-Security-Policy unless `showImages` is on.
    func page(showImages: Bool) -> String {
        let remote = showImages ? " https: http:" : ""
        let csp = "default-src 'none'; style-src 'unsafe-inline'\(remote); img-src data: cid:\(remote); "
            + "font-src \(showImages ? "https:" : "'none'")"
        let body = html ?? """
            <div style="white-space:pre-wrap">\(MIME.escapeHTML(text ?? "This email has no text."))</div>
            """
        return """
            <!doctype html><html><head><meta charset="utf-8">
            <meta http-equiv="Content-Security-Policy" content="\(csp)">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta name="color-scheme" content="light">
            <style>
            html,body{margin:0;background:#fff;color:#111}
            body{padding:12px 14px;font:-apple-system-body;-webkit-text-size-adjust:100%;overflow-wrap:anywhere}
            img{max-width:100%;height:auto}
            table{max-width:100%!important}
            </style></head><body>\(body)</body></html>
            """
    }
}

/// One MIME entity: headers plus its still-encoded body (one character per byte).
struct MIMEPart {
    let headers: [String: String]
    let body: String

    init(_ latin1: String) {
        let separator = latin1.range(of: "\r\n\r\n") ?? latin1.range(of: "\n\n")
        if let separator {
            headers = MIME.parseHeaders(String(latin1[..<separator.lowerBound]))
            body = String(latin1[separator.upperBound...])
        } else {
            headers = MIME.parseHeaders(latin1)
            body = ""
        }
    }

    var contentType: String { headers["content-type"] ?? "text/plain" }

    var mediaType: String {
        (contentType.components(separatedBy: ";").first ?? "")
            .trimmingCharacters(in: .whitespaces).lowercased()
    }

    var isAttachment: Bool {
        (headers["content-disposition"] ?? "").lowercased().hasPrefix("attachment")
    }

    /// Body bytes after undoing base64 / quoted-printable.
    var decodedBytes: Data {
        let bytes = body.data(using: .isoLatin1) ?? Data()
        switch (headers["content-transfer-encoding"] ?? "").trimmingCharacters(in: .whitespaces).lowercased() {
        case "base64": return Data(base64Encoded: bytes, options: .ignoreUnknownCharacters) ?? MIME.lenientBase64(bytes)
        case "quoted-printable": return MIME.decodeQuotedPrintable(bytes)
        default: return bytes
        }
    }

    var decodedText: String {
        MIME.string(decodedBytes, charset: MIME.parameter(contentType, "charset"))
    }

    /// Walks the tree and keeps the first HTML and first plain-text body.
    func collect(html: inout String?, text: inout String?, depth: Int) {
        guard depth < 10, !isAttachment else { return }
        let type = mediaType
        if type.hasPrefix("multipart/"), let boundary = MIME.parameter(contentType, "boundary") {
            var chunks = body.components(separatedBy: "--" + boundary)
            guard chunks.count > 1 else { return }
            chunks.removeFirst()                       // preamble
            for chunk in chunks {
                if chunk.hasPrefix("--") { break }     // closing delimiter
                var part = chunk
                if part.hasPrefix("\r\n") || part.hasPrefix("\n") { part.removeFirst() }
                MIMEPart(part).collect(html: &html, text: &text, depth: depth + 1)
            }
        } else if type == "message/rfc822" {
            MIMEPart(String(data: decodedBytes, encoding: .isoLatin1) ?? "")
                .collect(html: &html, text: &text, depth: depth + 1)
        } else if type == "text/html" {
            if html == nil { html = decodedText }
        } else if type == "text/plain" || type.isEmpty {
            if text == nil { text = decodedText }
        }
    }
}

enum MIME {
    static func parseHeaders(_ block: String) -> [String: String] {
        var out: [String: String] = [:]
        var lastKey: String?
        for rawLine in block.components(separatedBy: "\n") {
            let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
            if let first = line.first, first == " " || first == "\t" {
                if let key = lastKey { out[key, default: ""] += " " + line.trimmingCharacters(in: .whitespaces) }
            } else if let colon = line.firstIndex(of: ":") {
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if out[key] == nil {
                    out[key] = value
                    lastKey = key
                } else {
                    lastKey = nil          // repeated header (Received…): keep the first
                }
            }
        }
        return out
    }

    /// `charset` from `text/html; charset="utf-8"`, case-insensitively.
    static func parameter(_ header: String, _ name: String) -> String? {
        for piece in header.components(separatedBy: ";").dropFirst() {
            let pair = piece.trimmingCharacters(in: .whitespaces)
            guard let eq = pair.firstIndex(of: "=") else { continue }
            guard pair[..<eq].trimmingCharacters(in: .whitespaces).lowercased() == name else { continue }
            var value = pair[pair.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            return value
        }
        return nil
    }

    static func decodeQuotedPrintable(_ data: Data) -> Data {
        let b = [UInt8](data)
        var out = Data()
        out.reserveCapacity(b.count)
        var i = 0
        while i < b.count {
            if b[i] == 0x3D {                                        // "="
                if i + 1 < b.count, b[i + 1] == 0x0A { i += 2; continue }            // soft break \n
                if i + 2 < b.count, b[i + 1] == 0x0D, b[i + 2] == 0x0A { i += 3; continue }  // soft break \r\n
                if i + 2 < b.count, let hi = hex(b[i + 1]), let lo = hex(b[i + 2]) {
                    out.append(hi << 4 | lo)
                    i += 3
                    continue
                }
            }
            out.append(b[i])
            i += 1
        }
        return out
    }

    /// Base64 that was cut short (partial download): decode what's complete.
    static func lenientBase64(_ data: Data) -> Data {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
        var clean = data.filter { allowed.contains($0) }
        clean = clean.prefix(clean.count - clean.count % 4)
        return Data(base64Encoded: Data(clean)) ?? Data()
    }

    private static func hex(_ c: UInt8) -> UInt8? {
        switch c {
        case 48...57: c - 48
        case 65...70: c - 55
        case 97...102: c - 87
        default: nil
        }
    }

    static func string(_ data: Data, charset: String?) -> String {
        if let charset = charset?.trimmingCharacters(in: .whitespaces).lowercased(), !charset.isEmpty {
            let cf = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            if cf != kCFStringEncodingInvalidId {
                let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
                if let s = String(data: data, encoding: encoding) { return s }
            }
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(decoding: data, as: UTF8.self)
    }

    /// Undoes RFC 2047 words like `=?UTF-8?B?…?=` and raw UTF-8 in headers.
    static func decodeHeader(_ latin1: String) -> String {
        let bytes = latin1.data(using: .isoLatin1) ?? Data()
        var s = String(data: bytes, encoding: .utf8) ?? latin1
        // Whitespace between two encoded words is not part of the text.
        s = s.replacingOccurrences(of: #"\?=\s+=\?"#, with: "?==?", options: .regularExpression)
        guard let re = try? NSRegularExpression(pattern: #"=\?([^?]+)\?([BbQq])\?([^?]*)\?="#) else { return s }
        var result = ""
        var last = s.startIndex
        for match in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let whole = Range(match.range, in: s),
                  let charset = Range(match.range(at: 1), in: s),
                  let mode = Range(match.range(at: 2), in: s),
                  let payload = Range(match.range(at: 3), in: s) else { continue }
            result += s[last..<whole.lowerBound]
            let text = String(s[payload])
            let data = s[mode].uppercased() == "B"
                ? (Data(base64Encoded: text, options: .ignoreUnknownCharacters) ?? Data())
                : decodeQuotedPrintable(Data(text.replacingOccurrences(of: "_", with: " ").utf8))
            let cs = String(s[charset]).components(separatedBy: "*").first   // drop RFC 2231 language
            result += string(data, charset: cs)
            last = whole.upperBound
        }
        result += s[last...]
        return result
    }

    /// `"GEICO - geico at e.geico.com" <x@y>` -> ("GEICO", "x@y").
    static func splitAddress(_ value: String) -> (String, String) {
        var name = value
        var address = ""
        if let open = value.lastIndex(of: "<"), let close = value.lastIndex(of: ">"), open < close {
            address = String(value[value.index(after: open)..<close])
            name = String(value[..<open])
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\" ").union(.whitespaces))
        // SimpleLogin puts the real sender in the name: "Name - local at domain".
        if let r = name.range(of: #" - \S+ at \S+$"#, options: .regularExpression) {
            name = String(name[..<r.lowerBound])
        }
        if name.isEmpty { name = address }
        return (name, address)
    }

    static func parseDate(_ value: String) -> Date? {
        let cleaned = value.replacingOccurrences(of: #"\s*\([^)]*\)\s*$"#, with: "", options: .regularExpression)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z"] {
            f.dateFormat = format
            if let d = f.date(from: cleaned) { return d }
        }
        return nil
    }

    static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
