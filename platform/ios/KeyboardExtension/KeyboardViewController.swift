import AudioToolbox
import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    /// A fully clear keyboard surface is removed from the extension host's
    /// interactive region. This remains visually transparent while keeping gaps
    /// touchable; Cantoboard uses the same value for its clearInteractable color.
    private static let interactableClear = UIColor(white: 1, alpha: 0.005)

    private lazy var model = KeyboardModel(document: self)
    private var host: UIHostingController<KeyboardView>?
    private var heightConstraint: NSLayoutConstraint?
    private var appliedMetrics: KeyboardMetrics?
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    private var feedbackConfiguration = SharedKeyboardSettings.feedback
    private var dictionaryLoadTask: Task<Void, Never>?
    private let touchRegistry = KeyboardTouchRegistry()
    private static let keyClickSound: SystemSoundID = 1123
    private static let audioQueue = DispatchQueue(
        label: "com.mikan.xnheime.keyboard-audio",
        qos: .userInteractive
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        inputView?.allowsSelfSizing = true

        let metrics = KeyboardMetrics.resolve(traits: traitCollection)
        appliedMetrics = metrics

        let host = UIHostingController(
            rootView: KeyboardView(
                model: model,
                metrics: metrics,
                feedback: performKeyFeedback,
                touchRegistry: touchRegistry
            )
        )
        self.host = host
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        view.addSubview(host.view)

        let touchView = KeyboardTouchSurface.TouchView()
        touchView.translatesAutoresizingMaskIntoConstraints = false
        touchView.backgroundColor = Self.interactableClear
        view.addSubview(touchView)
        touchRegistry.touchView = touchView

        // Below required, or it conflicts with UIView-Encapsulated-Layout-Height and
        // the broken result is a fractional height that renders text blurry.

        let height = view.heightAnchor.constraint(equalToConstant: metrics.keyboardHeight)
        height.priority = UILayoutPriority(UILayoutPriority.required.rawValue - 1)
        heightConstraint = height

        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            touchView.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            touchView.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            touchView.topAnchor.constraint(equalTo: host.view.topAnchor),
            touchView.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),
            height,
        ])
        host.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        feedbackConfiguration = SharedKeyboardSettings.feedback
        loadUserDictionary()
    }

    private func loadUserDictionary() {
        let directory = UserDictionaryStore.directory
        let fingerprint = UserDictionaryStore.fingerprint()
        dictionaryLoadTask?.cancel()
        dictionaryLoadTask = Task { [weak self] in
            guard let self,
                  let result = await model.reloadUserDictionaryInBackground(
                      from: directory,
                      fingerprint: fingerprint
                  ),
                  let error = result.error
            else { return }
            NSLog("Xnheime: user dictionary load failed: %@", error)
        }
    }

    private func performKeyFeedback() {
        guard hasFullAccess else { return }
        if feedbackConfiguration.soundEnabled {
            let sound = Self.keyClickSound
            Self.audioQueue.async {
                AudioServicesPlaySystemSound(sound)
            }
        }
        let strength = feedbackConfiguration.strength
        guard strength > 0 else { return }
        feedbackGenerator.impactOccurred(intensity: strength)
        feedbackGenerator.prepare()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateLayoutMetrics()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateLayoutMetrics()
    }

    private func updateLayoutMetrics() {
        let width = view.bounds.width
        guard width > 0, let host, let heightConstraint else { return }

        if model.showsGlobeKey != needsInputModeSwitchKey {
            model.showsGlobeKey = needsInputModeSwitchKey
        }

        let metrics = KeyboardMetrics.resolve(traits: traitCollection)
        if metrics != appliedMetrics {
            appliedMetrics = metrics
            host.rootView = KeyboardView(
                model: model,
                metrics: metrics,
                feedback: performKeyFeedback,
                touchRegistry: touchRegistry
            )
        }

        let target = metrics.keyboardHeight + view.safeAreaInsets.bottom
        if abs(heightConstraint.constant - target) > 0.5 {
            heightConstraint.constant = target
        }
    }
}

extension KeyboardViewController: TextDocumentWriting {
    var documentContextBeforeInput: String? { textDocumentProxy.documentContextBeforeInput }
    var selectedText: String? { textDocumentProxy.selectedText }

    func insertText(_ text: String) { textDocumentProxy.insertText(text) }
    func deleteBackward() { textDocumentProxy.deleteBackward() }
}
