/* SPDX-License-Identifier: MIT */
#include "protocol.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static size_t frame(uint8_t *out, uint8_t command, const uint8_t *payload,
                    size_t size) {
  out[0] = 0xa0;
  out[1] = size + 4;
  out[2] = 0;
  out[3] = out[0] + out[1];
  out[4] = command;
  out[5] = size + 1;
  out[6] = 0;
  memcpy(out + 7, payload, size);
  uint8_t total = command + size + 1;
  for (size_t i = 0; i < size; i++)
    total += payload[i];
  out[7 + size] = 0xaa - total;
  return size + 8;
}

int main(void) {
  const uint8_t expected[] = {0xcc, 0xf2, 1, 0, 0xa0, 6,    0, 0xa6,
                              0xa8, 3,    0, 0, 0,    0xff, 0, 0};
  assert(memcmp(version_query, expected, sizeof(expected)) == 0);

  /* Actual checksum-valid ACK/version frames from portatilo. Excludes the
   * unrelated trailing bytes in the private raw response windows.
   */
  const uint8_t live_ack[] = {0xa0, 6, 0, 0xa6, 0xb0, 3, 0, 0xa8, 1, 0x4e};
  const uint8_t live_version[] = {
      0xa0, 0x14, 0,   0xb4, 0xa8, 0x11, 0,   'G', 'F', '_', 'I', 'T',
      'E',  '_',  'E', 'C',  '_',  '2',  '0', '0', '6', '6', 0,   0xdf,
  };
  struct version_parser live = {0};
  assert(version_feed(&live, live_ack, sizeof(live_ack)) == 0);
  assert(version_feed(&live, live_version, sizeof(live_version)) == 0);
  assert(live.ack && live.frames == 2 && live.rejected == 0);
  assert(strcmp(live.version, "GF_ITE_EC_20066") == 0);

  const uint8_t name[] = "GF_TEST_ONLY";
  uint8_t data[256], ack[32];
  size_t size = frame(data, 0xa8, name, sizeof(name));
  for (size_t split = 0; split <= size; split++) {
    struct version_parser parser = {0};
    assert(version_feed(&parser, data, split) == 0);
    assert(version_feed(&parser, data + split, size - split) == 0);
    assert(strcmp(parser.version, (const char *)name) == 0);
  }
  struct version_parser bytewise = {0};
  for (size_t i = 0; i < size; i++)
    assert(version_feed(&bytewise, data + i, 1) == 0);
  assert(strcmp(bytewise.version, (const char *)name) == 0);

  const uint8_t ack_payload[] = {0xa8, 1};
  size_t ack_size = frame(ack, 0xb0, ack_payload, sizeof(ack_payload));
  struct version_parser combined = {0};
  const uint8_t noise[] = {0, 0xff, 0xa0, 0xff, 0xff, 0x9e};
  assert(version_feed(&combined, noise, sizeof(noise)) == 0);
  assert(version_feed(&combined, ack, ack_size) == 0);
  assert(combined.ack && !combined.version[0]);
  assert(version_feed(&combined, data, size) == 0);
  assert(combined.ack && strcmp(combined.version, (const char *)name) == 0);

  for (size_t position = 1; position < size; position++) {
    struct version_parser parser = {0};
    uint8_t corrupt[256];
    memcpy(corrupt, data, size);
    corrupt[position] ^= 1;
    assert(version_feed(&parser, corrupt, size) == 0);
    assert(!parser.version[0]);
  }
  struct version_parser other = {0};
  size_t other_size = frame(ack, 0xae, name, sizeof(name));
  assert(version_feed(&other, ack, other_size) == 0);
  assert(!other.version[0]);

  const uint8_t invalid[][5] = {
      {'A', 0, 'B', 0, 0}, {'A', '\n', 0, 0, 0}, {0, 0, 0, 0, 0}};
  for (size_t i = 0; i < sizeof(invalid) / sizeof(invalid[0]); i++) {
    struct version_parser parser = {0};
    size_t n = frame(data, 0xa8, invalid[i], sizeof(invalid[i]));
    assert(version_feed(&parser, data, n) == 0);
    assert(!parser.version[0]);
  }
  struct version_parser maximum = {0};
  uint8_t long_name[64];
  memset(long_name, 'X', sizeof(long_name));
  size_t n = frame(data, 0xa8, long_name, sizeof(long_name));
  assert(version_feed(&maximum, data, n) == 0);
  assert(strlen(maximum.version) == 64);
  struct version_parser capacity = {0};
  assert(version_feed(&capacity, data, sizeof(capacity.pending) + 1) == -1);
  puts("Protocol tests passed: exact query, partial frames, checksums, noise, "
       "ACK-only, bounds and text validation.");
  return 0;
}
