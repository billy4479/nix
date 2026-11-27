/* SPDX-License-Identifier: MIT */
#ifndef GXFP_SESSION_H
#define GXFP_SESSION_H
#include <stddef.h>
#include <stdint.h>
int gxfp_session(int fd, const uint8_t *hello, size_t length);
#endif
