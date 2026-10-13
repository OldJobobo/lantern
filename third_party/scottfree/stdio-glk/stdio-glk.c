/* A deliberately small stdio Glk compatibility layer for Lantern's ScottFree
 * build. It implements only the calls used by the pinned ScottFree source.
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
#define _GNU_SOURCE
#include "glk.h"
#include "glkstart.h"

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

struct lantern_window { int unused; };
struct lantern_stream { FILE *file; int owned; };
struct lantern_fileref { char name[64]; };

static struct lantern_window main_window;
static struct lantern_stream output_stream = { NULL, 0 };
static char *line_buffer;
static glui32 line_capacity;
static winid_t line_window;
static glui32 timer_interval;
static int save_root_fd = -1;

static void fatal(const char *message) {
    fprintf(stderr, "scottfree: %s\n", message);
    exit(EXIT_FAILURE);
}

static int safe_path_component(const char *value) {
    size_t length = strlen(value);
    if (length == 0 || length > 80 || strcmp(value, ".") == 0 || strcmp(value, "..") == 0)
        return 0;
    for (size_t index = 0; index < length; index++) {
        unsigned char ch = (unsigned char)value[index];
        if (!islower(ch) && !isdigit(ch) && ch != '-') return 0;
    }
    return 1;
}

static int open_save_directory(int parent_fd, const char *name) {
    if (mkdirat(parent_fd, name, 0700) != 0 && errno != EEXIST)
        return -1;
    return openat(parent_fd, name, O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW);
}

static int safe_save_name(const char *input, char *output, size_t capacity) {
    size_t end = strcspn(input, "\r\n");
    while (end > 0 && isspace((unsigned char)input[end - 1])) end--;
    size_t start = 0;
    while (start < end && isspace((unsigned char)input[start])) start++;
    if (end - start > 4 && strncasecmp(input + end - 4, ".sav", 4) == 0) end -= 4;

    size_t out = 0;
    for (size_t i = start; i < end && out + 1 < capacity; i++) {
        unsigned char ch = (unsigned char)input[i];
        if (isalnum(ch) || ch == '-' || ch == '_') output[out++] = (char)ch;
        else if (isspace(ch) && out > 0 && output[out - 1] != '-') output[out++] = '-';
        else return 0;
    }
    if (out == 0 || out > 48) return 0;
    output[out] = '\0';
    return 1;
}

winid_t glk_window_open(winid_t split, glui32 method, glui32 size, glui32 wintype, glui32 rock) {
    (void)split; (void)method; (void)size; (void)wintype; (void)rock;
    output_stream.file = stdout;
    return &main_window;
}

void glk_window_clear(winid_t window) { (void)window; }
strid_t glk_window_get_stream(winid_t window) { (void)window; return &output_stream; }
void glk_set_window(winid_t window) { (void)window; }

void glk_put_string_stream(strid_t stream, const char *text) {
    if (!stream || !stream->file || !text) return;
    fputs(text, stream->file);
    fflush(stream->file);
}

void glk_request_line_event(winid_t window, char *buffer, glui32 max_length, glui32 initial_length) {
    (void)initial_length;
    line_window = window;
    line_buffer = buffer;
    line_capacity = max_length;
}

void glk_request_timer_events(glui32 milliseconds) { timer_interval = milliseconds; }

void glk_select(event_t *event) {
    memset(event, 0, sizeof(*event));
    if (line_buffer) {
        if (!fgets(line_buffer, (int)line_capacity + 1, stdin)) exit(EXIT_SUCCESS);
        size_t length = strcspn(line_buffer, "\r\n");
        line_buffer[length] = '\0';
        event->type = evtype_LineInput;
        event->win = line_window;
        event->val1 = (glui32)length;
        line_buffer = NULL;
        line_capacity = 0;
        return;
    }
    if (timer_interval) {
        event->type = evtype_Timer;
        return;
    }
    event->type = evtype_None;
}

glui32 glk_gestalt(glui32 selector, glui32 value) {
    (void)value;
    return selector == gestalt_Timer;
}

void glk_tick(void) {}
void glk_exit(void) { exit(EXIT_SUCCESS); }

frefid_t glk_fileref_create_by_prompt(glui32 usage, glui32 mode, glui32 rock) {
    (void)usage; (void)rock;
    char input[128];
    char name[64];
    fputs(mode == filemode_Write ? "Please enter a save name: " : "Please enter a save to restore: ", stdout);
    fflush(stdout);
    if (!fgets(input, sizeof(input), stdin) || !safe_save_name(input, name, sizeof(name))) {
        fputs("Invalid save name.\n", stdout);
        fflush(stdout);
        return NULL;
    }

    struct lantern_fileref *ref = calloc(1, sizeof(*ref));
    if (!ref) fatal("out of memory");
    int written = snprintf(ref->name, sizeof(ref->name), "%s.sav", name);
    if (written < 0 || (size_t)written >= sizeof(ref->name)) {
        free(ref);
        return NULL;
    }
    return ref;
}

void glk_fileref_destroy(frefid_t ref) { free(ref); }

strid_t glk_stream_open_file(frefid_t ref, glui32 mode, glui32 rock) {
    (void)rock;
    if (!ref || save_root_fd < 0) return NULL;
    int flags = mode == filemode_Write
        ? O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW
        : O_RDONLY | O_CLOEXEC | O_NOFOLLOW;
    int fd = openat(save_root_fd, ref->name, flags, 0600);
    if (fd < 0) return NULL;
    struct stat st;
    if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode)) { close(fd); return NULL; }
    FILE *file = fdopen(fd, mode == filemode_Write ? "w" : "r");
    if (!file) { close(fd); return NULL; }
    struct lantern_stream *stream = calloc(1, sizeof(*stream));
    if (!stream) { fclose(file); fatal("out of memory"); }
    stream->file = file;
    stream->owned = 1;
    return stream;
}

glui32 glk_get_line_stream(strid_t stream, char *buffer, glui32 length) {
    if (!stream || !stream->file || !buffer || length == 0) return 0;
    if (!fgets(buffer, (int)length, stream->file)) return 0;
    return (glui32)strlen(buffer);
}

void glk_stream_close(strid_t stream, void *result) {
    (void)result;
    if (!stream || !stream->owned) return;
    fclose(stream->file);
    free(stream);
}

int main(int argc, char **argv) {
    if (argc < 7 || strcmp(argv[1], "--save-root") != 0 ||
        strcmp(argv[3], "--save-key") != 0 || !safe_path_component(argv[4])) {
        fprintf(stderr, "usage: scottfree --save-root STATE_DIRECTORY --save-key CARTRIDGE -w GAME.dat\n");
        return EXIT_FAILURE;
    }
    int directory_fd = open(argv[2], O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW);
    if (directory_fd < 0) fatal("save root is unavailable or unsafe");
    const char *components[] = { "lantern", "saves", "scottfree", argv[4] };
    for (size_t index = 0; index < sizeof(components) / sizeof(components[0]); index++) {
        int child_fd = open_save_directory(directory_fd, components[index]);
        close(directory_fd);
        if (child_fd < 0) fatal("save directory is unavailable or unsafe");
        directory_fd = child_fd;
    }
    save_root_fd = directory_fd;

    char **filtered = calloc((size_t)argc, sizeof(*filtered));
    if (!filtered) fatal("out of memory");
    filtered[0] = argv[0];
    for (int source = 5, destination = 1; source < argc; source++, destination++)
        filtered[destination] = argv[source];

    glkunix_startup_t startup = { argc - 4, filtered };
    if (!glkunix_startup_code(&startup)) {
        free(filtered);
        return EXIT_FAILURE;
    }
    glk_main();
    free(filtered);
    return EXIT_SUCCESS;
}
