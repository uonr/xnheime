#include "paired_text.h"

int main() {
    const auto ascii = xnheime::makePairedText("(", ")");
    if (ascii.text != "()" || ascii.cursor != 1 ||
        ascii.trailingCharacters != 1) {
        return 1;
    }

    const auto unicode = xnheime::makePairedText("你好（", "）世界");
    if (unicode.text != "你好（）世界" || unicode.cursor != 3 ||
        unicode.trailingCharacters != 3) {
        return 2;
    }

    return 0;
}
