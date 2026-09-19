import UniformTypeIdentifiers
import UIKit

final class ShareViewController: UIViewController {
    private let appGroup = "group.com.f.redfruittracker"
    private let pendingURLsKey = "pendingShareURLs"

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        importSharedItem()
    }

    private func importSharedItem() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = extensionItem.attachments?.first else {
            finish()
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
                let url: URL?
                if let itemURL = item as? URL {
                    url = itemURL
                } else if let itemURL = item as? NSURL {
                    url = itemURL as URL
                } else {
                    url = nil
                }
                if let url {
                    self?.save(url: url)
                }
                self?.finishOnMainThread()
            }
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { [weak self] item, _ in
                if let text = item as? String, let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    self?.save(url: url)
                }
                self?.finishOnMainThread()
            }
            return
        }

        finish()
    }

    private func save(url: URL) {
        let defaults = UserDefaults(suiteName: appGroup)
        var pendingURLs = defaults?.stringArray(forKey: pendingURLsKey) ?? []
        let value = url.absoluteString
        if !pendingURLs.contains(value) {
            pendingURLs.append(value)
            defaults?.set(pendingURLs, forKey: pendingURLsKey)
        }
    }

    private func finishOnMainThread() {
        DispatchQueue.main.async { [weak self] in
            self?.finish()
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
