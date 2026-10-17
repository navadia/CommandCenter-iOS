import SwiftUI

/// Check what the app read, fix anything, save to Notion. Opened by the "+"
/// button, the Action button (Add Task) and Back Tap (Add Task from Screenshot).
struct AddTaskSheet: View {
    let request: CaptureRequest

    @Environment(ItemStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var draft = TaskDraft()
    @State private var guessedVenture = ""
    @State private var readText = ""
    @State private var amountText = ""
    @State private var hasDue = false
    @State private var dueDate = Date.now
    @State private var reading = true
    @State private var saving = false
    @State private var error: String?
    @FocusState private var titleFocused: Bool

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
                        Button("Add", systemImage: "checkmark") { Task { await save() } }
                            .buttonStyle(.glassProminent)
                            .disabled(reading || draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .alert("Couldn't add it", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
        .task { await read() }
    }

    private var title: String {
        switch request.kind {
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

    private func save() async {
        var final = draft
        final.amount = Double(amountText.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: ""))
        final.due = hasDue ? dueDate : nil
        saving = true
        defer { saving = false }
        do {
            try await store.add(final, kind: request.kind)
            // A corrected venture is remembered for this sender.
            if final.venture != guessedVenture, !final.from.isEmpty {
                VentureMemory.remember(from: final.from, venture: final.venture)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
