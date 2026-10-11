import UniformTypeIdentifiers
import UIKit

final class ShareViewController: UIViewController {
    private var didStartImport = false
    private var shouldOpenHostApp = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStartImport else { return }
        didStartImport = true
        importSharedItem()
    }

    private func importSharedItem() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let providers = extensionItem.attachments,
              !providers.isEmpty else {
            finish()
            return
        }

        loadURL(from: providers, providerIndex: 0)
    }

    private func loadURL(from providers: [NSItemProvider], providerIndex: Int) {
        guard providerIndex < providers.count else {
            finish()
            return
        }

        let provider = providers[providerIndex]
        let identifiers = [UTType.url.identifier, UTType.plainText.identifier, UTType.text.identifier]
            .filter { provider.hasItemConformingToTypeIdentifier($0) }
        loadURL(from: provider, identifiers: identifiers, identifierIndex: 0) { [weak self] url in
            guard let self else { return }
            if let url {
                self.save(url: url)
                self.finishOnMainThread()
            } else {
                self.loadURL(from: providers, providerIndex: providerIndex + 1)
            }
        }
    }

    private func loadURL(
        from provider: NSItemProvider,
        identifiers: [String],
        identifierIndex: Int,
        completion: @escaping (URL?) -> Void
    ) {
        guard identifierIndex < identifiers.count else {
            completion(nil)
            return
        }

        let identifier = identifiers[identifierIndex]
        provider.loadItem(forTypeIdentifier: identifier, options: nil) { [weak self] item, _ in
            let url = Self.url(from: item)
            if url != nil {
                completion(url)
            } else {
                self?.loadURL(
                    from: provider,
                    identifiers: identifiers,
                    identifierIndex: identifierIndex + 1,
                    completion: completion
                )
            }
        }
    }

    private static func url(from item: Any?) -> URL? {
        if let value = item as? URL { return value }
        if let value = item as? NSURL { return value as URL }
        if let value = item as? String { return URLExtractor.firstURL(in: value) }
        if let value = item as? NSString { return URLExtractor.firstURL(in: value as String) }
        if let value = item as? Data {
            return URLExtractor.firstURL(in: String(data: value, encoding: .utf8) ?? "")
        }
        return nil
    }

    private func save(url: URL) {
        ShareInbox.enqueue(url)
        shouldOpenHostApp = true
    }

    private func finishOnMainThread() {
        DispatchQueue.main.async { [weak self] in
            self?.finish()
        }
    }

    private func finish() {
        guard shouldOpenHostApp,
              let callbackURL = ShareRoute.wakeURL() else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        shouldOpenHostApp = false
        // Keep the extension alive until the host-app handoff has been
        // requested. Calling completeRequest first makes iOS dismiss the
        // extension without delivering the custom URL reliably.
        extensionContext?.open(callbackURL) { [weak self] opened in
            DispatchQueue.main.async {
                if !opened {
                    self?.extensionContext?.completeRequest(returningItems: nil)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        self?.extensionContext?.completeRequest(returningItems: nil)
                    }
                }
            }
        }
    }
}
