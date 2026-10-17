import Foundation

/// Sample items for screenshots on the build Mac's simulator
/// (launch argument -demoData). Never used on a phone.
enum DemoData {
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-demoData") }

    static func argument(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static var items: [Item] {
        let day = { (offset: Int) in
            Item.dayFormatter.string(from: Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now)
        }
        let ago = { (hours: Double) in
            ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(-hours * 3600))
        }
        let link = { (id: String) in "https://mail.google.com/mail/u/0/#search/rfc822msgid:\(id)" }
        return [
            Item(id: "d1", title: "GEICO: Your payment is due", type: "money", venture: "Personal",
                 amount: 143, due: day(0), trial: false, link: link("a1"), domain: "geico.com", created: ago(5)),
            Item(id: "d2", title: "Trial: Notion: Your Plus trial ends today", type: "money", venture: "Pseudo",
                 amount: 10, due: day(0), trial: true, link: link("a2"), domain: "notion.so", created: ago(20)),
            Item(id: "d3", title: "Qatar Airways: Check-in opens · DFW → DOH", type: "travel", venture: "Travel",
                 amount: nil, due: day(2), trial: false, link: link("a3"), domain: "qatarairways.com", created: ago(30)),
            Item(id: "d4", title: "AWS: CloudWatch alarm: disk at 91%", type: "todo", venture: "Vishramo",
                 amount: nil, due: nil, trial: false, link: link("a4"), domain: "amazonaws.com", created: ago(2)),
            Item(id: "d5", title: "Vercel: Deployment failed on main", type: "todo", venture: "Vishramo",
                 amount: nil, due: nil, trial: false, link: link("a5"), domain: "vercel.com", created: ago(26)),
            Item(id: "d6", title: "Express Energy: Your October bill is ready", type: "money", venture: "Shared/Household",
                 amount: 167, due: day(7), trial: false, link: link("a6"), domain: "expressenergy.com", created: ago(40)),
            Item(id: "d7", title: "Cloudflare: Renew your SSL certificate", type: "todo", venture: "Credaxe",
                 amount: nil, due: nil, trial: false, link: link("a7"), domain: "cloudflare.com", created: ago(70)),
            Item(id: "d8", title: "McLane: Invoice #4471 is ready", type: "money", venture: "7-Eleven",
                 amount: 1284, due: day(4), trial: false, link: link("a8"), domain: "mclaneco.com", created: ago(50)),
            Item(id: "d9", title: "Capital One: Your statement is ready", type: "money", venture: "Personal",
                 amount: 412, due: day(11), trial: false, link: link("a9"), domain: "capitalone.com", created: ago(80)),
            Item(id: "d10", title: "Greenhouse: Share your interview availability", type: "todo", venture: "Job Applications",
                 amount: nil, due: nil, trial: false, link: link("a10"), domain: "greenhouse.io", created: ago(100)),
            Item(id: "d11", title: "Priya: Diwali dinner plans", type: "todo", venture: "Family/General",
                 amount: nil, due: nil, trial: false, link: link("a11"), domain: nil, created: ago(120)),
            Item(id: "d12", title: "Reminder: Your Walgreens Photo order is ready", type: "todo", venture: "Family/General",
                 amount: nil, due: nil, trial: false, link: link("a12"), domain: "walgreens.com", created: ago(200),
                 source: "Walgreens Photo | <family@example.com>"),
            Item(id: "d13", title: "Get Wi-Fi done for 7-Eleven", type: "todo", venture: "7-Eleven",
                 amount: nil, due: nil, trial: false, link: nil, domain: nil, created: ago(2400), source: "claude"),
        ]
    }
}
