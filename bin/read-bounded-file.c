#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>

#define MAX_BYTES 65536U

static int write_all(const unsigned char *buffer, size_t length) {
  size_t written = 0;
  while (written < length) {
    ssize_t result = write(STDOUT_FILENO, buffer + written, length - written);
    if (result < 0 && errno == EINTR) continue;
    if (result <= 0) return 1;
    written += (size_t)result;
  }
  return 0;
}

int main(int argc, char **argv) {
  if (argc != 2 || argv[1][0] == '\0') return 64;

  int fd = open(argv[1], O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOFOLLOW);
  if (fd < 0) return 0;

  struct stat metadata;
  if (fstat(fd, &metadata) != 0 || !S_ISREG(metadata.st_mode) ||
      metadata.st_size < 0 || (uintmax_t)metadata.st_size > MAX_BYTES) {
    close(fd);
    return 0;
  }

  unsigned char buffer[MAX_BYTES + 1U];
  size_t length = 0;
  int read_failed = 0;
  while (length <= MAX_BYTES) {
    ssize_t result = read(fd, buffer + length, sizeof(buffer) - length);
    if (result < 0 && errno == EINTR) continue;
    if (result < 0) {
      read_failed = 1;
      break;
    }
    if (result == 0) break;
    length += (size_t)result;
  }
  close(fd);

  if (read_failed || length > MAX_BYTES) return 0;
  return write_all(buffer, length);
}
