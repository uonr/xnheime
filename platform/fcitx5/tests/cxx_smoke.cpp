#include "xnheime-cxx/src/lib.rs.h"
#include <exception>

int main() {
    auto session = xnheime::new_session();
    xnheime::ExternalText externalText;
    auto result = session->input_text("n", externalText);
    if (result.mode != xnheime::CompositionMode::Converting ||
        result.effects.size() != 2 ||
        result.effects[1].kind != xnheime::EffectKind::ShowCandidates ||
        result.effects[1].candidates.empty() ||
        result.effects[1].candidates[0].text.empty()) {
        return 1;
    }

    session->cancel(false);
    for (const char *input : {"g", "i", "t"}) {
        result = session->input_text(input, externalText);
    }
    if (result.effects.size() < 2 || result.effects[1].candidates.empty()) {
        return 2;
    }
    const auto &actionCandidate = result.effects[1].candidates[0];
    if (actionCandidate.kind != xnheime::CandidateKind::Action ||
        actionCandidate.action != xnheime::CandidateAction::AddUserEntry ||
        actionCandidate.label != "+") {
        return 3;
    }

    bool failedAsExpected = false;
    try {
        session->load_user_dictionary("/dev/null");
    } catch (const std::exception &) {
        failedAsExpected = true;
    }
    return failedAsExpected ? 0 : 4;
}
