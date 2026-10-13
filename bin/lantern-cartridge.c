#define _GNU_SOURCE
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define MAX_Z_STORY_BYTES (128LL * 1024LL * 1024LL)
#define MAX_SCOTT_STORY_BYTES (8LL * 1024LL * 1024LL)
#define COPY_BUFFER_BYTES 65536

enum story_format { FORMAT_ZMACHINE, FORMAT_SCOTT };

static void fail(const char *message) {
    fprintf(stderr, "lantern-cartridge: %s\n", message);
    exit(EXIT_FAILURE);
}

static int open_regular(const char *path, off_t maximum, off_t *size) {
    int fd = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
    if (fd < 0) fail("source is unavailable or is not a regular file");

    struct stat st;
    if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode)) {
        close(fd);
        fail("source is not a regular file");
    }
    if (st.st_size < 32 || st.st_size > maximum) {
        close(fd);
        fail("story size is outside Lantern's supported range");
    }
    *size = st.st_size;
    return fd;
}

static unsigned int validate_zmachine(int fd, off_t size) {
    (void)size;
    unsigned char header[64];
    ssize_t got = pread(fd, header, sizeof(header), 0);
    if (got != (ssize_t)sizeof(header) || header[0] < 1 || header[0] > 8)
        fail("file does not contain a supported Z-machine header");
    return header[0];
}

static void validate_scott(int fd) {
    int unknown, items, actions, words, rooms, carry, player_room;
    int treasures, word_length, light_time, messages, treasure_room;
    int copy = dup(fd);
    if (copy < 0) fail("could not inspect Scott Adams database");
    FILE *file = fdopen(copy, "r");
    if (!file) { close(copy); fail("could not inspect Scott Adams database"); }

    int *values[] = { &unknown, &items, &actions, &words, &rooms, &carry,
                      &player_room, &treasures, &word_length, &light_time,
                      &messages, &treasure_room };
    int fields = 0;
    for (size_t i = 0; i < sizeof(values) / sizeof(values[0]); i++) {
        char token[32];
        if (fscanf(file, "%31s", token) != 1) break;
        int separator = fgetc(file);
        if (separator != EOF && !isspace((unsigned char)separator)) break;
        char *end;
        errno = 0;
        long value = strtol(token, &end, 10);
        if (errno || *end || value < INT_MIN || value > INT_MAX) break;
        *values[i] = (int)value;
        fields++;
    }
    fclose(file);
    if (lseek(fd, 0, SEEK_SET) < 0) fail("could not rewind Scott Adams database");
    (void)unknown;
    (void)light_time;
    if (fields != 12 || items < 9 || items > 4096 || actions < 0 || actions > 20000 ||
        words < 6 || words > 10000 || rooms < 1 || rooms > 10000 ||
        carry < 0 || carry > items || player_room < 0 || player_room > rooms ||
        treasures < 0 || treasures > items || word_length < 1 || word_length > 16 ||
        messages < 0 || messages > 20000 || treasure_room < 0 || treasure_room > rooms)
        fail("file does not contain a plausible Scott Adams database header");
}

static int open_story(const char *path, enum story_format format,
                      unsigned int *version, off_t *size) {
    off_t maximum = format == FORMAT_ZMACHINE ? MAX_Z_STORY_BYTES : MAX_SCOTT_STORY_BYTES;
    int fd = open_regular(path, maximum, size);
    if (format == FORMAT_ZMACHINE) *version = validate_zmachine(fd, *size);
    else { validate_scott(fd); *version = 0; }
    return fd;
}

struct sha256_context {
    unsigned char block[64];
    uint32_t state[8];
    uint64_t bit_length;
    size_t block_length;
};

