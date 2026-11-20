/* SPDX-License-Identifier: MIT */
/* Linked only into the offline test executable. Never part of the live probe.
 */
#include "../spi/transport.h"
#include <assert.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static enum sensor_query current;
static unsigned int window;
static long milliseconds;
static int scenario(const char *name) {
  return !strcmp(getenv("SCENARIO"), name);
}
int sensor_open(const char *node) {
  (void)node;
  return open("/dev/null", O_RDWR);
}
int sensor_configure(int fd) {
  (void)fd;
  return 0;
}
int sensor_send(int fd, enum sensor_query query, uint16_t counter,
                uint16_t token) {
  (void)fd;
  (void)token;
  assert(counter == (unsigned int)query + 1);
  current = query;
  window = 0;
  FILE *calls = fopen("mock-queries.txt", "a");
  assert(calls);
  fprintf(calls, "%u\n", query);
  fclose(calls);
  return 0;
}
static void frame(uint8_t out[256], uint8_t cmd, const uint8_t *data,
                  size_t n) {
  assert(n + 8 <= 256);
  memset(out, 0, 256);
  out[0] = 0xa0;
  out[1] = n + 4;
  out[3] = out[0] + out[1];
  out[4] = cmd;
  out[5] = n + 1;
  memcpy(out + 7, data, n);
  uint8_t checksum = 0xaa;
  for (size_t i = 4; i < n + 7; i++)
    checksum -= out[i];
  out[n + 7] = checksum;
}
int sensor_read_mailbox(int fd, uint8_t status[4], uint8_t response[256]) {
  (void)fd;
  if (current == QUERY_STATE && scenario("io_error"))
    return -1;
  memset(status, 0, 4);
  memset(response, 0, 256);
  if (current == QUERY_STATE && scenario("missing_state"))
    return 0;
  if (window++ == 0) {
    uint8_t ack[] = {current == QUERY_VERSION ? 0xa8
                     : current == QUERY_STATE ? 0xaf
                                              : 0xe4,
                     1};
    frame(response, 0xb0, ack, sizeof(ack));
    return 0;
  }
  if (window > 2)
    return 0;
  if (current == QUERY_VERSION) {
    const char *name =
        scenario("wrong_version") ? "GF_ITE_EC_20063" : "GF_ITE_EC_20066";
    frame(response, 0xa8, (const uint8_t *)name, strlen(name) + 1);
  } else if (current == QUERY_STATE) {
    uint8_t state[20] = {1, 8};
    frame(response, 0xae, state, sizeof(state));
  } else if (current == QUERY_HASH && scenario("denied_hash")) {
    frame(response, 0xe4, (const uint8_t[]){7}, 1);
  } else {
    size_t size = current == QUERY_HASH ? 32 : 102;
    if (current == QUERY_HASH && scenario("short_hash"))
      size = 31;
    if (current == QUERY_WRAPPED && scenario("empty_blob"))
      size = 0;
    uint32_t type = current == QUERY_HASH ? KEY_HASH_TYPE : KEY_WRAPPED_TYPE;
    if (scenario("wrong_tag"))
      type = KEY_WRAPPED_TYPE;
    uint8_t payload[120] = {0};
    for (unsigned int i = 0; i < 4; i++)
      payload[1 + i] = type >> (8 * i);
    payload[5] = size;
    if (scenario("length_mismatch") && current == QUERY_HASH)
      payload[5]--;
    memset(payload + 9, 0xa5, size);
    if (current == QUERY_WRAPPED && size == 102)
      memcpy(payload + 9 + 32, (const uint8_t[]){2, 0xff, 32, 0, 0, 0}, 6);
    frame(response, 0xe4, payload, size + 9);
    if (scenario("corrupt_checksum") && current == QUERY_HASH)
      response[size + 16] ^= 1;
  }
  return 0;
}
long sensor_milliseconds(void) {
  milliseconds += 50;
  return milliseconds;
}
void sensor_pause(long delay) { (void)delay; }
