import SwiftUI

/// Every invoice, receipt, statement, payment and refund email, kept for good:
/// by month with a total, filtered by category, searchable, and exportable as
/// a spreadsheet. Tap one to read the email; the PDF opens from Drive.
struct ReceiptsView: View {
    @Environment(ItemStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var category: String?           // nil = all
    @State private var query = ""
    @State private var openMail: Item?

    private var categories: [String] {
        var seen: [String] = []
        for r in store.receipts where !seen.contains(r.category) { seen.append(r.category) }
        let order = CategoryStore.all.map(\.name)
        return seen.sorted { (order.firstIndex(of: $0) ?? 99, $0) < (order.firstIndex(of: $1) ?? 99, $1) }
    }

    private var shown: [Receipt] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return store.receipts.filter { r in
            (category == nil || r.category == category)
                && (q.isEmpty || r.title.lowercased().contains(q) || r.vendor.lowercased().contains(q))
        }
    }

    private var months: [(month: Date, receipts: [Receipt])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: shown) { r in
            cal.date(from: cal.dateComponents([.year, .month], from: r.date ?? .distantPast)) ?? .distantPast
        }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }

    private var exportName: String {
        let what = category.map { VentureStyle.of($0).short } ?? "All"
        return "Receipts - \(what) - \(Date.now.formatted(.dateTime.year().month().day()))"
    }

    var body: some View {
        List {
            if !categories.isEmpty {
                Section {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            chip("All", selected: category == nil) { category = nil }
                            ForEach(categories, id: \.self) { name in
                                chip(VentureStyle.of(name).short, selected: category == name) {
                                    category = category == name ? nil : name
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .scrollIndicators(.hidden)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            if store.receiptsLoaded && store.receipts.isEmpty {
                ContentUnavailableView("No Receipts Yet", systemImage: "doc.text",
                                       description: Text("Invoices, receipts and statements from your email collect here as they arrive."))
            } else if !store.receiptsLoaded {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
            ForEach(months, id: \.month) { group in
                Section {
                    ForEach(group.receipts) { r in
                        Button { if r.link != nil { openMail = r.asItem } else if let pdf = r.pdf.flatMap(URL.init(string:)) { openURL(pdf) } } label: {
                            row(r)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if r.link != nil {
                                Button("Open Email", systemImage: "envelope") { openMail = r.asItem }
                            }
                            if let pdf = r.pdf.flatMap(URL.init(string:)) {
                                Button("Open PDF", systemImage: "doc.richtext") { openURL(pdf) }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(group.month == .distantPast ? "Undated" : group.month.formatted(.dateTime.month(.wide).year()))
                        Spacer()
                        let total = group.receipts.reduce(0) { $0 + $1.spend }
                        if total != 0 {
                            Text(total, format: .currency(code: "USD")).monospacedDigit()
                        }
                    }
                }
            }
            if !store.receipts.isEmpty {
                Text("Month totals add invoices and receipts and take off refunds. Statements and payments aren't added, so nothing counts twice.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .searchable(text: $query, prompt: "Search receipts")
        .navigationTitle("Receipts")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !shown.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: ReceiptsExport(receipts: shown, name: exportName),
                              preview: SharePreview("\(exportName).csv", image: Image(systemName: "tablecells"))) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .navigationDestination(item: $openMail) { EmailView(item: $0) }
        .refreshable { await store.loadReceipts() }
        .task { if !store.receiptsLoaded { await store.loadReceipts() } }
        .animation(.snappy, value: category)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Color.onInk : Color.primary)
                .background(selected ? Color.ink : Color(uiColor: .secondarySystemGroupedBackground), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private func row(_ r: Receipt) -> some View {
        HStack(spacing: 12) {
            VentureBadge(venture: r.category, size: 34, ring: nil)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(r.vendor.isEmpty ? r.title : r.vendor).font(.body.weight(.semibold)).lineLimit(1)
                    StatusTag(text: r.kindLabel, color: tagColor(r.kind))
                }
                Text(r.subject)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                if let amount = r.amount {
                    Text((r.kind == "refund" ? -amount : amount), format: .currency(code: "USD"))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(r.kind == "refund" ? Color.green : Color.primary)
                }
                HStack(spacing: 4) {
                    if r.pdf != nil {
                        Image(systemName: "doc.richtext.fill").foregroundStyle(.red)
                            .accessibilityLabel("PDF saved in Drive")
                    }
                    if let date = r.date {
                        Text(date.formatted(.dateTime.month(.abbreviated).day()))
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
    }

    private func tagColor(_ kind: String) -> Color {
        switch kind {
        case "invoice": .orange
        case "statement": .blue
        case "payment": .purple
        case "refund": .green
        default: .teal
        }
    }
}

/// A small coloured word: "Invoice", "Receipt"…
struct StatusTag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: .capsule)
            .fixedSize()
    }
}
