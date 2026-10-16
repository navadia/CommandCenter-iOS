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
