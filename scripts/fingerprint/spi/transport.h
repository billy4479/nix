/* SPDX-License-Identifier: MIT */
#ifndef GXFP_TRANSPORT_H
#define GXFP_TRANSPORT_H
#include "queries.h"
#define SENSOR_SPEED 10000000U
int sensor_open(const char *node);
int sensor_configure(int fd);
int sensor_send(int fd, enum sensor_query query, uint16_t counter,
                uint16_t timestamp);
int sensor_read_small(int fd, uint8_t response[64]);
int sensor_read_mailbox(int fd, uint8_t status[4], uint8_t response[256]);
long sensor_milliseconds(void);
void sensor_pause(long milliseconds);
#endif
