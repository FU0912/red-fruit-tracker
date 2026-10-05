import UniformTypeIdentifiers
import UIKit

final class ShareViewController: UIViewController {
    private let appGroup = "group.com.f.redfruittracker"
    private let pendingURLsKey = "pendingShareURLs"
    private var shouldOpenHostApp = false
    private var sharedURLForCallback: URL?

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
                } else if let text = item as? String {
                    url = URLExtractor.firstURL(in: text)
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
                let text: String?
                if let value = item as? String {
                    text = value
                } else if let value = item as? NSString {
                    text = value as String
                } else if let value = item as? Data {
                    text = String(data: value, encoding: .utf8)
                } else {
                    text = nil
                }
                if let text, let url = URLExtractor.firstURL(in: text) {
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
        sharedURLForCallback = url
        shouldOpenHostApp = true
    }

    private func finishOnMainThread() {
        DispatchQueue.main.async { [weak self] in
            self?.finish()
        }
    }

    private func finish() {
        guard shouldOpenHostApp,
              let sharedURLForCallback,
              let callbackURL = ShareRoute.callbackURL(for: sharedURLForCallback) else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        shouldOpenHostApp = false
        extensionContext?.open(callbackURL) { [weak self] _ in
            DispatchQueue.main.async {
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        }
    }
}
