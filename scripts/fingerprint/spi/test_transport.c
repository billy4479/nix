/* SPDX-License-Identifier: MIT */
#include "transport.h"
#include <assert.h>
#include <errno.h>
#include <linux/spi/spidev.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

static unsigned int calls;
static int short_io;
static uint8_t sent[24];
int __wrap_ioctl(int fd, unsigned long op, ...) {
  assert(fd == 77);
  calls++;
  va_list args;
  va_start(args, op);
  struct spi_ioc_transfer *q = va_arg(args, void *);
  va_end(args);
  if (op == SPI_IOC_MESSAGE(1)) {
    assert(q->speed_hz == SENSOR_SPEED && q->bits_per_word == 8 &&
           !q->cs_change);
    const uint8_t *tx = (const uint8_t *)(uintptr_t)q->tx_buf;
    if (q->len == 64) {
      assert(!memcmp(tx, (uint8_t[]){0xbb, 0xf1, 0, 0}, 4));
      for (size_t i = 4; i < 64; i++)
        assert(tx[i] == 0);
      memset((void *)(uintptr_t)q->rx_buf, 0x19, 64);
    } else {
      assert(q->len <= sizeof(sent) && !q->rx_buf);
      memcpy(sent, tx, q->len);
    }
    return short_io ? 0 : (int)q->len;
  }
  assert(op == SPI_IOC_MESSAGE(2));
  assert(q[0].len == 4 && q[1].len == 256);
  assert(!memcmp((void *)(uintptr_t)q[0].tx_buf, (uint8_t[]){0xbb, 0xf1, 0, 0},
                 4));
  for (size_t i = 0; i < 256; i++)
    assert(((uint8_t *)(uintptr_t)q[1].tx_buf)[i] == 0);
  for (size_t i = 0; i < 2; i++)
    assert(q[i].speed_hz == SENSOR_SPEED && q[i].bits_per_word == 8 &&
           !q[i].cs_change);
  memset((void *)(uintptr_t)q[0].rx_buf, 0x22, 4);
  memset((void *)(uintptr_t)q[1].rx_buf, 0x33, 256);
  return short_io ? 0 : 260;
}
int main(void) {
  assert(sensor_open("/dev/null") == -1); /* Refused before any open/ioctl. */
  assert(calls == 0);
  assert(sensor_send(77, QUERY_WRAPPED, 4, 0) == 0);
  assert(sent[2] == 4 && sent[8] == 0xe4 && sent[13] == 1);
  unsigned int before = calls;
  assert(sensor_send(77, (enum sensor_query)99, 1, 0) == -1 && calls == before);
  uint8_t status[4], data[256];
  assert(sensor_read_mailbox(77, status, data) == 0);
  assert(status[3] == 0x22 && data[255] == 0x33);
  assert(sensor_read_small(77, data) == 0 && data[63] == 0x19);
  short_io = 1;
  assert(sensor_read_mailbox(77, status, data) == -1);
  puts("SPI transport tests passed: allowlist, full/small reads, CS continuity "
       "and short I/O rejection (all mocked).");
}
