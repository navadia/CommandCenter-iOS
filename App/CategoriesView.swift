import SwiftUI

/// Settings › Categories: every category with its badge and "send here"
/// rules. Tap one to edit it, + to add one.
struct CategoriesView: View {
    @Environment(ItemStore.self) private var store
    @State private var editing: Category?
    @State private var loading = false

    private var list: [Category] { CategoryStore.all }

    var body: some View {
        List {
            if list.isEmpty {
                ContentUnavailableView {
                    Label("No Categories Yet", systemImage: "square.grid.2x2")
                } description: {
                    Text(store.categoriesMissing
                         ? "The email sorter creates the Categories table in Notion on its next run (every half hour). Pull to check again."
                         : "Pull to load them from Notion.")
                }
            } else {
                Section {
                    ForEach(list) { category in
                        Button { editing = category } label: { row(category) }
                            .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Email is sorted by these rules every half hour. Tasks you add or edit can go to any category.")
                }
            }
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Category", systemImage: "plus") {
                    editing = Category(id: "", name: "", order: (list.map(\.order).max() ?? 0) + 1)
                }
                .disabled(list.isEmpty)
            }
        }
        .refreshable { await store.loadCategories() }
        .task {
            if list.isEmpty { await store.loadCategories() }
            if let name = DemoData.argument(after: "-demoCategory"), let c = CategoryStore.find(name) { editing = c }
        }
        .sheet(item: $editing) { CategoryEditor(category: $0) }
    }

    private func row(_ c: Category) -> some View {
        let open = store.items.filter { $0.venture == c.name }.count
        return HStack(spacing: 12) {
            VentureBadge(venture: c.name, size: 32, ring: nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(VentureStyle.of(c.name).short).font(.body.weight(.medium))
                Text(summary(c)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if open > 0 {
                Text("\(open)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
    }

    private func summary(_ c: Category) -> String {
        guard let first = c.rules.first else { return "No email rules" }
        let text = "\(CategoryEditor.label(first.kind)) \(first.needle)"
        return c.rules.count == 1 ? text : "\(text) + \(c.rules.count - 1) more"
    }
}

/// Add or edit one category: name, icon, color, "send here" rules, a note
/// for Apple Intelligence; delete moves its open items somewhere else first.
struct CategoryEditor: View {
    let category: Category

    @Environment(ItemStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Category
    @State private var moveTo = "Personal"
    @State private var saving = false
    @State private var confirmDelete = false
    @State private var error: String?

    init(category: Category) {
        self.category = category
        var d = category
        // Show the look it has today, so saving keeps it.
        if !d.name.isEmpty {
            if d.icon.isEmpty { d.icon = VentureStyle.of(d.name).symbol }
            if d.color.isEmpty { d.color = VentureColors.pickedName(for: VentureStyle.of(d.name).short) ?? VentureColors.standardName(d.name) }
        } else {
            d.icon = "tray.fill"
            d.color = "Blue"
        }
        _draft = State(initialValue: d)
    }

    private var isNew: Bool { category.id.isEmpty }
    private var others: [Category] { CategoryStore.all.filter { $0.id != category.id } }
    private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var nameTaken: Bool { others.contains { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame } }
    private var previewColor: Color { VentureColors.palette.first { $0.name == draft.color }?.color ?? .gray }

    static func label(_ kind: Category.Rule.Kind) -> String {
        switch kind {
        case .from: "From"
        case .to: "Sent to"
        case .subject: "Subject has"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(previewColor.gradient)
                            .frame(width: 44, height: 44)
                            .overlay { Image(systemName: draft.icon).font(.title3.weight(.semibold)).foregroundStyle(.white) }
                        TextField("Category name", text: $draft.name)
                            .font(.title3.weight(.semibold))
                            .textInputAutocapitalization(.words)
                    }
                    .padding(.vertical, 4)
                } footer: {
                    if nameTaken { Text("There's already a category with that name.").foregroundStyle(.red) }
                    else if !isNew && trimmedName != category.name && !trimmedName.isEmpty {
                        Text("Renaming moves its open items to the new name. Done items keep \(category.name) as history.")
                    }
                }

                Section {
                    ForEach($draft.rules) { $rule in
                        HStack(spacing: 8) {
                            Picker("Rule", selection: $rule.kind) {
                                ForEach(Category.Rule.Kind.allCases, id: \.self) { Text(Self.label($0)).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                            TextField(placeholder(rule.kind), text: $rule.needle)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(rule.kind == .subject ? .default : .emailAddress)
                        }
                    }
                    .onDelete { draft.rules.remove(atOffsets: $0) }
                    Button("Add Rule", systemImage: "plus.circle.fill") {
                        draft.rules.append(Category.Rule(kind: .from, needle: ""))
                    }
                } header: {
                    Text("Send here")
                } footer: {
                    Text("Email lands in this category when the From line, the address it was sent to, or the subject contains the text. \"From\" and \"Subject has\" rules win over \"Sent to\". Checked every half hour, for new email.")
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 10) {
                        ForEach(CategoryStore.icons, id: \.self) { icon in
                            let on = draft.icon == icon
                            Button { draft.icon = icon } label: {
                                Image(systemName: icon)
                                    .font(.body.weight(.semibold))
                                    .frame(width: 38, height: 38)
                                    .foregroundStyle(on ? .white : .primary)
                                    .background(on ? previewColor : Color(uiColor: .tertiarySystemFill),
                                                in: .rect(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(icon)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 10) {
                        ForEach(VentureColors.palette, id: \.name) { option in
                            let on = draft.color == option.name
                            Button { draft.color = option.name } label: {
                                Circle().fill(option.color)
                                    .frame(width: 30, height: 30)
                                    .overlay { if on { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white) } }
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(on ? option.color : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(option.name)\(on ? ", selected" : "")")
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    TextField("e.g. The store I run: vendors, staff, store bills", text: $draft.about, axis: .vertical)
                        .lineLimit(1...3)
                } header: {
                    Text("About")
                } footer: {
                    Text("Helps Apple Intelligence pick this category when you add a task by voice or screenshot.")
                }

                if !isNew {
                    Section {
                        Picker("Move its open items to", selection: $moveTo) {
                            ForEach(others.map(\.name), id: \.self) { Text(VentureStyle.of($0).short).tag($0) }
                        }
                        Button("Delete Category", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Its email rules go too, so new mail to those addresses lands in Personal.")
                    }
                }
            }
            .disabled(saving)
            .navigationTitle(isNew ? "New Category" : "Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Save", systemImage: "checkmark") { Task { await save() } }
                            .buttonStyle(.glassProminent)
                            .disabled(trimmedName.isEmpty || nameTaken)
                    }
                }
            }
            .confirmationDialog("Delete \(category.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete and Move Items to \(VentureStyle.of(moveTo).short)", role: .destructive) {
                    Task { await delete() }
                }
            } message: {
                Text("Open items move to \(VentureStyle.of(moveTo).short). Done items keep \(category.name) as history.")
            }
            .alert("Couldn't save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
            .onAppear {
                if !others.contains(where: { $0.name == moveTo }) { moveTo = others.first?.name ?? "Personal" }
            }
        }
    }

    private func placeholder(_ kind: Category.Rule.Kind) -> String {
        switch kind {
        case .from: "mclane.com"
        case .to: "store@example.com"
        case .subject: "invoice"
        }
    }

    private func save() async {
        var final = draft
        final.name = trimmedName
        final.rules = final.rules
            .map { Category.Rule(kind: $0.kind, needle: $0.needle.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.needle.isEmpty }
        saving = true
        defer { saving = false }
        do {
            try await store.save(final, renamedFrom: isNew ? nil : category.name)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete() async {
        saving = true
        defer { saving = false }
        do {
            try await store.delete(category, movingTo: moveTo)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