static const uint32_t sha256_round_constants[64] = {
    0x428a2f98U, 0x71374491U, 0xb5c0fbcfU, 0xe9b5dba5U,
    0x3956c25bU, 0x59f111f1U, 0x923f82a4U, 0xab1c5ed5U,
    0xd807aa98U, 0x12835b01U, 0x243185beU, 0x550c7dc3U,
    0x72be5d74U, 0x80deb1feU, 0x9bdc06a7U, 0xc19bf174U,
    0xe49b69c1U, 0xefbe4786U, 0x0fc19dc6U, 0x240ca1ccU,
    0x2de92c6fU, 0x4a7484aaU, 0x5cb0a9dcU, 0x76f988daU,
    0x983e5152U, 0xa831c66dU, 0xb00327c8U, 0xbf597fc7U,
    0xc6e00bf3U, 0xd5a79147U, 0x06ca6351U, 0x14292967U,
    0x27b70a85U, 0x2e1b2138U, 0x4d2c6dfcU, 0x53380d13U,
    0x650a7354U, 0x766a0abbU, 0x81c2c92eU, 0x92722c85U,
    0xa2bfe8a1U, 0xa81a664bU, 0xc24b8b70U, 0xc76c51a3U,
    0xd192e819U, 0xd6990624U, 0xf40e3585U, 0x106aa070U,
    0x19a4c116U, 0x1e376c08U, 0x2748774cU, 0x34b0bcb5U,
    0x391c0cb3U, 0x4ed8aa4aU, 0x5b9cca4fU, 0x682e6ff3U,
    0x748f82eeU, 0x78a5636fU, 0x84c87814U, 0x8cc70208U,
    0x90befffaU, 0xa4506cebU, 0xbef9a3f7U, 0xc67178f2U
};

static uint32_t rotate_right(uint32_t value, unsigned int amount) {
    return (value >> amount) | (value << (32U - amount));
}

static void sha256_transform(struct sha256_context *context) {
    uint32_t words[64];
    for (size_t i = 0; i < 16; i++) {
        size_t offset = i * 4;
        words[i] = ((uint32_t)context->block[offset] << 24) |
                   ((uint32_t)context->block[offset + 1] << 16) |
                   ((uint32_t)context->block[offset + 2] << 8) |
                   (uint32_t)context->block[offset + 3];
    }
    for (size_t i = 16; i < 64; i++) {
        uint32_t s0 = rotate_right(words[i - 15], 7) ^ rotate_right(words[i - 15], 18) ^
                      (words[i - 15] >> 3);
        uint32_t s1 = rotate_right(words[i - 2], 17) ^ rotate_right(words[i - 2], 19) ^
                      (words[i - 2] >> 10);
        words[i] = words[i - 16] + s0 + words[i - 7] + s1;
    }

    uint32_t a = context->state[0];
    uint32_t b = context->state[1];
    uint32_t c = context->state[2];
    uint32_t d = context->state[3];
    uint32_t e = context->state[4];
    uint32_t f = context->state[5];
    uint32_t g = context->state[6];
    uint32_t h = context->state[7];

    for (size_t i = 0; i < 64; i++) {
        uint32_t sum1 = rotate_right(e, 6) ^ rotate_right(e, 11) ^ rotate_right(e, 25);
        uint32_t choice = (e & f) ^ ((~e) & g);
        uint32_t temporary1 = h + sum1 + choice + sha256_round_constants[i] + words[i];
        uint32_t sum0 = rotate_right(a, 2) ^ rotate_right(a, 13) ^ rotate_right(a, 22);
        uint32_t majority = (a & b) ^ (a & c) ^ (b & c);
        uint32_t temporary2 = sum0 + majority;
        h = g;
        g = f;
        f = e;
        e = d + temporary1;
        d = c;
        c = b;
        b = a;
        a = temporary1 + temporary2;
    }

    context->state[0] += a;
    context->state[1] += b;
    context->state[2] += c;
    context->state[3] += d;
    context->state[4] += e;
    context->state[5] += f;
    context->state[6] += g;
    context->state[7] += h;
}

static void sha256_init(struct sha256_context *context) {
    memset(context, 0, sizeof(*context));
    context->state[0] = 0x6a09e667U;
    context->state[1] = 0xbb67ae85U;
    context->state[2] = 0x3c6ef372U;
    context->state[3] = 0xa54ff53aU;
    context->state[4] = 0x510e527fU;
    context->state[5] = 0x9b05688cU;
    context->state[6] = 0x1f83d9abU;
    context->state[7] = 0x5be0cd19U;
}

static void sha256_update(struct sha256_context *context,
                          const unsigned char *data, size_t length) {
    for (size_t i = 0; i < length; i++) {
        context->block[context->block_length++] = data[i];
        if (context->block_length == sizeof(context->block)) {
            sha256_transform(context);
            context->bit_length += 512U;
            context->block_length = 0;
        }
    }
}

