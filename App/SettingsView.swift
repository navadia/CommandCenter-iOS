import SwiftUI

struct SettingsView: View {
    @Environment(ItemStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var token = ""
    @State private var savedIn: String?
    @State private var isSaving = false

    @State private var gmailAddress = GmailCredentials.savedAddress
    @State private var gmailPassword = ""
    @State private var check: CheckState = .idle
    @State private var editingColor: String?
    @AppStorage(GlassPreference.key, store: SharedStore.defaults) private var frost = GlassPreference.standard
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    enum CheckState: Equatable {
        case idle, checking, ok
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(store.hasToken ? "Saved · type to replace" : "ntn_…", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                } header: {
                    Text("Notion Token")
                } footer: {
                    Text("The same token your Scriptable widget uses. It stays on this iPhone and is shared only with the Command Center widget.")
                }

                Section {
                    TextField("Hub address (name@gmail.com)", text: $gmailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                    SecureField(store.hasGmail ? "App password saved · type to replace" : "16-letter app password",
                                text: $gmailPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                    Button {
                        Task { await checkSignIn() }
                    } label: {
                        HStack {
                            Text("Check Sign-In")
                            Spacer()
                            checkStatus
                        }
                    }
                    .disabled(check == .checking || gmailAddress.trimmed.isEmpty
                              || (gmailPassword.trimmed.isEmpty && !store.hasGmail))
                    if case .failed(let reason) = check {
                        Text(reason)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Gmail Hub")
                } footer: {
                    Text("Lets the app open emails. Use the hub Gmail that collects your mail and the same app password the parser uses (Google Account › Security › App passwords). It's kept in this iPhone's keychain. The app only reads; it never marks mail as read or changes anything.")
                }

                if store.hasToken || store.hasGmail {
                    Section {
                        if store.hasToken {
                            Button("Remove Notion Token", role: .destructive) {
                                TokenStore.delete()
                                store.hasToken = false
                                savedIn = nil
                            }
                        }
                        if store.hasGmail {
                            Button("Remove Gmail Password", role: .destructive) {
                                GmailCredentials.delete()
                                store.hasGmail = false
                                check = .idle
                            }
                        }
                    }
                }

                Section {
                    ForEach(colorVentures, id: \.self) { venture in
                        VentureColorRow(venture: venture, editing: $editingColor)
                    }
                } header: {
                    Text("Venture Colors")
                } footer: {
                    Text("Tap a venture to pick its color. It changes everywhere: the app, the badges and the widget. Tap the selected color again to go back to the standard one.")
                }

                Section {
                    glassPreview
                    VStack(alignment: .leading, spacing: 6) {
                        Slider(value: $frost, in: 0...1) {
                            Text("Glass")
                        } minimumValueLabel: {
                            Text("Clear").font(.caption)
                        } maximumValueLabel: {
                            Text("Solid").font(.caption)
                        }
                        .disabled(reduceTransparency)
                        if abs(frost - GlassPreference.standard) > 0.01 && !reduceTransparency {
                            Button("Back to standard") { frost = GlassPreference.standard }
                                .font(.footnote)
                        }
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text(reduceTransparency
                         ? "Reduce Transparency is on in your iPhone settings, so the app is solid. Turn it off in Settings › Accessibility › Display & Text Size to use glass."
                         : "How see-through the cards and email tiles are, everywhere in the app. It turns solid by itself when Reduce Transparency is on in iPhone Settings › Accessibility. The buttons and bars follow iPhone's own Liquid Glass setting in Display & Brightness.")
                }

                Section("Status") {
                    LabeledContent("Notion") {
                        Text(store.hasToken ? (store.errorMessage == nil ? "Connected" : "Error") : "Not set")
                            .foregroundStyle(store.hasToken && store.errorMessage == nil ? .green : .secondary)
                    }
                    LabeledContent("Gmail") {
                        Text(store.hasGmail ? "Saved" : "Not set")
                            .foregroundStyle(store.hasGmail ? .green : .secondary)
                    }
                    if let savedIn {
                        LabeledContent("Token stored in", value: savedIn)
                    }
                    if let date = store.lastUpdated {
                        LabeledContent("Last updated", value: date.formatted(date: .omitted, time: .shortened))
                    }
                    LabeledContent("Shared storage", value: SharedStore.isGroupWorking ? "Working" : "Unavailable")
                }
            }
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-demoSettings"), editingColor == nil { editingColor = "Credaxe" }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        isSaving = true
                        Task {
                            await save()
                            isSaving = false
                            if store.errorMessage == nil { dismiss() }
                        }
                    }
                    .disabled(!hasChanges || isSaving)
                }
            }
        }
    }

