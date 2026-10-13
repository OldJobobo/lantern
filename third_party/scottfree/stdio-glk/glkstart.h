/* Lantern stdio compatibility layer for ScottFree.
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
#ifndef LANTERN_STDIO_GLKSTART_H
#define LANTERN_STDIO_GLKSTART_H

typedef struct {
    int argc;
    char **argv;
} glkunix_startup_t;

typedef struct {
    const char *name;
    int argtype;
    const char *description;
} glkunix_argumentlist_t;

enum {
    glkunix_arg_End = 0,
    glkunix_arg_NoValue = 1,
    glkunix_arg_ValueFollows = 2
};

int glkunix_startup_code(glkunix_startup_t *data);
void glk_main(void);

#endif
