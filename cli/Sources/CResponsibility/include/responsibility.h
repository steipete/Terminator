#ifndef RESPONSIBILITY_H
#define RESPONSIBILITY_H

#include <spawn.h>

// Wrapper for the undocumented responsibility_spawnattrs_setdisclaim function
int terminator_spawnattr_setdisclaim(posix_spawnattr_t *attr, int disclaim);

#endif /* RESPONSIBILITY_H */