    /// A tiny live sample: a venture-colored card with one email tile on it.
    private var glassPreview: some View {
        let style = VentureStyle.of("Vishramo")
        return HStack(spacing: 10) {
            Circle()
                .fill(LinearGradient(colors: [.hex(0xA5ABB8), .hex(0x858A95)], startPoint: .top, endPoint: .bottom))
                .frame(width: 34, height: 34)
                .overlay(Text("A").font(.subheadline.weight(.semibold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 1) {
                Text("AWS").font(.subheadline.weight(.semibold))
                Text("CloudWatch alarm: disk at 91%").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .glassTile(radius: 14)
        .padding(12)
        .background(alignment: .topTrailing) {
            Image(systemName: style.symbol)
                .font(.system(size: 70, weight: .bold))
                .foregroundStyle(.white.opacity(0.25))
                .offset(x: 6, y: -6)
        }
        .background(style.fill, in: .rect(cornerRadius: 20, style: .continuous))
        .clipShape(.rect(cornerRadius: 20, style: .continuous))
        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 4, trailing: 12))
        .accessibilityHidden(true)
    }

    private var colorVentures: [String] {
        let standard = ["Vishramo", "Credaxe", "7-Eleven", "Personal", "Shared/Household", "Family/General",
                        "Travel", "Job Applications", "Pseudo"]
        let present = store.board.ventures.map(\.venture).filter { !standard.contains($0) && $0 != "HotelOS" }
        return standard + present
    }

    private var hasChanges: Bool {
        !token.trimmed.isEmpty || !gmailPassword.trimmed.isEmpty
            || gmailAddress.trimmed != GmailCredentials.savedAddress
    }

    @ViewBuilder
    private var checkStatus: some View {
        switch check {
        case .idle: EmptyView()
        case .checking: ProgressView()
        case .ok: Label("Signed in", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Label("Failed", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    private func save() async {
        let address = gmailAddress.trimmed
        if address != GmailCredentials.savedAddress { GmailCredentials.saveAddress(address) }
        if !gmailPassword.trimmed.isEmpty { GmailCredentials.savePassword(gmailPassword) }
        store.hasGmail = GmailCredentials.load() != nil
        if !token.trimmed.isEmpty {
            savedIn = await store.saveToken(token)
        }
    }

    private func checkSignIn() async {
        let typed = GmailCredentials.clean(gmailPassword)
        guard let password = typed.isEmpty ? GmailCredentials.load()?.password : typed else { return }
        check = .checking
        do {
            try await MailService.shared.checkSignIn(address: gmailAddress.trimmed, password: password)
            check = .ok
        } catch {
            check = .failed(error.localizedDescription)
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// One venture in Settings › Venture Colors: its badge and current color,
/// and the swatches when it's the one being edited.
private struct VentureColorRow: View {
    let venture: String
    @Binding var editing: String?
    @Environment(ItemStore.self) private var store

    var body: some View {
        let style = VentureStyle.of(venture)
        let picked = VentureColors.pickedName(for: style.short)
        let isOpen = editing == venture
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) { editing = isOpen ? nil : venture }
            } label: {
                HStack(spacing: 12) {
                    VentureBadge(venture: venture, size: 30, ring: nil)
                    Text(style.short).foregroundStyle(Color.primary)
                    Spacer()
                    Text(picked ?? "Standard").font(.subheadline).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? "Hides the colors" : "Shows the colors")
            if isOpen {
                ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(VentureColors.palette, id: \.name) { option in
                        let isOn = picked == option.name
                        Button {
                            VentureColors.set(isOn ? nil : option.name, for: style.short)
                            store.ventureColorsChanged()
                        } label: {
                            Circle()
                                .fill(option.color)
                                .frame(width: 28, height: 28)
                                .overlay {
                                    if isOn {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .padding(3)
                                .overlay(Circle().strokeBorder(isOn ? option.color : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(option.name)\(isOn ? ", selected" : "")")
                    }
                }
            }
            .scrollIndicators(.hidden)
            }
        }
        .padding(.vertical, 4)
    }
}
