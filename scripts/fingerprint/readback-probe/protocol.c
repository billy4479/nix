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
  uint8_t expected;
  switch (p->query) {
  case QUERY_VERSION:
    expected = 0xa8;
    break;
  case QUERY_STATE:
    expected = 0xae;
    break;
  case QUERY_UPLOAD:
    expected = 0xe0;
    break;
  case QUERY_TLS_START:
    expected = 0xd0;
    break;
  default:
    expected = 0xe4;
    break;
  }
  if (command == 0xb0 && size == 2 && (payload[0] & 0xfe) == expected &&
      (payload[1] & 1)) {
    p->ack = true;
    return;
  }
  if (p->query == QUERY_TLS_START || p->done || command != expected)
    return;
  /* The mailbox may contain an older reply. Require a matching ACK first
   * for version, upload completion, and provisioning hash checks.
   */
  if ((expected == 0xa8 || expected == 0xe0 || p->require_ack) && !p->ack) {
    p->foreign++;
    return;
  }
  if (expected == 0xe0) {
    if (size < 1) {
      p->done = p->malformed = true;
      return;
    }
    p->status = payload[0];
    p->done = true;
    return;
  }
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
    uint32_t type = le32(payload + 1);
    /* 20066 returns the stored BB01 object tag for a BB02 hash request.
     * The OEM reader accepts this; do not require an echoed read selector.
     * Keep the allowlist exact, rather than accepting arbitrary reply tags.
     */
    if (type != KEY_WRAPPED_TYPE &&
        !(p->query == QUERY_HASH && type == KEY_HASH_TYPE)) {
      p->foreign++;
      return;
    }
    if (le32(payload + 5) != size - 9) {
      p->done = p->malformed = true;
      return;
    }
    payload += 9;
    size -= 9;
    /* A canonical-tag 32-byte hash is not a wrapped key: it can be cached,
     * or arrive again after the key-read ACK (observed on this device).
     * Conversely, a 102-byte key wrapper is not the requested hash.
     */
    if ((p->query == QUERY_WRAPPED && size == 32) ||
        (p->query == QUERY_HASH && type == KEY_WRAPPED_TYPE && size == 102)) {
      p->foreign++;
      return;
    }
  }
  if (size > sizeof(p->data)) {
    p->done = p->malformed = true;
    return;
  }
  memcpy(p->data, payload, size);
  p->length = size;
  p->done = true;
}
/* The reference ITE firmware envelopes one TLS record in a B0 frame.
 * Recognize ClientHello only; no TLS response or key is sent here. */
static bool client_hello(const uint8_t *b, size_t n) {
  if (n < 45 || b[0] != 0x16 || b[1] != 3 || b[2] > 3 ||
      ((size_t)b[3] << 8 | b[4]) != n - 5 || b[5] != 1 || b[6] != 0 ||
      ((size_t)b[7] << 8 | b[8]) != n - 9 || b[9] != 3 || b[10] != 3)
    return false;
  size_t i = 44 + (size_t)b[43];
  if (b[43] > 32 || i + 2 > n)
    return false;
  size_t suites = (size_t)b[i] << 8 | b[i + 1];
  i += 2;
  if (suites < 2 || suites % 2 || i + suites >= n)
    return false;
  bool offered = false;
  for (size_t j = i; j < i + suites; j += 2)
    if (b[j] == 0 && b[j + 1] == 0xae)
      offered = true;
  i += suites;
  size_t compression = b[i++];
  if (!offered || !compression || i + compression > n)
    return false;
  if (!memchr(b + i, 0, compression))
    return false;
  i += compression;
  return i == n || (i + 2 <= n && ((size_t)b[i] << 8 | b[i + 1]) == n - i - 2);
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
    bool tls = p->query == QUERY_TLS_START && frame[0] == 0xb0;
    if ((frame[0] != 0xa0 && !tls) || sum(frame, 3) != frame[3]) {
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
    if (tls) {
      if (!p->done && client_hello(body, size)) {
        memcpy(p->data, body, size);
        p->length = size;
        p->done = true;
        p->frames++;
      } else {
        p->foreign++;
      }
      consume(p, size + 4);
      continue;
    }
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
