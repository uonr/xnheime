#include "engine.h"
#include "candidate_list_utils.h"
#include "key_policy.h"
#include "paired_text.h"
#include <fcitx-utils/capabilityflags.h>
#include <fcitx-utils/key.h>
#include <fcitx-utils/keysym.h>
#include <fcitx-utils/log.h>
#include <fcitx-utils/misc.h>
#include <fcitx/addonmanager.h>
#include <fcitx/candidatelist.h>
#include <fcitx/event.h>
#include <fcitx/inputcontext.h>
#include <fcitx/inputcontextmanager.h>
#include <fcitx/inputpanel.h>
#include <fcitx/instance.h>
#include <fcitx/surroundingtext.h>
#include <fcitx/text.h>
#include <fcitx/userinterface.h>
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <exception>
#include <filesystem>
#include <optional>
#include <stdexcept>
#include <string>
#include <utility>

#include "xnheime-cxx/src/lib.rs.h"

namespace xnheime {
namespace {

FCITX_DEFINE_LOG_CATEGORY(xnheime_log, "xnheime");

constexpr std::array<const char *, 3> userDictionaryFiles = {
    "xnhe.txt", "flypy_top.txt", "flypy_user.txt"};

using DictionaryFileRevision =
    std::optional<std::pair<std::filesystem::file_time_type, std::uintmax_t>>;
using DictionaryRevision = std::array<DictionaryFileRevision, 3>;

std::filesystem::path userDictionaryDirectory() {
    if (const char *data = std::getenv("XDG_DATA_HOME"); data && *data) {
        return std::filesystem::path(data) / "xnheime";
    }
    if (const char *home = std::getenv("HOME"); home && *home) {
        return std::filesystem::path(home) / ".local" / "share" / "xnheime";
    }
    return {};
}

DictionaryRevision dictionaryRevision(const std::filesystem::path &directory) {
    DictionaryRevision revision;
    if (directory.empty()) {
        return revision;
    }
    for (size_t index = 0; index < userDictionaryFiles.size(); ++index) {
        const auto path = directory / userDictionaryFiles[index];
        std::error_code timeError;
        const auto writeTime = std::filesystem::last_write_time(path, timeError);
        if (timeError) {
            continue;
        }
        std::error_code sizeError;
        const auto size = std::filesystem::file_size(path, sizeError);
        if (!sizeError) {
            revision[index] = std::make_pair(writeTime, size);
        }
    }
    return revision;
}

std::filesystem::path dictionaryEditorPath() {
    return XNHEIME_DICTIONARY_EDITOR_COMMAND;
}

bool dictionaryEditorAvailable(const std::filesystem::path &editor) {
    std::error_code error;
    return std::filesystem::is_regular_file(editor, error);
}

void prewarmDictionaryEditor() {
    const auto editor = dictionaryEditorPath();
    if (dictionaryEditorAvailable(editor)) {
        fcitx::startProcess({editor.string(), "__xnheime_service__"});
    }
}

const fcitx::KeyList selectionKeys = {
    fcitx::Key(FcitxKey_1), fcitx::Key(FcitxKey_2), fcitx::Key(FcitxKey_3),
    fcitx::Key(FcitxKey_4), fcitx::Key(FcitxKey_5), fcitx::Key(FcitxKey_6),
    fcitx::Key(FcitxKey_7), fcitx::Key(FcitxKey_8), fcitx::Key(FcitxKey_9),
};

DictionaryMode dictionaryMode(ConfigDictionaryMode mode) {
    switch (mode) {
    case ConfigDictionaryMode::Expert:
        return DictionaryMode::Expert;
    case ConfigDictionaryMode::Regular:
        return DictionaryMode::Regular;
    case ConfigDictionaryMode::Beginner:
        return DictionaryMode::Beginner;
    }
    throw std::logic_error("unknown dictionary mode");
}

SpecialKey specialKey(const fcitx::Key &key) {
    if (key.check(FcitxKey_Return) || key.check(FcitxKey_KP_Enter)) {
        return SpecialKey::Return;
    }
    if (key.check(FcitxKey_Escape)) {
        return SpecialKey::Escape;
    }
    if (key.check(FcitxKey_Tab)) {
        return SpecialKey::Tab;
    }
    if (key.check(FcitxKey_BackSpace)) {
        return SpecialKey::Backspace;
    }
    if (key.check(FcitxKey_Left)) {
        return SpecialKey::Left;
    }
    if (key.check(FcitxKey_Right)) {
        return SpecialKey::Right;
    }
    if (key.check(FcitxKey_Up)) {
        return SpecialKey::Up;
    }
    if (key.check(FcitxKey_Down)) {
        return SpecialKey::Down;
    }
    return SpecialKey::None;
}

} // namespace

class XnheimeState;

class XnheimeCandidateWord final : public fcitx::CandidateWord {
public:
    XnheimeCandidateWord(XnheimeState *state, size_t index,
                         const Candidate &candidate);
    void select(fcitx::InputContext *inputContext) const override;

private:
    XnheimeState *state_;
    size_t index_;
    CandidateAction action_;
};

class XnheimeState final : public fcitx::InputContextProperty {
public:
    XnheimeState(XnheimeEngine *engine, fcitx::InputContext *inputContext)
        : engine_(engine), inputContext_(inputContext),
          session_(new_session()), dictionaryMode_(engine_->dictionaryMode()) {
        session_->set_dictionary_mode(dictionaryMode(dictionaryMode_));
        reloadUserDictionary();
    }