static void sha256_finish(struct sha256_context *context, unsigned char digest[32]) {
    size_t index = context->block_length;
    context->block[index++] = 0x80U;
    if (index > 56) {
        while (index < sizeof(context->block)) context->block[index++] = 0;
        sha256_transform(context);
        index = 0;
    }
    while (index < 56) context->block[index++] = 0;

    context->bit_length += (uint64_t)context->block_length * 8U;
    for (size_t i = 0; i < 8; i++)
        context->block[63 - i] = (unsigned char)(context->bit_length >> (i * 8));
    sha256_transform(context);

    for (size_t i = 0; i < 8; i++) {
        digest[i * 4] = (unsigned char)(context->state[i] >> 24);
        digest[i * 4 + 1] = (unsigned char)(context->state[i] >> 16);
        digest[i * 4 + 2] = (unsigned char)(context->state[i] >> 8);
        digest[i * 4 + 3] = (unsigned char)context->state[i];
    }
}

static void fingerprint_zmachine(const char *path) {
    unsigned int version;
    off_t size;
    int fd = open_story(path, FORMAT_ZMACHINE, &version, &size);
    (void)version;

    struct sha256_context context;
    sha256_init(&context);
    unsigned char buffer[COPY_BUFFER_BYTES];
    off_t remaining = size;
    while (remaining > 0) {
        size_t requested = remaining < (off_t)sizeof(buffer) ? (size_t)remaining : sizeof(buffer);
        ssize_t got = read(fd, buffer, requested);
        if (got < 0 && errno == EINTR) continue;
        if (got <= 0) {
            close(fd);
            fail("story changed while its fingerprint was computed");
        }
        sha256_update(&context, buffer, (size_t)got);
        remaining -= got;
    }

    unsigned char extra;
    ssize_t got;
    do { got = read(fd, &extra, 1); } while (got < 0 && errno == EINTR);
    if (got != 0) {
        close(fd);
        fail("story changed while its fingerprint was computed");
    }
    if (close(fd) != 0) fail("could not finish reading the cartridge");

    unsigned char digest[32];
    sha256_finish(&context, digest);
    for (size_t i = 0; i < sizeof(digest); i++)
        if (printf("%02x", digest[i]) < 0) fail("could not write cartridge fingerprint");
    if (putchar('\n') == EOF || fflush(stdout) == EOF || ferror(stdout))
        fail("could not write cartridge fingerprint");
}

static void sanitize_stem(const char *path, char *stem, size_t capacity) {
    const char *base = strrchr(path, '/');
    base = base ? base + 1 : path;
    size_t length = strcspn(base, ".");
    size_t out = 0;

    for (size_t i = 0; i < length && out + 1 < capacity; i++) {
        unsigned char ch = (unsigned char)base[i];
        if (isalnum(ch)) stem[out++] = (char)tolower(ch);
        else if ((ch == '-' || ch == '_' || isspace(ch)) && out > 0 && stem[out - 1] != '-') stem[out++] = '-';
    }
    while (out > 0 && stem[out - 1] == '-') out--;
    if (out == 0) { memcpy(stem, "story", 5); out = 5; }
    stem[out] = '\0';
}

static void require_managed_path(const char *path, const char *root,
                                 enum story_format format) {
    char resolved_root[PATH_MAX];
    char resolved_path[PATH_MAX];
    if (!realpath(root, resolved_root) || !realpath(path, resolved_path))
        fail("managed cartridge path is unavailable");

    size_t root_length = strlen(resolved_root);
    if (strncmp(resolved_path, resolved_root, root_length) != 0 || resolved_path[root_length] != '/')
        fail("cartridge is outside Lantern's managed library");

    unsigned int version;
    off_t size;
    int fd = open_story(path, format, &version, &size);
    close(fd);
    (void)version;
    (void)size;
}

