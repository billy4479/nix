/* SPDX-License-Identifier: MIT */
#include "queries.h"
#include <string.h>

size_t sensor_query_packet(enum sensor_query query, uint16_t counter,
                           uint16_t timestamp, uint8_t packet[24]) {
  uint8_t command, payload[8] = {0};
  size_t length;
  switch (query) {
  case QUERY_VERSION:
    command = 0xa8;
    length = 2;
    break;
  case QUERY_TLS_START:
    command = 0xd1;
    length = 2;
    break;
  case QUERY_STATE:
    command = 0xaf;
    length = 5;
    payload[0] = 0x55;
    payload[1] = timestamp;
    payload[2] = timestamp >> 8;
    break;
  case QUERY_HASH:
  case QUERY_WRAPPED: {
    command = 0xe4;
    length = 8;
    uint32_t type = query == QUERY_HASH ? KEY_HASH_TYPE : KEY_WRAPPED_TYPE;
    for (unsigned int i = 0; i < 4; i++)
      payload[i] = type >> (8 * i);
    break;
  }
  default:
    return 0;
  }
  memset(packet, 0, 24);
  packet[0] = 0xcc;
  packet[1] = 0xf2;
  packet[2] = counter;
  packet[3] = counter >> 8;
  packet[4] = 0xa0;
  packet[5] = length + 4;
  packet[7] = packet[4] + packet[5];
  packet[8] = command;
  packet[9] = length + 1;
  memcpy(packet + 11, payload, length);
  /* The official ITE branch adds the no-ACK bit AFTER calculating checksum. */
  /* The reference GXFP5120 D1 frame instead checksums the literal opcode. */
  uint8_t checksum = 0xaa -
                     (query == QUERY_TLS_START ? command : (command & 0xfe)) -
                     packet[9];
  for (size_t i = 0; i < length; i++)
    checksum -= payload[i];
  packet[11 + length] = checksum;
  return (12 + length + 3) & ~(size_t)3;
}