    bool composing() const { return mode_ != CompositionMode::Idle; }
    uint32_t candidateCount() const { return candidateCount_; }

    bool handle(const KeyAction &action) {
        try {
            switch (action.kind) {
            case KeyActionKind::PassThrough:
                return true;
            case KeyActionKind::InputText:
                inputText(action.text);
                break;
            case KeyActionKind::InsertDirect:
                applyResult(session_->insert_direct(action.text));
                break;
            case KeyActionKind::EnterInline:
                applyResult(session_->enter_inline(action.text));
                break;
            case KeyActionKind::Commit:
            case KeyActionKind::CommitAndPassThrough:
                applyResult(session_->commit());
                break;
            case KeyActionKind::CommitCode:
                applyResult(session_->commit_code());
                break;
            case KeyActionKind::Cancel:
                applyResult(session_->cancel(true));
                break;
            case KeyActionKind::MoveCandidate:
                applyResult(session_->move_candidate(action.offset));
                break;
            }
            return true;
        } catch (const std::exception &error) {
            FCITX_LOGC(xnheime_log, Error) << error.what();
            return false;
        }
    }

    void inputText(const std::string &text) {
        if (mode_ == CompositionMode::Idle) {
            reloadUserDictionaryIfChanged();
            const auto &surrounding = inputContext_->surroundingText();
            hasSelectedText_ = surrounding.isValid() &&
                               surrounding.anchor() != surrounding.cursor();
            selectedText_ = hasSelectedText_ ? surrounding.selectedText() : "";
        }
        const auto clipboard = engine_->clipboardText(inputContext_);
        ExternalText externalText{hasSelectedText_, selectedText_,
                                  clipboard.has_value(),
                                  clipboard.value_or(std::string())};
        applyResult(session_->input_text(text, externalText));
    }

    void applyResult(DispatchResult result) {
        mode_ = result.mode;
        candidateCount_ = result.candidate_count;
        for (const auto &effect : result.effects) {
            apply(effect);
        }
        if (mode_ == CompositionMode::Idle) {
            selectedText_.clear();
            hasSelectedText_ = false;
        }
        updateUI();
    }

    void select(size_t index, CandidateAction action) {
        switch (action) {
        case CandidateAction::None:
            applyResult(session_->select_candidate(static_cast<uint32_t>(index)));
            break;
        case CandidateAction::AddUserEntry:
            inputText("+");
            break;
        default:
            FCITX_LOGC(xnheime_log, Error) << "Unknown candidate action";
            break;
        }
    }

    void clear() { applyResult(session_->cancel(true)); }

    void setDictionaryMode(ConfigDictionaryMode mode) {
        if (mode == dictionaryMode_) {
            return;
        }
        dictionaryMode_ = mode;
        session_->set_dictionary_mode(dictionaryMode(mode));
        mode_ = CompositionMode::Idle;
        candidateCount_ = 0;
        preedit_.clear();
        auxiliary_.clear();
        selectedText_.clear();
        hasSelectedText_ = false;
        inputContext_->inputPanel().reset();
        updateUI();
    }

    void shiftPressed(fcitx::KeySym sym) {
        pendingShift_ = sym == FcitxKey_Shift_R ? 2 : 1;
    }

