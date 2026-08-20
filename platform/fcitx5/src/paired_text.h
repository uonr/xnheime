#ifndef FCITX5_XNHEIME_PAIRED_TEXT_H
#define FCITX5_XNHEIME_PAIRED_TEXT_H

#include <fcitx-utils/utf8.h>
#include <cstddef>
#include <string>

namespace xnheime {

struct PairedText {
    std::string text;
    size_t cursor;
    size_t trailingCharacters;
};

inline PairedText makePairedText(const std::string &before,
                                 const std::string &after) {
    return {before + after, fcitx::utf8::length(before),
            fcitx::utf8::length(after)};
}

} // namespace xnheime

#endif
