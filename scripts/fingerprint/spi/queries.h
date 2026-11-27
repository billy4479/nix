/* SPDX-License-Identifier: MIT */
#ifndef GXFP_QUERIES_H
#define GXFP_QUERIES_H
#include <stddef.h>
#include <stdint.h>

enum sensor_query {
  QUERY_VERSION,
  QUERY_STATE,
  QUERY_HASH,
  QUERY_WRAPPED,
  QUERY_UPLOAD,
  QUERY_TLS_START
};
#define KEY_HASH_TYPE 0xbb020003U
#define KEY_WRAPPED_TYPE 0xbb010003U
/* No arbitrary command, tag, payload, length or offset can be supplied. */
size_t sensor_query_packet(enum sensor_query query, uint16_t counter,
                           uint16_t timestamp, uint8_t packet[24]);
#endif