    bool shiftReleased(fcitx::KeySym sym) {
        const int released = sym == FcitxKey_Shift_R ? 2 : 1;
        if (std::exchange(pendingShift_, 0) != released || !composing()) {
            return false;
        }
        applyResult(released == 1 ? session_->enter_inline("")
                                  : session_->commit_code());
        return true;
    }

    void cancelPendingShift() { pendingShift_ = 0; }

private:
    void apply(const Effect &effect) {
        switch (effect.kind) {
        case EffectKind::InsertText:
            inputContext_->commitString(static_cast<std::string>(effect.text));
            preedit_.clear();
            break;
        case EffectKind::InsertPairedText:
            commitPairedText(static_cast<std::string>(effect.text),
                             static_cast<std::string>(effect.secondary_text));
            preedit_.clear();
            break;
        case EffectKind::SetMarkedText:
            preedit_ = static_cast<std::string>(effect.text);
            break;
        case EffectKind::ShowCandidates:
            showCandidates(effect);
            break;
        case EffectKind::HideCandidates:
            inputContext_->inputPanel().setCandidateList(nullptr);
            auxiliary_.clear();
            break;
        case EffectKind::DeleteBackward:
            inputContext_->forwardKey(fcitx::Key(FcitxKey_BackSpace));
            break;
        case EffectKind::ShowAddEntry:
            launchDictionaryEditor(static_cast<std::string>(effect.text));
            break;
        }
    }

    void launchDictionaryEditor(const std::string &code) {
        const auto editor = dictionaryEditorPath();
        if (!dictionaryEditorAvailable(editor)) {
            auxiliary_ = "无法启动用户词典编辑器：" + editor.string();
            return;
        }
        fcitx::startProcess({editor.string(), code});
        auxiliary_.clear();
    }

    void reloadUserDictionary() {
        const auto directory = userDictionaryDirectory();
        dictionaryRevision_ = dictionaryRevision(directory);
        if (directory.empty()) {
            return;
        }
        try {
            session_->load_user_dictionary(directory.string());
        } catch (const std::exception &error) {
            FCITX_LOGC(xnheime_log, Warn)
                << "Failed to load user dictionary from " << directory
                << ": " << error.what();
        }
    }

    void reloadUserDictionaryIfChanged() {
        const auto revision = dictionaryRevision(userDictionaryDirectory());
        if (revision == dictionaryRevision_) {
            return;
        }
        reloadUserDictionary();
    }

    void commitPairedText(const std::string &before,
                          const std::string &after) {
        const auto paired = makePairedText(before, after);
        if (inputContext_->capabilityFlags().test(
                fcitx::CapabilityFlag::CommitStringWithCursor)) {
            inputContext_->commitStringWithCursor(paired.text, paired.cursor);
            return;
        }

        inputContext_->commitString(paired.text);
        for (size_t index = 0; index < paired.trailingCharacters; ++index) {
            inputContext_->forwardKey(fcitx::Key(FcitxKey_Left));
        }
    }

    void showCandidates(const Effect &effect) {
        auto list = std::make_unique<fcitx::CommonCandidateList>();
        for (size_t index = 0; index < effect.candidates.size(); ++index) {
            list->append<XnheimeCandidateWord>(this, index, effect.candidates[index]);
        }
        list->setPageSize(9);
        list->setSelectionKey(selectionKeys);
        list->setCursorIncludeUnselected(false);
        if (!effect.candidates.empty()) {
            const auto selectedIndex = static_cast<int>(std::min<size_t>(
                effect.selected_index, effect.candidates.size() - 1));
            setCandidateCursor(*list, selectedIndex);
        }
        inputContext_->inputPanel().setCandidateList(std::move(list));
    }

    void updateUI() {
        auto &panel = inputContext_->inputPanel();
        if (preedit_.empty()) {
            panel.setClientPreedit(fcitx::Text());
            panel.setPreedit(fcitx::Text());
        } else if (inputContext_->capabilityFlags().test(
                       fcitx::CapabilityFlag::Preedit)) {
            panel.setClientPreedit(
                fcitx::Text(preedit_, fcitx::TextFormatFlag::HighLight));
            panel.setPreedit(fcitx::Text());
        } else {
            panel.setClientPreedit(fcitx::Text());
            panel.setPreedit(fcitx::Text(preedit_));
        }
        panel.setAuxDown(fcitx::Text(auxiliary_));
        inputContext_->updatePreedit();
        inputContext_->updateUserInterface(
            fcitx::UserInterfaceComponent::InputPanel);
    }

