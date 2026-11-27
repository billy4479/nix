/* SPDX-License-Identifier: MIT */
#include "payload.h"
#include <string.h>

static void le32(uint8_t *out, uint32_t value) {
  out[0] = value;
  out[1] = value >> 8;
  out[2] = value >> 16;
  out[3] = value >> 24;
}
size_t gxfp_payload(uint8_t out[GXFP_PAYLOAD_MAX],
                    const uint8_t wrapper[GXFP_WRAPPER_SIZE],
                    const uint8_t seed8[8]) {
  size_t offset = 0;
  le32(out, 0xbb010002);
  le32(out + 4, 8);
  memcpy(out + 8, seed8, 8);
  offset = 16;
  le32(out + offset, 0xbb010003);
  le32(out + offset + 4, GXFP_WRAPPER_SIZE);
  memcpy(out + offset + 8, wrapper, GXFP_WRAPPER_SIZE);
  offset += 8 + GXFP_WRAPPER_SIZE;
  size_t padded = (offset + 3) & ~(size_t)3;
  memset(out + offset, 0, padded - offset);
  return padded;
}
size_t gxfp_record(uint8_t out[GXFP_RECORD_MAX], const uint8_t *payload,
                   size_t size) {
  size_t inner = 4 + size;
  size_t total = 4 + inner;
  size_t padded = (total + 3) & ~(size_t)3;
  if (padded > GXFP_RECORD_MAX)
    return 0;
  out[0] = 0xa0;
  out[1] = inner;
  out[2] = inner >> 8;
  out[3] = out[0] + out[1] + out[2];
  out[4] = 0xe0;
  out[5] = size + 1;
  out[6] = (size + 1) >> 8;
  memcpy(out + 7, payload, size);
  uint8_t checksum = 0xaa - out[4] - out[5] - out[6];
  for (size_t i = 0; i < size; i++)
    checksum -= payload[i];
  out[7 + size] = checksum;
  memset(out + total, 0, padded - total);
  return padded;
}
size_t gxfp_fragment(uint8_t out[GXFP_FRAGMENT_MAX], const uint8_t *chunk,
                     size_t size, uint16_t counter) {
  if (size == 0 || size > 252)
    return 0;
  out[0] = 0xcc;
  out[1] = 0xf2;
  out[2] = counter;
  out[3] = counter >> 8;
  memcpy(out + 4, chunk, size);
  return size + 4;
}
