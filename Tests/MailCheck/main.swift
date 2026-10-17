// Runs on the build Mac before every app build:
//   swiftc App/Mail/EmailMessage.swift Tests/MailCheck/main.swift -o mailcheck && ./mailcheck
import Foundation

var failures = 0
func expect(_ ok: Bool, _ what: String) {
    print(ok ? "ok   \(what)" : "FAIL \(what)")
    if !ok { failures += 1 }
}
func msg(_ s: String, crlf: Bool = true) -> EmailMessage {
    let text = crlf ? s.replacingOccurrences(of: "\n", with: "\r\n") : s
    return EmailMessage(raw: text.data(using: .isoLatin1) ?? Data(text.utf8))
}

// 1. multipart/alternative, quoted-printable UTF-8 HTML, encoded subject, SimpleLogin sender
let m1 = msg("""
From: "GEICO - geico at e.geico.com" <geico_at_e_geico_com_abc@simplelogin.co>
Subject: =?UTF-8?B?WW91ciBwYXltZW50IGlzIGR1ZSDinIU=?=
Date: Tue, 14 Oct 2026 09:30:00 -0500 (CDT)
Message-ID: <abc123@geico.com>
MIME-Version: 1.0
Content-Type: multipart/alternative; boundary="b1"

--b1
Content-Type: text/plain; charset=utf-8
Content-Transfer-Encoding: quoted-printable

Pay $143 by Oct 20 =E2=80=94 thanks
--b1
Content-Type: text/html; charset="UTF-8"
Content-Transfer-Encoding: quoted-printable

<p>Pay <b>$143</b> by Oct 20 =E2=80=94 tha=
nks</p><img src=3D"https://track.example.com/p.gif">
--b1--
""")
expect(m1.subject == "Your payment is due ✅", "encoded-word subject -> \(m1.subject)")
expect(m1.fromName == "GEICO", "SimpleLogin name -> \(m1.fromName)")
expect(m1.fromAddress.hasSuffix("@simplelogin.co"), "address")
expect(m1.date != nil, "date with (CDT) comment")
expect(m1.html?.contains("Pay <b>$143</b> by Oct 20 — thanks</p>") == true, "QP html + soft break")
expect(m1.text == "Pay $143 by Oct 20 — thanks\r\n", "plain text part")
expect(m1.hasRemoteImages, "detects remote image")
expect(m1.page(showImages: false).contains("img-src data: cid:;"), "remote images blocked by default")
expect(m1.page(showImages: true).contains("img-src data: cid: https: http:"), "images allowed when asked")

// 2. nested mixed > alternative, base64 ISO-8859-1, attachment skipped, Q-encoded subject
let html2 = Data("<p>Caf\u{e9} r\u{e9}serv\u{e9}</p>".data(using: .isoLatin1)!).base64EncodedString(options: .lineLength76Characters)
let m2 = msg("""
From: Delta <noreply@delta.com>
Subject: =?iso-8859-1?Q?Votre_r=E9servation?= =?iso-8859-1?Q?_confirm=E9e?=
Content-Type: multipart/mixed; boundary=outer

--outer
Content-Type: multipart/alternative; boundary="inner"

--inner
Content-Type: text/html; charset=ISO-8859-1
Content-Transfer-Encoding: base64

\(html2)
--inner--

--outer
Content-Type: text/html; name="ticket.html"
Content-Disposition: attachment; filename="ticket.html"

<p>ATTACHMENT</p>
--outer--
""")
expect(m2.subject == "Votre réservation confirmée", "Q words joined -> \(m2.subject)")
expect(m2.html?.contains("Café réservé") == true, "base64 latin-1 html")
expect(m2.html?.contains("ATTACHMENT") == false, "attachment ignored")
expect(m2.fromName == "Delta" && m2.fromAddress == "noreply@delta.com", "plain sender")

// 3. single-part plain text, LF line endings, raw UTF-8 header, folded header
let m3 = msg("""
From: =?utf-8?q?Shop_Admin?= <admin@example.com>
Subject: Server alarm:
 disk 91% \u{2014} check
Content-Type: text/plain

Line one
Line <two>
""", crlf: false)
expect(m3.subject == "Server alarm: disk 91% — check", "folded + raw utf-8 subject -> \(m3.subject)")
expect(m3.fromName == "Shop Admin", "q-encoded name")
expect(m3.html == nil && m3.text?.hasPrefix("Line one") == true, "plain only")
expect(m3.page(showImages: false).contains("Line &lt;two&gt;"), "plain text escaped")
expect(!m3.hasRemoteImages, "no remote images")

// 4. truncated base64 (partial download) still decodes what arrived
let long = String(repeating: "Hello world. ", count: 50)
var b64 = Data(long.utf8).base64EncodedString()
b64.removeLast(7)
let m4 = msg("""
Subject: Cut
Content-Type: text/plain; charset=utf-8
Content-Transfer-Encoding: base64

\(b64)
""")
expect(m4.text?.hasPrefix("Hello world. Hello world.") == true, "truncated base64")

// 5. forwarded message/rfc822
let m5 = msg("""
Subject: Fwd: receipt
Content-Type: multipart/mixed; boundary=z

--z
Content-Type: message/rfc822

Subject: receipt
Content-Type: text/html; charset=utf-8

<p>Inner receipt</p>
--z--
""")
expect(m5.html?.contains("Inner receipt") == true, "message/rfc822 body")

// 6. card previews: plain text preferred; HTML stripped of styles, tags, links and entities
expect(m1.previewText == "Pay $143 by Oct 20 — thanks", "preview from text part -> \(m1.previewText)")
expect(m2.previewText == "Café réservé", "preview from html -> \(m2.previewText)")
let m6 = msg("""
Subject: Html only
Content-Type: text/html; charset=utf-8

<html><head><style>p{color:red}</style></head><body><p>Hi&nbsp;Parth,</p><p>Your bill of &#36;167 is ready &amp; due Oct 24.</p><a href="https://x.example/track">https://x.example/track</a></body></html>
""")
expect(m6.previewText == "Hi Parth, Your bill of $167 is ready & due Oct 24.", "html preview -> \(m6.previewText)")

print(failures == 0 ? "\nAll email parser checks passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
