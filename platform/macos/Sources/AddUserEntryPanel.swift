import AppKit

@MainActor
final class AddUserEntryPanel: NSPanel, NSWindowDelegate {
    struct Entry {
        let text: String
        let code: String
        let placement: UserEntryPlacement
        let weight: String?
    }

    private static var current: AddUserEntryPanel?

    private let onSubmit: (Entry) -> String?
    private let textField = NSTextField()
    private let codeField = NSTextField()
    private let topButton = NSButton(radioButtonWithTitle: "前面", target: nil, action: nil)
    private let userButton = NSButton(radioButtonWithTitle: "后面", target: nil, action: nil)
    private let weightField = NSTextField()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")

    static func present(code: String, onSubmit: @escaping (Entry) -> String?) {
        if let current {
            current.orderFrontRegardless()
            current.makeKey()
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let panel = AddUserEntryPanel(code: code, onSubmit: onSubmit)
        current = panel
        panel.center()
        panel.orderFrontRegardless()
        panel.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    init(code: String, onSubmit: @escaping (Entry) -> String?) {
        self.onSubmit = onSubmit
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 194),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "新增用户词条"
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        delegate = self

        codeField.stringValue = code
        codeField.placeholderString = "最多 4 个编码字符"
        textField.placeholderString = "实际要输入的字或词"
        weightField.placeholderString = "可选，例如 100"
        userButton.state = .on
        topButton.state = .off
        topButton.target = self
        topButton.action = #selector(positionChanged(_:))
        userButton.target = self
        userButton.action = #selector(positionChanged(_:))

        let position = NSStackView(views: [topButton, userButton])
        position.orientation = .horizontal
        position.spacing = 16
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "编码"), codeField],
            [NSTextField(labelWithString: "字词"), textField],
            [NSTextField(labelWithString: "位置"), position],
            [NSTextField(labelWithString: "权重"), weightField],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 7
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.column(at: 0).width = 44
        grid.column(at: 1).width = 298
        for rowIndex in 0 ..< grid.numberOfRows {
            grid.row(at: rowIndex).rowAlignment = .firstBaseline
        }

        let cancelButton = NSButton(title: "取消", target: self, action: #selector(cancel(_:)))
        cancelButton.keyEquivalent = "\u{1b}"
        let submitButton = NSButton(title: "提交", target: self, action: #selector(submit(_:)))
        submitButton.keyEquivalent = "\r"
        submitButton.bezelStyle = .rounded
        let buttons = NSStackView(views: [cancelButton, submitButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        errorLabel.maximumNumberOfLines = 2
        errorLabel.alignment = .left

        let content = NSView()
        contentView = content
        for view in [grid, errorLabel, buttons] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),

            errorLabel.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 5),
            errorLabel.leadingAnchor.constraint(equalTo: grid.leadingAnchor),
            errorLabel.trailingAnchor.constraint(equalTo: grid.trailingAnchor),
            errorLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 16),

            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            buttons.topAnchor.constraint(greaterThanOrEqualTo: errorLabel.bottomAnchor, constant: 8),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])
        initialFirstResponder = textField
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_: Notification) {
        if Self.current === self {
            Self.current = nil
        }
    }

    private func validatedEntry() -> Result<Entry, ValidationError> {
        let code = codeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, code.utf8.count <= 4,
              code.utf8.allSatisfy({
                  (UInt8(ascii: "a") ... UInt8(ascii: "z")).contains($0) || $0 == 0x3B || $0 == 0x27
              })
        else {
            return .failure(ValidationError("编码必须是 1–4 个小写字母、分号或单引号。"))
        }
        guard !text.isEmpty, !text.contains("\t"), !text.contains("\n"), !text.contains("\r") else {
            return .failure(ValidationError("字词不能为空，也不能包含 Tab 或换行。"))
        }
        let placement: UserEntryPlacement = topButton.state == .on ? .beforeSystem : .afterSystem
        let weight = weightField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if placement == .afterSystem, !weight.isEmpty,
           Double(weight.trimmingCharacters(in: CharacterSet(charactersIn: "%"))) == nil
        {
            return .failure(ValidationError("权重必须留空或填写数字。"))
        }
        return .success(Entry(
            text: text,
            code: code,
            placement: placement,
            weight: placement == .beforeSystem || weight.isEmpty ? nil : weight
        ))
    }

    @objc private func positionChanged(_ sender: NSButton) {
        topButton.state = sender === topButton ? .on : .off
        userButton.state = sender === userButton ? .on : .off
        weightField.isEnabled = userButton.state == .on
    }

    @objc private func cancel(_: NSButton) {
        close()
    }

    @objc private func submit(_: NSButton) {
        switch validatedEntry() {
        case let .success(entry):
            if let message = onSubmit(entry) {
                errorLabel.stringValue = message
                NSSound.beep()
            } else {
                close()
            }
        case let .failure(error):
            errorLabel.stringValue = error.message
            NSSound.beep()
        }
    }

    private struct ValidationError: Error {
        let message: String

        init(_ message: String) {
            self.message = message
        }
    }
}

