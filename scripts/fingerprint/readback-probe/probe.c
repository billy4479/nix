/* SPDX-License-Identifier: MIT */
#define _GNU_SOURCE
#include "../spi/transport.h"
#include "protocol.h"
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

static int private_file(const char *name) {
  return open(name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
}
static int save(const char *name, const uint8_t *data, size_t size) {
  int fd = private_file(name);
  if (fd < 0) {
    perror("create private data file");
    return -1;
  }
  size_t offset = 0;
  while (offset < size) {
    ssize_t n = write(fd, data + offset, size - offset);
    if (n < 0 && errno == EINTR)
      continue;
    if (n <= 0) {
      close(fd);
      return -1;
    }
    offset += n;
  }
  return close(fd);
}
static void dump(FILE *file, const char *name, const uint8_t *data,
                 size_t size) {
  fprintf(file, "%s=", name);
  for (size_t i = 0; i < size; i++)
    fprintf(file, "%02x", data[i]);
  fputc('\n', file);
}
/* Return 0 for a checksum-valid matching reply (including a refusal),
 * 2 for no reply, 1 for an I/O, framing or output error. No command retries.
 */
static int query(int fd, FILE *raw, enum sensor_query kind, uint16_t sequence,
                 struct readback_parser *parser) {
  *parser = (struct readback_parser){.query = kind};
  struct timespec time;
  if (clock_gettime(CLOCK_REALTIME, &time) != 0)
    return 1;
  uint16_t token = (time.tv_sec % 60) * 1000 + time.tv_nsec / 1000000;
  long start = sensor_milliseconds();
  if (start < 0)
    return 1;
  fprintf(raw, "\nquery=%u\nsequence=%u\n", kind, sequence);
  uint8_t packet[24];
  size_t length = sensor_query_packet(kind, sequence, token, packet);
  dump(raw, "tx", packet, length);
  if (sensor_send(fd, kind, sequence, token) != 0)
    return 1;
  sensor_pause(5);
  for (unsigned int window = 0; window < 128; window++) {
    long now = sensor_milliseconds();
    if (now < 0)
      return 1;
    if (now - start >= 1500)
      break;
    uint8_t status[4], data[256];
    if (sensor_read_mailbox(fd, status, data) != 0)
      return 1;
    dump(raw, "status", status, sizeof(status));
    dump(raw, "rx", data, sizeof(data));
    if (fflush(raw) != 0 || readback_feed(parser, data, sizeof(data)) != 0)
      return 1;
    if (parser->done)
      break;
    sensor_pause(10);
  }
  printf("query_%u_frames=%u\nquery_%u_rejected=%u\n", kind, parser->frames,
         kind, parser->rejected);
  if (parser->malformed)
    return 1;
  return parser->done ? 0 : 2;
}

static int run(int fd, FILE *raw) {
  if (sensor_configure(fd) != 0)
    return 1;
  struct readback_parser reply;
  int result = query(fd, raw, QUERY_VERSION, 1, &reply);
  if (result != 0) {
    puts("result=version_unavailable");
    return result;
  }
  static const char expected[] = "GF_ITE_EC_20066";
  if (reply.length != sizeof(expected) ||
      memcmp(reply.data, expected, sizeof(expected))) {
    puts("result=unexpected_firmware_stop");
    return 2;
  }
  puts("firmware=GF_ITE_EC_20066");

  result = query(fd, raw, QUERY_STATE, 2, &reply);
  if (result == 1) {
    puts("result=state_io_or_format_error");
    return 1;
  }
  if (result == 0) {
    if (reply.length != 20) {
      puts("result=unexpected_state_layout_stop");
      return 2;
    }
    if (save("mcu-state.bin", reply.data, reply.length) != 0)
      return 1;
    /* Same bit meanings as the official driver. Not a provisioning policy test.
     */
    printf("mcu_state=received\nmcu_tls_connected=%u\nmcu_locked=%u\n",
           (reply.data[1] >> 1) & 1, (reply.data[1] >> 3) & 1);
  } else {
    /* State is advisory. Its timeout does not trigger an alternate state/reset
     * command; the two independently approved E4 reads remain unchanged.
     */
    puts("mcu_state=no_reply");
  }

  result = query(fd, raw, QUERY_HASH, 3, &reply);
  if (result != 0) {
    puts("result=hash_unavailable");
    return result;
  }
  if (reply.status) {
    printf("key_hash_status=%u\nresult=hash_read_refused_stop\n", reply.status);
    return 2;
  }
  if (save("key-hash.bin", reply.data, reply.length) != 0)
    return 1;
  if (reply.length != 32) {
    puts("result=unexpected_hash_length_stop");
    return 2;
  }
  puts("key_hash=collected");

  result = query(fd, raw, QUERY_WRAPPED, 4, &reply);
  if (result != 0) {
    puts("result=wrapped_key_unavailable");
    return result;
  }
  if (reply.status) {
    printf("wrapped_key_status=%u\nresult=wrapped_key_read_refused\n",
           reply.status);
    return 2;
  }
  if (save("wrapped-key.bin", reply.data, reply.length) != 0)
    return 1;
  const uint8_t marker[6] = {2, 0xff, 32, 0, 0, 0};
  if (reply.length != 102 || memcmp(reply.data + 32, marker, sizeof(marker))) {
    puts("result=unexpected_wrapped_key_format");
    return 2;
  }
  puts("wrapped_key=collected\nresult=readback_collected_crypto_not_yet_"
       "verified");
  return 0;
}

int main(int argc, char **argv) {
  if (argc == 2 && !strcmp(argv[1], "--help")) {
    puts("Use the reviewed run.sh as sudo. Fixed "
         "version/state/hash/wrapped-key queries only.\n"
         "Requires a private output directory. No GPIO requests, reset, "
         "configuration,\n"
         "TLS, scan, enrollment, key upload, arbitrary commands or fallback.");
    return 0;
  }
  if (argc != 2) {
    fprintf(stderr, "Use the reviewed run.sh as sudo\n");
    return 1;
  }
  struct stat directory;
  if (stat(".", &directory) || directory.st_uid != geteuid() ||
      (directory.st_mode & 077)) {
    fprintf(stderr,
            "Requires a private directory owned by the executing user\n");
    return 1;
  }
  if (prctl(PR_SET_DUMPABLE, 0UL, 0UL, 0UL, 0UL) != 0) {
    perror("disable process dumps");
    return 1;
  }
  int raw_fd = private_file("raw-spi.txt");
  if (raw_fd < 0) {
    perror("create private raw log");
    return 1;
  }
  FILE *raw = fdopen(raw_fd, "w");
  if (!raw) {
    close(raw_fd);
    return 1;
  }
  setvbuf(stdout, NULL, _IOLBF, 0);
  int fd = sensor_open(argv[1]);
  int result = fd < 0 ? 1 : run(fd, raw);
  if (fd >= 0)
    close(fd);
  if (fclose(raw) != 0)
    result = 1;
  return result;
}
