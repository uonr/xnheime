#ifndef FCITX5_XNHEIME_ENGINE_H
#define FCITX5_XNHEIME_ENGINE_H

#include <fcitx/addonfactory.h>
#include <fcitx/addonmanager.h>
#include <fcitx-config/configuration.h>
#include <fcitx-config/enum.h>
#include <fcitx-config/iniparser.h>
#include <fcitx-config/option.h>
#include <fcitx-utils/i18n.h>
#include <fcitx/inputcontextproperty.h>
#include <fcitx/inputmethodengine.h>
#include <fcitx/instance.h>
#include "clipboard_public.h"
#include <optional>
#include <string>

namespace fcitx {
class Instance;
}

namespace xnheime {

class XnheimeState;

enum class ConfigDictionaryMode { Expert, Regular, Beginner };
FCITX_CONFIG_ENUM_NAME_WITH_I18N(ConfigDictionaryMode, N_("Expert"),
                                 N_("Regular"), N_("Beginner"));

FCITX_CONFIGURATION(
    XnheimeConfig,
    fcitx::OptionWithAnnotation<ConfigDictionaryMode,
                                ConfigDictionaryModeI18NAnnotation>
        dictionaryMode{this, "DictionaryMode", N_("Dictionary mode"),
                       ConfigDictionaryMode::Expert};);

class XnheimeEngine final : public fcitx::InputMethodEngineV2 {
public:
    explicit XnheimeEngine(fcitx::Instance *instance);

    void keyEvent(const fcitx::InputMethodEntry &, fcitx::KeyEvent &) override;
    void reset(const fcitx::InputMethodEntry &, fcitx::InputContextEvent &) override;
    void deactivate(const fcitx::InputMethodEntry &, fcitx::InputContextEvent &) override;
    void reloadConfig() override;
    const fcitx::Configuration *getConfig() const override { return &config_; }
    void setConfig(const fcitx::RawConfig &config) override;

    auto *factory() { return &factory_; }
    fcitx::Instance *instance() const { return instance_; }
    ConfigDictionaryMode dictionaryMode() const { return *config_.dictionaryMode; }
    std::optional<std::string>
    clipboardText(const fcitx::InputContext *inputContext);

private:
    fcitx::Instance *instance_;
    fcitx::FactoryFor<XnheimeState> factory_;
    XnheimeConfig config_;
    FCITX_ADDON_DEPENDENCY_LOADER(clipboard, instance_->addonManager());
};

class XnheimeEngineFactory final : public fcitx::AddonFactory {
public:
    fcitx::AddonInstance *create(fcitx::AddonManager *manager) override;
};

} // namespace xnheime

#endif
