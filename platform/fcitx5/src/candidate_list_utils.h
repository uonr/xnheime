#ifndef FCITX5_XNHEIME_CANDIDATE_LIST_UTILS_H
#define FCITX5_XNHEIME_CANDIDATE_LIST_UTILS_H

#include <fcitx/candidatelist.h>

namespace xnheime {

inline void setCandidateCursor(fcitx::CommonCandidateList &list,
                               int globalIndex) {
    list.setPage(globalIndex / list.pageSize());
    list.setGlobalCursorIndex(globalIndex);
}

} // namespace xnheime

#endif