    XnheimeEngine *engine_;
    fcitx::InputContext *inputContext_;
    rust::Box<Session> session_;
    ConfigDictionaryMode dictionaryMode_;
    CompositionMode mode_ = CompositionMode::Idle;
    uint32_t candidateCount_ = 0;
    std::string preedit_;
    std::string auxiliary_;
    std::string selectedText_;
    bool hasSelectedText_ = false;
    int pendingShift_ = 0;
    DictionaryRevision dictionaryRevision_;
};

XnheimeCandidateWord::XnheimeCandidateWord(
    XnheimeState *state, size_t index, const Candidate &candidate)
    : state_(state), index_(index),
      action_(candidate.action) {
    setText(fcitx::Text(static_cast<std::string>(candidate.text)));
    if (!candidate.code.empty()) {
        setComment(fcitx::Text(static_cast<std::string>(candidate.code)));
    }
    if (!candidate.label.empty()) {
        setCustomLabel(fcitx::Text(static_cast<std::string>(candidate.label)));
    }
}

void XnheimeCandidateWord::select(fcitx::InputContext *inputContext) const {
    FCITX_UNUSED(inputContext);
    state_->select(index_, action_);
}

XnheimeEngine::XnheimeEngine(fcitx::Instance *instance)
    : instance_(instance), factory_([this](fcitx::InputContext &inputContext) {
          return new XnheimeState(this, &inputContext);
      }) {
    instance_->inputContextManager().registerProperty("xnheimeState", &factory_);
    prewarmDictionaryEditor();
    reloadConfig();
}

std::optional<std::string>
XnheimeEngine::clipboardText(const fcitx::InputContext *inputContext) {
    if (auto *module = clipboard()) {
        return module->call<fcitx::IClipboard::clipboard>(inputContext);
    }
    return std::nullopt;
}

void XnheimeEngine::keyEvent(const fcitx::InputMethodEntry &, fcitx::KeyEvent &event) {
    auto *state = event.inputContext()->propertyFor(&factory_);
    const auto rawSym = event.rawKey().sym();
    const bool shiftKey = rawSym == FcitxKey_Shift_L || rawSym == FcitxKey_Shift_R;
    if (event.isRelease()) {
        if (shiftKey && state->shiftReleased(rawSym)) {
            event.filterAndAccept();
        }
        return;
    }
    if (shiftKey) {
        state->shiftPressed(rawSym);
        return;
    }
    state->cancelPendingShift();
    const auto states = event.key().states();
    const bool applicationShortcut = states.testAny(fcitx::KeyState::Ctrl) ||
                                     states.testAny(fcitx::KeyState::Alt) ||
                                     states.testAny(fcitx::KeyState::Super);
    const auto key = event.key();
    const auto action = keyAction(
        specialKey(key), fcitx::Key::keySymToUTF8(key.sym()),
        event.rawKey().states().test(fcitx::KeyState::Shift),
        applicationShortcut, state->composing(), state->candidateCount());
    if (action.kind == KeyActionKind::PassThrough) {
        return;
    }
    if (!state->handle(action)) {
        return;
    }
    if (action.kind != KeyActionKind::CommitAndPassThrough) {
        event.filterAndAccept();
    }
}

void XnheimeEngine::reset(const fcitx::InputMethodEntry &,
                          fcitx::InputContextEvent &event) {
    event.inputContext()->propertyFor(&factory_)->clear();
}

void XnheimeEngine::deactivate(const fcitx::InputMethodEntry &,
                               fcitx::InputContextEvent &event) {
    event.inputContext()->propertyFor(&factory_)->clear();
}

void XnheimeEngine::reloadConfig() {
    fcitx::readAsIni(config_, "conf/xnheime.conf");
    if (!factory_.registered()) {
        return;
    }
    instance_->inputContextManager().foreach([this](fcitx::InputContext *inputContext) {
        inputContext->propertyFor(&factory_)->setDictionaryMode(dictionaryMode());
        return true;
    });
}

void XnheimeEngine::setConfig(const fcitx::RawConfig &config) {
    config_.load(config, true);
    fcitx::safeSaveAsIni(config_, "conf/xnheime.conf");
    reloadConfig();
}

fcitx::AddonInstance *XnheimeEngineFactory::create(fcitx::AddonManager *manager) {
    return new XnheimeEngine(manager->instance());
}

} // namespace xnheime

FCITX_ADDON_FACTORY_V2(xnheime, xnheime::XnheimeEngineFactory);
