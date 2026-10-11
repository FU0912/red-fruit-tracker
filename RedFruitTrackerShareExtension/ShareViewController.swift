import UniformTypeIdentifiers
import UIKit

final class ShareViewController: UIViewController {
    private var didStartImport = false
    private var shouldOpenHostApp = false
    private let statusLabel = UILabel()
    private let doneButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        statusLabel.text = "正在读取分享内容…"
        statusLabel.textColor = .label
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center

        doneButton.setTitle("完成", for: .normal)
        doneButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        doneButton.isHidden = true

        let stack = UIStackView(arrangedSubviews: [statusLabel, doneButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
        ])
    }

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
            showFailure("没有读到分享链接。请返回后选择红果漫剧的链接或文本分享。")
            return
        }

        loadURL(from: providers, providerIndex: 0)
    }

    private func loadURL(from providers: [NSItemProvider], providerIndex: Int) {
        guard providerIndex < providers.count else {
            showFailure("没有识别到可导入的链接。分享窗口仍保留，确认后可返回。")
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
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel.text = "已接收分享链接\n打开漫剧记录后会自动导入，不需要复制链接。"
        }
    }

    private func finishOnMainThread() {
        DispatchQueue.main.async { [weak self] in
            self?.finish()
        }
    }

    private func showFailure(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel.text = message
            self?.doneButton.isHidden = false
        }
    }

    private func finish() {
        guard shouldOpenHostApp else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        guard let callbackURL = ShareRoute.wakeURL() else {
            showFailure("链接已接收。打开漫剧记录后会自动导入。")
            return
        }

        shouldOpenHostApp = false
        // Keep the extension alive until the host-app handoff has been
        // requested. Calling completeRequest first makes iOS dismiss the
        // extension without delivering the custom URL reliably.
        extensionContext?.open(callbackURL) { [weak self] opened in
            DispatchQueue.main.async {
                if !opened {
                    // Ordinary Share Extensions are not guaranteed to be able
                    // to foreground their containing app. Keep the success
                    // state visible instead of dismissing with no feedback.
                    self?.statusLabel.text = "已接收分享链接\n打开漫剧记录后会自动导入，不需要复制链接。"
                    self?.doneButton.isHidden = false
                } else {
                    self?.statusLabel.text = "已发送到漫剧记录，正在打开…"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        self?.extensionContext?.completeRequest(returningItems: nil)
                    }
                }
            }
        }
    }

    @objc private func doneTapped() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
