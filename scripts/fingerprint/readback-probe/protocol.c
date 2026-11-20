/* SPDX-License-Identifier: MIT */
#include "protocol.h"
#include <string.h>

static uint8_t sum(const uint8_t *data, size_t size) {
  uint8_t result = 0;
  for (size_t i = 0; i < size; i++)
    result += data[i];
  return result;
}
static uint32_t le32(const uint8_t *data) {
  return data[0] | ((uint32_t)data[1] << 8) | ((uint32_t)data[2] << 16) |
         ((uint32_t)data[3] << 24);
}
static void consume(struct readback_parser *parser, size_t size) {
  memmove(parser->pending, parser->pending + size, parser->used - size);
  parser->used -= size;
}
static void accept(struct readback_parser *p, uint8_t command,
                   const uint8_t *payload, size_t size) {
  uint8_t expected = p->query == QUERY_VERSION ? 0xa8
                     : p->query == QUERY_STATE ? 0xae
                                               : 0xe4;
  if (command == 0xb0 && size == 2 && (payload[0] & 0xfe) == expected) {
    p->ack = true;
    return;
  }
  if (p->done || command != expected)
    return;
  if (expected == 0xe4) {
    if (size < 1) {
      p->done = p->malformed = true;
      return;
    }
    if (payload[0] != 0) {
      p->status = payload[0];
      p->done = true;
      return;
    }
    if (size < 9) {
      p->done = p->malformed = true;
      return;
    }
    uint32_t type = p->query == QUERY_HASH ? KEY_HASH_TYPE : KEY_WRAPPED_TYPE;
    if (le32(payload + 1) != type) {
      p->foreign++;
      return;
    }
    if (le32(payload + 5) != size - 9) {
      p->done = p->malformed = true;
      return;
    }
    payload += 9;
    size -= 9;
  }
  if (size > sizeof(p->data)) {
    p->done = p->malformed = true;
    return;
  }
  memcpy(p->data, payload, size);
  p->length = size;
  p->done = true;
}
int readback_feed(struct readback_parser *p, const uint8_t *data,
                  size_t length) {
  if (length > sizeof(p->pending) - p->used)
    return -1;
  if (length)
    memcpy(p->pending + p->used, data, length);
  p->used += length;
  while (p->used >= 4) {
    uint8_t *frame = p->pending;
    if (frame[0] != 0xa0 || sum(frame, 3) != frame[3]) {
      consume(p, 1);
      continue;
    }
    size_t size = frame[1] | ((size_t)frame[2] << 8);
    if (size < 4 || size > READBACK_CAPACITY + 13) {
      p->rejected++;
      consume(p, 1);
      continue;
    }
    if (p->used < size + 4)
      break;
    uint8_t *body = frame + 4;
    size_t declared = body[1] | ((size_t)body[2] << 8);
    if (declared + 3 != size || sum(body, size) != 0xaa) {
      p->rejected++;
    } else {
      p->frames++;
      accept(p, body[0], body + 3, size - 4);
    }
    consume(p, size + 4);
  }
  return 0;
}
