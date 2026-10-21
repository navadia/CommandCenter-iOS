import SwiftUI

/// Check what the app read, fix anything, save to Notion. Opened by the "+"
/// button, the Action button (Add Task) and Back Tap (Add Task from Screenshot),
/// and, with an existing item, as the Edit sheet (long-press › Edit).
struct AddTaskSheet: View {
    let request: CaptureRequest

    @Environment(ItemStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var draft = TaskDraft()
    @State private var guessedVenture = ""
    @State private var original = TaskDraft()
    @State private var readText = ""
    @State private var amountText = ""
    @State private var hasDue = false
    @State private var dueDate = Date.now
    @State private var reading = true
    @State private var saving = false
    @State private var error: String?
    @FocusState private var titleFocused: Bool
    @State private var ruleOffer: (needle: String, venture: String)?
    @State private var showRuleOffer = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("From (optional)", text: $draft.from)
                        .textInputAutocapitalization(.words)
                    TextField("What needs doing", text: $draft.title, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($titleFocused)
                } footer: {
                    if !reading, !readText.isEmpty {
                        Text(draft.readBy == .model ? "Filled in by Apple Intelligence on this iPhone. Check it before saving."
                                                     : "Filled in by simple rules. Check it before saving.")
                    }
                }

                Section {
                    Picker(selection: $draft.venture) {
                        ForEach(ventureChoices, id: \.self) { venture in
                            HStack(spacing: 10) {
                                VentureBadge(venture: venture, size: 24, ring: nil)
                                Text(VentureStyle.of(venture).short)
                            }
                            .tag(venture)
                        }
                    } label: {
                        Text("Venture")
                    }
                    .pickerStyle(.navigationLink)

                    Picker("Type", selection: $draft.type) {
                        Text("To-do").tag("todo")
                        Text("Money").tag("money")
                        Text("Travel").tag("travel")
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                }

                Section {
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("$0", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                    }
                    Toggle("Due date", isOn: $hasDue.animation())
                    if hasDue {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                    }
                }

                if editing != nil {
                    Section {
                        Button("Mark Done", systemImage: "checkmark.circle") {
                            if let item = editing { Task { await store.markDone([item.id]) } }
                            dismiss()
                        }
                    }
                }

                if !readText.isEmpty && isImage {
                    Section("What the screenshot says") {
                        Text(readText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(12)
                            .textSelection(.enabled)
                    }
                }
            }
            .disabled(reading || saving)
            .overlay {
                if reading {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(readingLabel).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .glassEffect(in: .rect(cornerRadius: 22))
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button(editing == nil ? "Add" : "Save", systemImage: "checkmark") { Task { await save() } }
                            .buttonStyle(.glassProminent)
                            .disabled(reading || draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .alert(ruleOfferTitle, isPresented: $showRuleOffer) {
                Button("Always") {
                    guard let offer = ruleOffer else { return }
                    Task {
                        try? await store.alwaysSend(from: offer.needle, to: offer.venture)
                        dismiss()
                    }
                }
                Button("Just This One", role: .cancel) { dismiss() }
            } message: {
                Text("New email from \(ruleOffer?.needle ?? "") will land in \(VentureStyle.of(ruleOffer?.venture ?? "").short). You can change it in Settings › Categories.")
            }
            .alert(editing == nil ? "Couldn't add it" : "Couldn't save it", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
        .task { await read() }
    }

    private var editing: Item? {
        if case .edit(let item) = request.input { return item }
        return nil
    }

    private var title: String {
        if editing != nil { return "Edit Task" }
        return switch request.kind {
        case .screenshot: "Add from Screen"
        case .voice: "Add Task"
        case .typed: "New Task"
        }
    }

    private var readingLabel: String {
        isImage ? "Reading the screenshot…" : "Reading…"
    }

    private var isImage: Bool {
        if case .image = request.input { return true }
        return false
    }

    /// The usual ventures, plus whatever the draft or the board has.
    private var ventureChoices: [String] {
        var list = TaskDraft.ventures
        for extra in [draft.venture] + store.board.ventures.map(\.venture) where !list.contains(extra) && extra != "HotelOS" {
            list.append(extra)
        }
        return list
    }

    private func read() async {
        switch request.input {
        case .text(let words):
            readText = words
        case .image(let data):
            readText = (try? await TaskReader.text(in: data)) ?? ""
        case .edit(let item):
            fill(from: item)
            return
        }
        if !readText.isEmpty {
            draft = await TaskReader.draft(from: readText, kind: request.kind)
            amountText = draft.amount.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? ""
            if let due = draft.due { dueDate = due; hasDue = true }
        } else if isImage {
            error = "No text found on that screenshot. Type the task instead."
        }
        guessedVenture = draft.venture
        reading = false
        if draft.title.isEmpty { titleFocused = true }
    }

    /// The Edit sheet starts from the item as it is.
    private func fill(from item: Item) {
        var d = TaskDraft()
        if item.subject.isEmpty { d.title = item.sender } else { d.from = item.sender; d.title = item.subject }
        d.type = TaskDraft.types.contains(item.type) ? item.type : "todo"
        d.venture = item.venture == "HotelOS" ? "Vishramo" : item.venture
        d.amount = item.amount
        d.due = item.due.flatMap { Item.dayFormatter.date(from: String($0.prefix(10))) }
        draft = d
        original = d
        amountText = d.amount.map { $0.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) } ?? ""
        if let due = d.due { dueDate = due; hasDue = true }
        guessedVenture = d.venture
        reading = false
    }

    private func save() async {
        var final = draft
        final.amount = Double(amountText.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: ""))
        final.due = hasDue ? dueDate : nil
        saving = true
        defer { saving = false }
        do {
            if let item = editing {
                try await store.update(item, changes(from: final, item: item))
                // Moved to another category: offer to send this sender's mail there from now on.
                if final.venture != original.venture, let needle = senderNeedle(item, final),
                   let target = CategoryStore.find(final.venture),
                   !target.rules.contains(where: { $0.kind == .from && $0.needle.lowercased() == needle.lowercased() }) {
                    ruleOffer = (needle, final.venture)
                    showRuleOffer = true
                    return
                }
            } else {
                try await store.add(final, kind: request.kind)
            }
            // A corrected venture is remembered for this sender.
            if final.venture != guessedVenture, !final.from.isEmpty {
                VentureMemory.remember(from: final.from, venture: final.venture)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Only what was actually changed goes to Notion, so the parser's title,
    /// a due time, etc. stay as they were.
    private func changes(from final: TaskDraft, item: Item) -> NotionClient.Changes {
        var c = NotionClient.Changes()
        let day = { (date: Date?) in date.map { Item.dayFormatter.string(from: $0) } }
        if final.from != original.from || final.title != original.title { c.title = final.notionTitle }
        if final.type != original.type { c.type = final.type }
        if final.venture != original.venture { c.venture = final.venture }
        if final.amount != original.amount { c.amount = .some(final.amount) }
        if day(final.due) != day(original.due) { c.due = .some(day(final.due)) }
        return c
    }

    private var ruleOfferTitle: String {
        guard let offer = ruleOffer else { return "" }
        return "Always send \(offer.needle) to \(VentureStyle.of(offer.venture).short)?"
    }

    /// What identifies this sender in a From line: the site (geico.com) when
    /// the email sorter recorded it, else the sender's name. Nothing for tasks
    /// added by hand.
    private func senderNeedle(_ item: Item, _ final: TaskDraft) -> String? {
        if let domain = item.domain, !domain.isEmpty { return domain }
        guard item.messageID != nil else { return nil }
        let name = final.from.trimmingCharacters(in: .whitespaces)
        return name.count >= 3 ? name : nil
    }
}
