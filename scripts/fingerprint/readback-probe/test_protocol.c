/* SPDX-License-Identifier: MIT */
#include "protocol.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static size_t frame(uint8_t *out, uint8_t cmd, const uint8_t *payload,
                    size_t n) {
  out[0] = 0xa0;
  out[1] = n + 4;
  out[2] = (n + 4) >> 8;
  out[3] = out[0] + out[1] + out[2];
  out[4] = cmd;
  out[5] = n + 1;
  out[6] = (n + 1) >> 8;
  memcpy(out + 7, payload, n);
  uint8_t checksum = 0xaa;
  for (size_t i = 4; i < n + 7; i++)
    checksum -= out[i];
  out[n + 7] = checksum;
  return n + 8;
}
int main(void) {
  uint8_t packet[24];
  const uint8_t version[] = {0xcc, 0xf2, 1, 0, 0xa0, 6,    0, 0xa6,
                             0xa8, 3,    0, 0, 0,    0xff, 0, 0};
  assert(sensor_query_packet(QUERY_VERSION, 1, 0, packet) == sizeof(version));
  assert(!memcmp(packet, version, sizeof(version)));
  const uint8_t state[] = {0xcc, 0xf2, 1,    0, 0xa0, 9,    0, 0xa9, 0xaf, 6, 0,
                           0x55, 0x39, 0x30, 0, 0,    0x38, 0, 0,    0};
  const uint8_t hash[] = {0xcc, 0xf2, 1, 0, 0xa0, 12, 0, 0xac, 0xe4, 9,
                          0,    3,    0, 2, 0xbb, 0,  0, 0,    0,    0xfd};
  const uint8_t wrapped[] = {0xcc, 0xf2, 1, 0, 0xa0, 12, 0, 0xac, 0xe4, 9,
                             0,    3,    0, 1, 0xbb, 0,  0, 0,    0,    0xfe};
  /* Golden vectors independently compared with original Windows machine code.
   */
  assert(sensor_query_packet(QUERY_STATE, 1, 12345, packet) == sizeof(state));
  assert(!memcmp(packet, state, sizeof(state)));
  assert(sensor_query_packet(QUERY_HASH, 1, 0, packet) == sizeof(hash));
  assert(!memcmp(packet, hash, sizeof(hash)));
  assert(sensor_query_packet(QUERY_WRAPPED, 1, 0, packet) == sizeof(wrapped));
  assert(!memcmp(packet, wrapped, sizeof(wrapped)));
  assert(sensor_query_packet(QUERY_STATE, 0xabcd, 0xffff, packet) ==
         sizeof(state));
  assert(packet[2] == 0xcd && packet[3] == 0xab && packet[12] == 0xff &&
         packet[13] == 0xff);
  assert(sensor_query_packet((enum sensor_query)99, 1, 0, packet) == 0);

  /* An old A8 reply must not satisfy the new firmware preflight before ACK. */
  {
    uint8_t record[64];
    const uint8_t name[] = "GF_ITE_EC_20066";
    size_t n = frame(record, 0xa8, name, sizeof(name));
    struct readback_parser p = {.query = QUERY_VERSION};
    assert(readback_feed(&p, record, n) == 0 && !p.done && p.foreign == 1);
    const uint8_t negative_ack[] = {0xa8, 0};
    n = frame(record, 0xb0, negative_ack, sizeof(negative_ack));
    assert(readback_feed(&p, record, n) == 0 && !p.ack);
    const uint8_t ack[] = {0xa8, 1};
    n = frame(record, 0xb0, ack, sizeof(ack));
    assert(readback_feed(&p, record, n) == 0 && p.ack && !p.done);
    n = frame(record, 0xa8, name, sizeof(name));
    assert(readback_feed(&p, record, n) == 0 && p.done &&
           p.length == sizeof(name));
  }

  /* Real 20066 metadata, synthetic digest bytes only: hash selector BB02,
   * canonical BB01 object in the response, and exactly 32 data bytes.
   */
  {
    uint8_t hash_payload[41] = {0, 3, 0, 1, 0xbb, 32, 0, 0, 0};
    memset(hash_payload + 9, 0xa5, 32);
    uint8_t hash_frame[49];
    size_t n = frame(hash_frame, 0xe4, hash_payload, sizeof(hash_payload));
    struct readback_parser p = {.query = QUERY_HASH};
    assert(readback_feed(&p, hash_frame, n) == 0);
    assert(p.done && !p.malformed && p.length == 32);
    assert(!memcmp(p.data, hash_payload + 9, 32));
    p = (struct readback_parser){.query = QUERY_WRAPPED};
    assert(readback_feed(&p, hash_frame, n) == 0);
    assert(!p.done && p.foreign == 1 && p.length == 0);
  }

  uint8_t payload[READBACK_CAPACITY + 10] = {0, 3, 0, 1, 0xbb, 102, 0, 0, 0};
  for (size_t i = 0; i < 102; i++)
    payload[9 + i] = i;
  uint8_t record[READBACK_CAPACITY + 32];
  size_t size = frame(record, 0xe4, payload, 111);
  for (size_t cut = 0; cut <= size; cut++) {
    struct readback_parser p = {.query = QUERY_WRAPPED};
    assert(readback_feed(&p, record, cut) == 0);
    assert(readback_feed(&p, record + cut, size - cut) == 0);
    assert(p.done && !p.malformed && !p.status && p.length == 102);
    assert(!memcmp(p.data, payload + 9, 102));
  }
  struct readback_parser p = {.query = QUERY_HASH};
  assert(readback_feed(&p, record, size) == 0);
  assert(!p.done &&
         p.foreign == 1); /* A stale wrapper is not the requested hash. */
  payload[3] = 2;
  size = frame(record, 0xe4, payload, 111);
  assert(readback_feed(&p, record, size) == 0 && p.done);

  p = (struct readback_parser){.query = QUERY_HASH};
  record[size - 1] ^= 1;
  assert(readback_feed(&p, record, size) == 0 && !p.done && p.rejected == 1);
  size = frame(record, 0xe4, payload, 111);
  assert(record[size - 1] != 0x88);
  record[size - 1] = 0x88;
  p = (struct readback_parser){.query = QUERY_HASH};
  assert(readback_feed(&p, record, size) == 0 && !p.done && p.rejected == 1);

  const uint8_t refusal[] = {7};
  size = frame(record, 0xe4, refusal, sizeof(refusal));
  p = (struct readback_parser){.query = QUERY_WRAPPED};
  assert(readback_feed(&p, record, size) == 0 && p.done && p.status == 7 &&
         !p.malformed);
  const uint8_t ack[] = {0xe4, 1};
  size = frame(record, 0xb0, ack, sizeof(ack));
  p = (struct readback_parser){.query = QUERY_HASH};
  assert(readback_feed(&p, record, size) == 0 && !p.done && p.ack);

  payload[5] = 101; /* Declared length must match, not just fit in the reply. */
  size = frame(record, 0xe4, payload, 111);
  p = (struct readback_parser){.query = QUERY_HASH};
  assert(readback_feed(&p, record, size) == 0 && p.malformed);
  size = frame(record, 0xe4, payload, 8);
  p = (struct readback_parser){.query = QUERY_HASH};
  assert(readback_feed(&p, record, size) == 0 && p.malformed);
  p = (struct readback_parser){.query = QUERY_HASH};
  const uint8_t oversize[] = {0xa0, 0xff, 0xff, 0x9e};
  assert(readback_feed(&p, oversize, sizeof(oversize)) == 0 && p.rejected == 1);
  assert(readback_feed(&p, record, sizeof(p.pending) + 1) == -1);

  /* A maximum-size reply over multiple 256-byte mailboxes. */
  payload[3] = 1;
  payload[5] = 0;
  payload[6] = 8;
  memset(payload + 9, 0x31, READBACK_CAPACITY);
  size = frame(record, 0xe4, payload, READBACK_CAPACITY + 9);
  p = (struct readback_parser){.query = QUERY_WRAPPED};
  for (size_t offset = 0; offset < size; offset += 256) {
    size_t n = size - offset < 256 ? size - offset : 256;
    assert(readback_feed(&p, record + offset, n) == 0);
  }
  assert(p.done && p.length == READBACK_CAPACITY && !p.malformed);
  puts("Readback protocol tests passed: native vectors, fragmentation, "
       "checksums, tags, refusals and bounds.");
}
