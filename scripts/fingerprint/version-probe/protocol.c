/* SPDX-License-Identifier: MIT */
#include "protocol.h"
#include <string.h>

/* The only sensor command this program can send: A8, two zero payload bytes.
 * ITE counter 1, message-pack header, inner checksum, two padding bytes.
 */
const uint8_t version_query[16] = {
    0xcc, 0xf2, 0x01, 0x00, 0xa0, 0x06, 0x00, 0xa6,
    0xa8, 0x03, 0x00, 0x00, 0x00, 0xff, 0x00, 0x00,
};

static uint8_t sum(const uint8_t *data, size_t size) {
  uint8_t result = 0;
  for (size_t i = 0; i < size; i++)
    result += data[i];
  return result;
}

static void consume(struct version_parser *parser, size_t size) {
  memmove(parser->pending, parser->pending + size, parser->used - size);
  parser->used -= size;
}

int version_feed(struct version_parser *parser, const uint8_t *data,
                 size_t size) {
  if (size > sizeof(parser->pending) - parser->used)
    return -1;
  memcpy(parser->pending + parser->used, data, size);
  parser->used += size;
  while (parser->used >= 4) {
    uint8_t *frame = parser->pending;
    if (frame[0] != 0xa0 || sum(frame, 3) != frame[3]) {
      consume(parser, 1);
      continue;
    }
    size_t body = frame[1] | ((size_t)frame[2] << 8);
    if (body < 4 || body > 68) {
      parser->rejected++;
      consume(parser, 1);
      continue;
    }
    if (parser->used < body + 4)
      break;
    uint8_t *inner = frame + 4;
    size_t declared = inner[1] | ((size_t)inner[2] << 8);
    if (declared + 3 != body || sum(inner, body) != 0xaa) {
      parser->rejected++;
      consume(parser, body + 4);
      continue;
    }
    parser->frames++;
    size_t payload = body - 4;
    if (inner[0] == 0xb0 && payload >= 2 && inner[3] == 0xa8)
      parser->ack = true;
    if (inner[0] == 0xa8 && payload > 0 && !parser->version[0]) {
      size_t length = 0;
      bool valid = true, terminated = false;
      for (size_t i = 0; i < payload; i++) {
        uint8_t value = inner[3 + i];
        if (value == 0) {
          terminated = true;
        } else if (terminated || value < 32 || value > 126) {
          valid = false;
        } else {
          length++;
        }
      }
      if (valid && length > 0) {
        memcpy(parser->version, inner + 3, length);
        parser->version[length] = '\0';
      } else {
        parser->rejected++;
      }
    }
    consume(parser, body + 4);
  }
  return 0;
}
