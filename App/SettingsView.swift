import SwiftUI

struct SettingsView: View {
    @Environment(ItemStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var token = ""
    @State private var savedIn: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("ntn_…", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                } header: {
                    Text("Notion Token")
                } footer: {
                    Text("The same token your Scriptable widget uses. It stays on this iPhone and is shared only with the Command Center widget.")
                }

                if store.hasToken {
                    Section {
                        Button("Remove Token", role: .destructive) {
                            TokenStore.delete()
                            store.hasToken = false
                            savedIn = nil
                        }
                    }
                }

                Section("Status") {
                    LabeledContent("Connection") {
                        Text(store.hasToken ? (store.errorMessage == nil ? "Connected" : "Error") : "Not set")
                            .foregroundStyle(store.hasToken && store.errorMessage == nil ? .green : .secondary)
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
                            savedIn = await store.saveToken(token)
                            isSaving = false
                            if store.errorMessage == nil { dismiss() }
                        }
                    }
                    .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }
}
