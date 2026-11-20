/* SPDX-License-Identifier: MIT */
#include "../spi/transport.h"
#include "protocol.h"
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static void dump(const char *label, const uint8_t *data, size_t size) {
  printf("%s=", label);
  for (size_t i = 0; i < size; i++)
    printf("%02x", data[i]);
  putchar('\n');
}

static int query(int fd) {
  if (sensor_configure(fd) != 0)
    return 1;
  dump("tx_version", version_query, sizeof(version_query));
  long start = sensor_milliseconds();
  if (start < 0 || sensor_send(fd, QUERY_VERSION, 1, 0) != 0)
    return 1;

  /* Preserve the successful first probe's 64-byte reads and one A8 command.
   * No preamble, reset, retry, state/config upload, or TLS setup.
   */
  uint8_t response[64];
  struct version_parser parser = {0};
  sensor_pause(5);
  for (unsigned int i = 0; i < 128; i++) {
    long now = sensor_milliseconds();
    if (now < 0 || now - start >= 1500)
      break;
    if (sensor_read_small(fd, response) != 0)
      return 1;
    dump("rx_window", response, sizeof(response));
    if (version_feed(&parser, response + 4, 60) != 0) {
      fprintf(stderr, "Response parser capacity exceeded\n");
      return 1;
    }
    if (parser.version[0])
      break;
    sensor_pause(10);
  }
  printf("ack_seen=%s\nvalid_frames=%u\nrejected_frames=%u\n",
         parser.ack ? "yes" : "no", parser.frames, parser.rejected);
  if (parser.version[0]) {
    printf("firmware=%s\nresult=version_received\n", parser.version);
    return 0;
  }
  printf("result=no_valid_version\n");
  return 2;
}

int main(int argc, char **argv) {
  if (argc == 2 && strcmp(argv[1], "--help") == 0) {
    puts("Use the reviewed run.sh as sudo. Sends one fixed firmware-version "
         "query.\n"
         "No userspace GPIO requests, reset, key writes, sensor configuration, "
         "or fallback.");
    return 0;
  }
  if (argc != 2) {
    fprintf(stderr, "Use the reviewed run.sh as sudo\n");
    return 1;
  }
  int fd = sensor_open(argv[1]);
  if (fd < 0)
    return 1;
  setvbuf(stdout, NULL, _IOLBF, 0);
  int result = query(fd);
  close(fd);
  return result;
}
