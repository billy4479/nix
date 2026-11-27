/* SPDX-License-Identifier: MIT */
#define _GNU_SOURCE
#include "transport.h"
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <linux/spi/spidev.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <time.h>
#include <unistd.h>

#define SENSOR                                                                 \
  "/sys/devices/pci0000:00/0000:00:1e.3/pxa2xx-spi.2/spi_master/spi1/"         \
  "spi-GXFP5120:00"

int sensor_open(const char *node) {
  if (geteuid() != 0 || strncmp(node, "/dev/spidev", 11) != 0) {
    fprintf(stderr, "Use the reviewed run.sh as sudo\n");
    return -1;
  }
  int fd = open(node, O_RDWR | O_CLOEXEC | O_NOFOLLOW);
  if (fd < 0) {
    perror("open SPI node");
    return -1;
  }
  struct stat info;
  char sysfs[128], actual[PATH_MAX];
  if (fstat(fd, &info) != 0 || !S_ISCHR(info.st_mode)) {
    fprintf(stderr, "Not a character device\n");
    close(fd);
    return -1;
  }
  snprintf(sysfs, sizeof(sysfs), "/sys/dev/char/%u:%u/device",
           major(info.st_rdev), minor(info.st_rdev));
  if (!realpath(sysfs, actual) || strcmp(actual, SENSOR) != 0) {
    fprintf(stderr,
            "Refusing a node that is not the reviewed fingerprint device\n");
    close(fd);
    return -1;
  }
  return fd;
}

int sensor_configure(int fd) {
  uint32_t mode = SPI_MODE_0, speed = SENSOR_SPEED;
  uint8_t bits = 8;
  if (ioctl(fd, SPI_IOC_WR_MODE32, &mode) < 0 ||
      ioctl(fd, SPI_IOC_WR_BITS_PER_WORD, &bits) < 0 ||
      ioctl(fd, SPI_IOC_WR_MAX_SPEED_HZ, &speed) < 0 ||
      ioctl(fd, SPI_IOC_RD_MODE32, &mode) < 0 ||
      ioctl(fd, SPI_IOC_RD_BITS_PER_WORD, &bits) < 0 ||
      ioctl(fd, SPI_IOC_RD_MAX_SPEED_HZ, &speed) < 0) {
    perror("SPI configuration");
    return -1;
  }
  if (mode != SPI_MODE_0 || bits != 8 || speed != SENSOR_SPEED) {
    fprintf(stderr,
            "SPI parameters did not match reviewed firmware resources\n");
    return -1;
  }
  printf("spi_mode=0\nbits=8\nrequested_speed_hz=%u\nuserspace_gpio_requests="
         "none\n",
         SENSOR_SPEED);
  return 0;
}

static int exchange(int fd, struct spi_ioc_transfer *requests, size_t count,
                    size_t size) {
  unsigned long request = count == 1 ? SPI_IOC_MESSAGE(1) : SPI_IOC_MESSAGE(2);
  int result = ioctl(fd, request, requests);
  if (result != (int)size) {
    if (result < 0)
      perror("SPI transfer");
    else
      fprintf(stderr, "Short SPI transfer: %d, expected %zu\n", result, size);
    return -1;
  }
  return 0;
}

int sensor_send(int fd, enum sensor_query query, uint16_t counter,
                uint16_t timestamp) {
  uint8_t packet[24];
  size_t length = sensor_query_packet(query, counter, timestamp, packet);
  if (!length) {
    errno = EINVAL;
    return -1;
  }
  struct spi_ioc_transfer request = {
      .tx_buf = (uintptr_t)packet,
      .len = length,
      .speed_hz = SENSOR_SPEED,
      .bits_per_word = 8,
  };
  return exchange(fd, &request, 1, length);
}

int sensor_read_small(int fd, uint8_t response[64]) {
  const uint8_t command[64] = {0xbb, 0xf1, 0, 0};
  struct spi_ioc_transfer request = {
      .tx_buf = (uintptr_t)command,
      .rx_buf = (uintptr_t)response,
      .len = 64,
      .speed_hz = SENSOR_SPEED,
      .bits_per_word = 8,
  };
  return exchange(fd, &request, 1, 64);
}

int sensor_read_mailbox(int fd, uint8_t status[4], uint8_t response[256]) {
  const uint8_t command[4] = {0xbb, 0xf1, 0, 0};
  const uint8_t zeros[256] = {0};
  /* One CS assertion, write four command bytes then read the full mailbox.
   * Corresponds to the official two-entry SPB sequence, not a reset/preamble.
   */
  struct spi_ioc_transfer requests[2] = {
      {.tx_buf = (uintptr_t)command,
       .rx_buf = (uintptr_t)status,
       .len = 4,
       .speed_hz = SENSOR_SPEED,
       .bits_per_word = 8},
      {.tx_buf = (uintptr_t)zeros,
       .rx_buf = (uintptr_t)response,
       .len = 256,
       .speed_hz = SENSOR_SPEED,
       .bits_per_word = 8},
  };
  return exchange(fd, requests, 2, 260);
}

int sensor_write_fragment(int fd, const uint8_t *fragment, size_t length) {
  struct spi_ioc_transfer request = {
      .tx_buf = (uintptr_t)fragment,
      .len = length,
      .speed_hz = SENSOR_SPEED,
      .bits_per_word = 8,
  };
  return exchange(fd, &request, 1, length);
}

long sensor_milliseconds(void) {
  struct timespec value;
  if (clock_gettime(CLOCK_MONOTONIC, &value) != 0)
    return -1;
  return value.tv_sec * 1000L + value.tv_nsec / 1000000L;
}

void sensor_pause(long milliseconds) {
  struct timespec delay = {.tv_sec = milliseconds / 1000,
                           .tv_nsec = (milliseconds % 1000) * 1000000L};
  while (nanosleep(&delay, &delay) < 0 && errno == EINTR) {
  }
}