static void copy_story(const char *source, const char *destination_root,
                       enum story_format format) {
    unsigned int version;
    off_t source_size;
    int source_fd = open_story(source, format, &version, &source_size);

    if (mkdir(destination_root, 0700) != 0 && errno != EEXIST) {
        close(source_fd);
        fail("could not create the cartridge library");
    }
    int directory_fd = open(destination_root, O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW);
    if (directory_fd < 0) {
        close(source_fd);
        fail("cartridge library is unavailable or unsafe");
    }

    struct stat directory_stat;
    if (fstat(directory_fd, &directory_stat) != 0 || directory_stat.st_uid != getuid() ||
        (directory_stat.st_mode & 0777) != 0700) {
        close(directory_fd);
        close(source_fd);
        fail("cartridge library must be privately owned with mode 0700");
    }

    char stem[49];
    sanitize_stem(source, stem, sizeof(stem));

    char temporary[96];
    snprintf(temporary, sizeof(temporary), ".import-%ld.tmp", (long)getpid());
    int output_fd = openat(directory_fd, temporary,
                           O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                           0600);
    if (output_fd < 0) {
        close(directory_fd);
        close(source_fd);
        fail("could not create a temporary cartridge");
    }

    unsigned char buffer[COPY_BUFFER_BYTES];
    off_t copied = 0;
    while (copied < source_size) {
        off_t remaining = source_size - copied;
        size_t requested = remaining < (off_t)sizeof(buffer) ? (size_t)remaining : sizeof(buffer);
        ssize_t got = read(source_fd, buffer, requested);
        if (got < 0 && errno == EINTR) continue;
        if (got <= 0) {
            unlinkat(directory_fd, temporary, 0);
            close(output_fd); close(directory_fd); close(source_fd);
            fail("source changed while it was being read");
        }
        ssize_t offset = 0;
        while (offset < got) {
            ssize_t written = write(output_fd, buffer + offset, (size_t)(got - offset));
            if (written < 0 && errno == EINTR) continue;
            if (written <= 0) {
                unlinkat(directory_fd, temporary, 0);
                close(output_fd); close(directory_fd); close(source_fd);
                fail("could not write the imported cartridge");
            }
            offset += written;
        }
        copied += got;
    }

    unsigned char extra;
    ssize_t tail;
    do { tail = read(source_fd, &extra, 1); } while (tail < 0 && errno == EINTR);
    if (tail != 0) {
        unlinkat(directory_fd, temporary, 0);
        close(output_fd); close(directory_fd); close(source_fd);
        fail("source changed while it was being read");
    }

    if (fsync(output_fd) != 0 || close(output_fd) != 0) {
        unlinkat(directory_fd, temporary, 0);
        close(directory_fd); close(source_fd);
        fail("could not finish the imported cartridge");
    }

    char destination[80];
    int linked = 0;
    for (unsigned int suffix = 1; suffix < 10000; suffix++) {
        const char *separator = suffix == 1 ? "" : "-";
        char suffix_text[16] = "";
        if (suffix != 1) snprintf(suffix_text, sizeof(suffix_text), "%u", suffix);
        if (format == FORMAT_ZMACHINE)
            snprintf(destination, sizeof(destination), "%s%s%s.z%u", stem, separator, suffix_text, version);
        else
            snprintf(destination, sizeof(destination), "%s%s%s.dat", stem, separator, suffix_text);
        if (linkat(directory_fd, temporary, directory_fd, destination, 0) == 0) {
            linked = 1;
            break;
        }
        if (errno != EEXIST) break;
    }

    unlinkat(directory_fd, temporary, 0);
    int durable = fsync(directory_fd) == 0;
    close(directory_fd);
    close(source_fd);
    if (!linked) fail("could not file the cartridge in the library");
    if (!durable) fail("could not checkpoint the cartridge library");
    if (puts(destination) == EOF || fflush(stdout) == EOF) fail("could not report imported cartridge");
}

int main(int argc, char **argv) {
    if (argc == 4 && (strcmp(argv[1], "import") == 0 || strcmp(argv[1], "import-zmachine") == 0)) {
        copy_story(argv[2], argv[3], FORMAT_ZMACHINE);
        return EXIT_SUCCESS;
    }
    if (argc == 4 && strcmp(argv[1], "import-scott") == 0) {
        copy_story(argv[2], argv[3], FORMAT_SCOTT);
        return EXIT_SUCCESS;
    }
    if (argc == 4 && (strcmp(argv[1], "check") == 0 || strcmp(argv[1], "check-zmachine") == 0)) {
        require_managed_path(argv[2], argv[3], FORMAT_ZMACHINE);
        return EXIT_SUCCESS;
    }
    if (argc == 4 && strcmp(argv[1], "check-scott") == 0) {
        require_managed_path(argv[2], argv[3], FORMAT_SCOTT);
        return EXIT_SUCCESS;
    }
    if (argc == 3 && strcmp(argv[1], "fingerprint-zmachine") == 0) {
        fingerprint_zmachine(argv[2]);
        return EXIT_SUCCESS;
    }

    fprintf(stderr, "usage: lantern-cartridge import-zmachine SOURCE DIRECTORY\n"
                    "       lantern-cartridge import-scott SOURCE DIRECTORY\n"
                    "       lantern-cartridge check-zmachine STORY DIRECTORY\n"
                    "       lantern-cartridge check-scott STORY DIRECTORY\n"
                    "       lantern-cartridge fingerprint-zmachine STORY\n");
    return EXIT_FAILURE;
}
