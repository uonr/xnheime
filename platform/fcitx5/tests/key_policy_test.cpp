#include "key_policy.h"

using xnheime::KeyActionKind;
using xnheime::SpecialKey;

int main() {
    for (const char *key : {"-", "["}) {
        const auto action = xnheime::keyAction(SpecialKey::None, key, false,
                                               false, true, 10);
        if (action.kind != KeyActionKind::MoveCandidate || action.offset != -9) {
            return 1;
        }
    }
    for (const char *key : {"=", "]"}) {
        const auto action = xnheime::keyAction(SpecialKey::None, key, false,
                                               false, true, 10);
        if (action.kind != KeyActionKind::MoveCandidate || action.offset != 9) {
            return 2;
        }
    }
    const auto shortcut = xnheime::keyAction(SpecialKey::None, "a", false,
                                             true, true, 10);
    if (shortcut.kind != KeyActionKind::PassThrough) {
        return 3;
    }
    const auto arrow = xnheime::keyAction(SpecialKey::Left, "", false, false,
                                          true, 1);
    if (arrow.kind != KeyActionKind::CommitAndPassThrough) {
        return 4;
    }
    const auto shifted = xnheime::keyAction(SpecialKey::None, "A", true, false,
                                            true, 10);
    return shifted.kind == KeyActionKind::EnterInline ? 0 : 5;
}
