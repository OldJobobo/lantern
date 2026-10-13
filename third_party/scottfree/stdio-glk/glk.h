/* Lantern stdio compatibility layer for ScottFree.
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
#ifndef LANTERN_STDIO_GLK_H
#define LANTERN_STDIO_GLK_H

#include <stddef.h>
#include <stdint.h>

typedef uint32_t glui32;
typedef struct lantern_window *winid_t;
typedef struct lantern_stream *strid_t;
typedef struct lantern_fileref *frefid_t;

typedef struct {
    glui32 type;
    winid_t win;
    glui32 val1;
    glui32 val2;
} event_t;

enum {
    evtype_None = 0,
    evtype_Timer = 1,
    evtype_LineInput = 3,
    evtype_Arrange = 5,
    gestalt_Timer = 5,
    wintype_TextBuffer = 3,
    wintype_TextGrid = 4,
    winmethod_Above = 0x02,
    winmethod_Fixed = 0x10,
    fileusage_SavedGame = 0x01,
    fileusage_TextMode = 0x100,
    filemode_Write = 1,
    filemode_Read = 2
};

winid_t glk_window_open(winid_t split, glui32 method, glui32 size, glui32 wintype, glui32 rock);
void glk_window_clear(winid_t window);
strid_t glk_window_get_stream(winid_t window);
void glk_set_window(winid_t window);
void glk_put_string_stream(strid_t stream, const char *text);
void glk_request_line_event(winid_t window, char *buffer, glui32 max_length, glui32 initial_length);
void glk_request_timer_events(glui32 milliseconds);
void glk_select(event_t *event);
glui32 glk_gestalt(glui32 selector, glui32 value);
void glk_tick(void);
void glk_exit(void) __attribute__((noreturn));
frefid_t glk_fileref_create_by_prompt(glui32 usage, glui32 mode, glui32 rock);
void glk_fileref_destroy(frefid_t ref);
strid_t glk_stream_open_file(frefid_t ref, glui32 mode, glui32 rock);
glui32 glk_get_line_stream(strid_t stream, char *buffer, glui32 length);
void glk_stream_close(strid_t stream, void *result);

#endif
