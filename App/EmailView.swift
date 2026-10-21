import SwiftUI
import WebKit

/// Reads one item's email straight from the hub Gmail.
struct EmailView: View {
    let item: Item

    @Environment(ItemStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var message: EmailMessage?
    @State private var loadError: String?
    @State private var showImages = false
    @State private var showSettings = false

    var body: some View {
        content
            .navigationTitle(message?.fromName ?? "Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(isPresented: $showSettings, onDismiss: { Task { await load() } }) {
                SettingsView()
            }
            .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let message {
            VStack(spacing: 0) {
                header(message)
                Divider()
                EmailWebView(html: message.page(showImages: showImages))
            }
        } else if let loadError {
            ContentUnavailableView {
                Label(store.hasGmail ? "Couldn't Open Email" : "Connect Gmail", systemImage: "envelope.badge")
            } description: {
                Text(loadError)
            } actions: {
                if store.hasGmail {
                    Button("Try Again") { Task { await load() } }
                        .buttonStyle(.glass)
                } else {
                    Button("Open Settings") { showSettings = true }
                        .buttonStyle(.glassProminent)
                }
            }
        } else {
            ProgressView("Opening email…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ m: EmailMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(m.subject.isEmpty ? item.cleanTitle : m.subject)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
            HStack(alignment: .firstTextBaseline) {
                Text(m.fromName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let date = m.date {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if !m.fromAddress.isEmpty, m.fromAddress != m.fromName {
                Text(m.fromAddress)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if !item.isMailOnly {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit", systemImage: "pencil") {
                    CaptureCenter.shared.request = CaptureRequest(input: .edit(item), kind: .typed)
                }
            }
        }
        if message?.hasRemoteImages == true {
            ToolbarItem(placement: .topBarTrailing) {
                Button(showImages ? "Hide Images" : "Show Images",
                       systemImage: showImages ? "photo.fill" : "photo") {
                    showImages.toggle()
                }
            }
        }
        if !item.isMailOnly {
        ToolbarItem(placement: .bottomBar) {
            Button {
                let id = item.id
                Task { await store.markDone([id]) }
                dismiss()
            } label: {
                Label("Mark Done", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.green)
        }
        }
    }

    private func load() async {
        loadError = nil
        guard let id = item.messageID else {
            loadError = "This item wasn't created from an email."
            return
        }
        do {
            message = try await MailService.shared.message(id: id)
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// Shows the email page. JavaScript is off, nothing is stored, and tapped
/// links open in Safari.
struct EmailWebView: UIViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        config.dataDetectorTypes = [.link, .phoneNumber]
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.backgroundColor = .white
        view.scrollView.backgroundColor = .white
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loaded != html else { return }
        context.coordinator.loaded = html
        view.loadHTMLString(html, baseURL: nil)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded: String?

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                _ = await UIApplication.shared.open(url)
                return .cancel
            }
            return .allow
        }
    }
}
