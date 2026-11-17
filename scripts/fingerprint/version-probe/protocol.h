/* SPDX-License-Identifier: MIT */
#ifndef GXFP_VERSION_PROTOCOL_H
#define GXFP_VERSION_PROTOCOL_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

extern const uint8_t version_query[16];
struct version_parser {
  uint8_t pending[512];
  size_t used;
  bool ack;
  char version[65];
  unsigned int frames;
  unsigned int rejected;
};
int version_feed(struct version_parser *parser, const uint8_t *data,
                 size_t size);
#endif
