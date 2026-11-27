/* SPDX-License-Identifier: MIT */
/* Emulate the ITE envelope over a socket connected to a real TLS peer. */
#define _POSIX_C_SOURCE 200809L
#include "../spi/transport.h"
#include "session.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static int read_exact(int fd, uint8_t *out, size_t n) {
  while (n) {
    ssize_t r = read(fd, out, n);
    if (r <= 0)
      return -1;
    out += r;
    n -= (size_t)r;
  }
  return 0;
}
static size_t peer_record(int fd, uint8_t *out, size_t capacity) {
  if (capacity < 5 || read_exact(fd, out, 5))
    return 0;
  size_t body = (size_t)out[3] << 8 | out[4];
  if (body > capacity - 5 || read_exact(fd, out + 5, body))
    return 0;
  return body + 5;
}
int sensor_write_fragment(int fd, const uint8_t *frame, size_t length) {
  static unsigned int expected_counter = 3;
  assert(length >= 8 && frame[0] == 0xcc && frame[1] == 0xf2);
  assert((unsigned int)(frame[2] | frame[3] << 8) == expected_counter++);
  size_t n = frame[5];
  assert(frame[4] == 0xb0 && frame[6] == 0 && frame[7] == (uint8_t)(0xb0 + n));
  assert(length == ((n + 11) & ~(size_t)3));
  for (size_t i = n + 8; i < length; i++)
    assert(frame[i] == 0);
  return write(fd, frame + 8, n) == (ssize_t)n ? 0 : -1;
}
int sensor_read_mailbox(int fd, uint8_t status[4], uint8_t out[256]) {
  memset(status, 0, 4);
  memset(out, 0, 256);
  size_t n = peer_record(fd, out + 4, 252);
  if (!n)
    return -1;
  out[0] = 0xb0;
  out[1] = n;
  out[3] = 0xb0 + n;
  return 0;
}
long sensor_milliseconds(void) {
  struct timespec ts;
  assert(clock_gettime(CLOCK_MONOTONIC, &ts) == 0);
  return ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}
void sensor_pause(long milliseconds) { (void)milliseconds; }
int main(int argc, char **argv) {
  assert(argc == 2);
  int fd = atoi(argv[1]);
  uint8_t hello[252];
  size_t n = peer_record(fd, hello, sizeof(hello));
  assert(n >= 5);
  return gxfp_session(fd, hello, n);
}
