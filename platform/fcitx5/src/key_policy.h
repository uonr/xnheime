#ifndef FCITX5_XNHEIME_KEY_POLICY_H
#define FCITX5_XNHEIME_KEY_POLICY_H

#include <cstdint>
#include <string>
#include <utility>

namespace xnheime {

enum class SpecialKey {
    None,
    Return,
    Escape,
    Tab,
    Backspace,
    Left,
    Right,
    Up,
    Down,
};

enum class KeyActionKind {
    PassThrough,
    InputText,
    InsertDirect,
    EnterInline,
    Commit,
    CommitCode,
    Cancel,
    MoveCandidate,
    CommitAndPassThrough,
};

struct KeyAction {
    KeyAction() = default;
    KeyAction(KeyActionKind kind, std::string text = {}, int32_t offset = 0)
        : kind(kind), text(std::move(text)), offset(offset) {}

    KeyActionKind kind = KeyActionKind::PassThrough;
    std::string text;
    int32_t offset = 0;
};

inline bool isAsciiLetter(const std::string &text) {
    return text.size() == 1 &&
           ((text[0] >= 'a' && text[0] <= 'z') ||
            (text[0] >= 'A' && text[0] <= 'Z'));
}

inline KeyAction keyAction(SpecialKey key, std::string text, bool shift,
                           bool applicationShortcut, bool composing,
                           uint32_t candidateCount) {
    if (applicationShortcut) {
        return {};
    }

    switch (key) {
    case SpecialKey::Return:
        if (candidateCount > 0) {
            return {KeyActionKind::CommitCode};
        }
        return {composing ? KeyActionKind::Commit
                          : KeyActionKind::PassThrough};
    case SpecialKey::Escape:
    case SpecialKey::Tab:
        return {composing ? KeyActionKind::Cancel
                          : KeyActionKind::PassThrough};
    case SpecialKey::Backspace:
        return composing ? KeyAction{KeyActionKind::InputText, "\x7f"}
                         : KeyAction{};
    case SpecialKey::Left:
    case SpecialKey::Right:
    case SpecialKey::Up:
    case SpecialKey::Down:
        if (candidateCount > 1) {
            const int32_t offset = key == SpecialKey::Left    ? -1
                                   : key == SpecialKey::Right ? 1
                                   : key == SpecialKey::Up    ? -9
                                                              : 9;
            return {KeyActionKind::MoveCandidate, {}, offset};
        }
        return {composing ? KeyActionKind::CommitAndPassThrough
                          : KeyActionKind::PassThrough};
    case SpecialKey::None:
        break;
    }

    if (candidateCount > 1) {
        if (text == "-" || text == "[") {
            return {KeyActionKind::MoveCandidate, {}, -9};
        }
        if (text == "=" || text == "]") {
            return {KeyActionKind::MoveCandidate, {}, 9};
        }
    }
    if (text.empty()) {
        return {};
    }
    if (shift && isAsciiLetter(text)) {
        return {composing ? KeyActionKind::EnterInline
                          : KeyActionKind::InsertDirect,
                std::move(text)};
    }
    return {KeyActionKind::InputText, std::move(text)};
}

} // namespace xnheime

#endif
