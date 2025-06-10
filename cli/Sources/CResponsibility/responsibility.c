#include "include/responsibility.h"
#include <spawn.h>

// Define the constant for clarity (matches the value used by Qt, LLVM, Chromium, etc.)
#define POSIX_SPAWN_SETDISCLAIM 1

// This is an undocumented but battle-tested API used to disclaim parent responsibility
// for spawned processes. This is crucial for macOS permission dialogs to appear correctly.
//
// References:
// - Qt Blog: https://www.qt.io/blog/the-curious-case-of-the-responsible-process
// - LLVM Implementation: https://github.com/llvm/llvm-project/commit/041c7b84a4b925476d1e21ed302786033bb6035f
// - Chromium Implementation: https://chromium.googlesource.com/chromium/src/+/lkgr/base/process/launch_mac.cc
//
// The "responsible process" determines which app name appears in permission dialogs.
// Without this, dialogs may not appear or may show the wrong app name in the authorization prompt.
extern int responsibility_spawnattrs_setdisclaim(posix_spawnattr_t *attr, int disclaim);

int terminator_spawnattr_setdisclaim(posix_spawnattr_t *attr, int disclaim) {
    return responsibility_spawnattrs_setdisclaim(attr, disclaim);
}