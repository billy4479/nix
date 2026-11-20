/* SPDX-License-Identifier: MIT */
#ifndef GXFP_READBACK_PROTOCOL_H
#define GXFP_READBACK_PROTOCOL_H
#include "../spi/queries.h"
#include <stdbool.h>
#define READBACK_CAPACITY 2048
struct readback_parser {
  enum sensor_query query;
  uint8_t pending[4096], data[READBACK_CAPACITY];
  size_t used, length;
  unsigned int frames, rejected, foreign;
  uint8_t status;
  bool done, malformed, ack;
};
int readback_feed(struct readback_parser *parser, const uint8_t *data,
                  size_t length);
#endif
