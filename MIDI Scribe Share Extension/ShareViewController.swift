#if os(iOS)
import UniformTypeIdentifiers
import UIKit
typealias ShareBaseViewController = UIViewController

private enum SharedImportConfig {
    static let appGroupID = "group.org.centennialoss.midiscribe"
    static let incomingDirectoryName = "SharedIncoming"
    static let deepLinkScheme = "midiscribe"
    static let deepLinkHost = "import-shared"
    static let deepLinkFileQueryItem = "file"
}

final class ShareViewController: ShareBaseViewController {
    private var hasStartedImport = false
    private let statusLabel = UILabel()
    private let indicator = UIActivityIndicatorView(style: .medium)
    private let checkLabel = UILabel()
    private lazy var dismissButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("OK", for: .normal)
        button.isHidden = true
        button.addTarget(self, action: #selector(dismissExtensionSheet), for: .touchUpInside)
        return button
    }()

    override func loadView() {
        indicator.startAnimating()
        indicator.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.text = "Sending to MIDI Scribe…"
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        checkLabel.text = "✓"
        checkLabel.font = .systemFont(ofSize: 48, weight: .bold)
        checkLabel.textColor = .systemGreen
        checkLabel.isHidden = true
        checkLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [indicator, checkLabel, statusLabel, dismissButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false

        let view = UIView()
        view.backgroundColor = .systemBackground
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
        self.view = view
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasStartedImport else { return }
        hasStartedImport = true
        handleIncomingItems()
    }

    private func handleIncomingItems() {
#if DEBUG
        NSLog("[ShareExt] handleIncomingItems started")
#endif
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
#if DEBUG
            NSLog("[ShareExt] No NSExtensionItem payload")
#endif
            cancelRequest()
            return
        }

        let providers = items
            .flatMap { $0.attachments ?? [] }
            .filter { provider in
                provider.hasItemConformingToTypeIdentifier(UTType.midi.identifier) ||
                provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
            }

        guard !providers.isEmpty else {
#if DEBUG
            NSLog("[ShareExt] No matching item providers for MIDI/fileURL")
#endif
            cancelRequest()
            return
        }

#if DEBUG
        NSLog("[ShareExt] Found %ld matching providers", providers.count)
#endif
        importFirstMatchingProvider(providers)
    }

    private func cancelRequest() {
        let error = NSError(
            domain: "org.centennialoss.midiscribe.share",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "No MIDI file was provided."]
        )
        extensionContext?.cancelRequest(withError: error)
    }

    private func importFirstMatchingProvider(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else {
            cancelRequest()
            return
        }

        let identifier = provider.hasItemConformingToTypeIdentifier(UTType.midi.identifier)
            ? UTType.midi.identifier
            : UTType.fileURL.identifier

        provider.loadFileRepresentation(forTypeIdentifier: identifier) { [weak self] url, error in
            guard let self else { return }
            if let error {
#if DEBUG
                NSLog("[ShareExt] loadFileRepresentation error: %@", error.localizedDescription)
#endif
                self.extensionContext?.cancelRequest(withError: error)
                return
            }
            guard let url else {
#if DEBUG
                NSLog("[ShareExt] loadFileRepresentation returned nil URL")
#endif
                self.cancelRequest()
                return
            }
#if DEBUG
            NSLog("[ShareExt] Received shared URL: %@", url.absoluteString)
#endif
            self.persistAndOpenInHostApp(sourceURL: url)
        }
    }

    private func persistAndOpenInHostApp(sourceURL: URL) {
        do {
            let destinationURL = try copySharedFile(from: sourceURL)
#if DEBUG
            NSLog("[ShareExt] Copied shared file to: %@", destinationURL.path)
#endif
            openHostApp(with: destinationURL.lastPathComponent)
        } catch {
#if DEBUG
            NSLog("[ShareExt] persistAndOpenInHostApp error: %@", error.localizedDescription)
#endif
            showCompletionState(message: "Sending failed: \(error.localizedDescription)", isSuccess: false)
        }
    }

    private func copySharedFile(from sourceURL: URL) throws -> URL {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedImportConfig.appGroupID
        ) else {
            throw NSError(
                domain: "org.centennialoss.midiscribe.share",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unable to access shared import container."]
            )
        }

        let incomingDirectory = containerURL.appendingPathComponent(
            SharedImportConfig.incomingDirectoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: incomingDirectory, withIntermediateDirectories: true)

        let incomingName = sourceURL.lastPathComponent.isEmpty ? "shared-import.mid" : sourceURL.lastPathComponent
        let destinationName = "\(UUID().uuidString)-\(incomingName)"
        let destinationURL = incomingDirectory.appendingPathComponent(destinationName)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private func openHostApp(with storedFileName: String) {
        var components = URLComponents()
        components.scheme = SharedImportConfig.deepLinkScheme
        components.host = SharedImportConfig.deepLinkHost
        components.queryItems = [
            URLQueryItem(
                name: SharedImportConfig.deepLinkFileQueryItem,
                value: "\(SharedImportConfig.incomingDirectoryName)/\(storedFileName)"
            )
        ]

        guard components.url != nil else {
#if DEBUG
            NSLog("[ShareExt] Failed to construct deep link")
#endif
            showCompletionState(
                message: "Sent to MIDI Scribe. Open the app to view the imported take.",
                isSuccess: true
            )
            return
        }

        showCompletionState(
            message: "Sent to MIDI Scribe. Open the app to view the imported take.",
            isSuccess: true
        )
    }

    private func showCompletionState(message: String, isSuccess: Bool) {
        DispatchQueue.main.async {
            self.indicator.stopAnimating()
            self.indicator.isHidden = true
            self.checkLabel.isHidden = !isSuccess
            self.statusLabel.text = message
            self.dismissButton.isHidden = false
        }
    }

    @objc
    private func dismissExtensionSheet() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
#endif
