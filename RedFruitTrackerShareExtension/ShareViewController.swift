import UniformTypeIdentifiers
import UIKit

final class ShareViewController: UIViewController {
    private var didStartImport = false
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
        let identifiers = [
            UTType.url.identifier,
            UTType.webURL.identifier,
            UTType.plainText.identifier,
            UTType.utf8PlainText.identifier,
            UTType.text.identifier,
            UTType.html.identifier,
            UTType.data.identifier
        ]
            .filter { provider.hasItemConformingToTypeIdentifier($0) }
        loadURL(from: provider, identifiers: identifiers, identifierIndex: 0) { [weak self] url in
            guard let self else { return }
            if let url {
                self.save(url: url)
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
        SharePayloadParser.url(from: item)
    }

    private func save(url: URL) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if ShareInbox.enqueue(url) {
                self.statusLabel.text = "链接已接收\n打开漫剧记录后会自动完成导入，无须复制链接。"
                self.doneButton.setTitle("完成", for: .normal)
                self.doneButton.isHidden = false
            } else {
                self.showFailure("链接暂时未能保存，请稍后重试。")
            }
        }
    }

    private func showFailure(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel.text = message
            self?.doneButton.isHidden = false
        }
    }

    @objc private func doneTapped() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
