#include "candidate_list_utils.h"

#include <fcitx/inputcontext.h>
#include <fcitx/text.h>
#include <string>

namespace {

class Candidate final : public fcitx::CandidateWord {
public:
    explicit Candidate(int index) : fcitx::CandidateWord(fcitx::Text(std::to_string(index))) {}

    void select(fcitx::InputContext *) const override {}
};

} // namespace

int main() {
    fcitx::CommonCandidateList list;
    list.setPageSize(9);
    for (int index = 0; index < 12; ++index) {
        list.append<Candidate>(index);
    }

    xnheime::setCandidateCursor(list, 9);
    if (list.currentPage() != 1 || list.globalCursorIndex() != 9 ||
        list.cursorIndex() != 0) {
        return 1;
    }

    xnheime::setCandidateCursor(list, 11);
    if (list.currentPage() != 1 || list.globalCursorIndex() != 11 ||
        list.cursorIndex() != 2) {
        return 2;
    }

    xnheime::setCandidateCursor(list, 0);
    return list.currentPage() == 0 && list.cursorIndex() == 0 ? 0 : 3;
}
