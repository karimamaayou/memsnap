#ifndef LAB_COMMON_H
#define LAB_COMMON_H

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

// Shellcode arrays (read-only extern declarations)
extern unsigned char shell_binsh[];
extern int shell_binsh_len;
extern unsigned char shell_bind[];
extern int shell_bind_len;

// Flag helpers
void set_flag(const char *path);
void clear_flag(const char *path);

#endif
