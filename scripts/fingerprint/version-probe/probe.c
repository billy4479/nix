/* SPDX-License-Identifier: MIT */
#define _GNU_SOURCE
#include "protocol.h"
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
#define SPEED 10000000U

static void dump(const char *label, const uint8_t *data, size_t size) {
  printf("%s=", label);
  for (size_t i = 0; i < size; i++)
    printf("%02x", data[i]);
  putchar('\n');
}

static int transfer(int fd, const uint8_t *tx, uint8_t *rx, size_t size) {
  struct spi_ioc_transfer request = {
      .tx_buf = (uintptr_t)tx,
      .rx_buf = (uintptr_t)rx,
      .len = size,
      .speed_hz = SPEED,
      .bits_per_word = 8,
  };
  int result = ioctl(fd, SPI_IOC_MESSAGE(1), &request);
  if (result != (int)size) {
    if (result < 0)
      perror("SPI transfer");
    else
      fprintf(stderr, "Short SPI transfer: %d, expected %zu\n", result, size);
    return -1;
  }
  return 0;
}

static long milliseconds(void) {
  struct timespec value;
  if (clock_gettime(CLOCK_MONOTONIC, &value) != 0)
    return -1;
  return value.tv_sec * 1000L + value.tv_nsec / 1000000L;
}

static void pause_ms(long value) {
  struct timespec delay = {.tv_sec = value / 1000,
                           .tv_nsec = (value % 1000) * 1000000L};
  while (nanosleep(&delay, &delay) < 0 && errno == EINTR) {
  }
}

static int query(int fd) {
  uint32_t mode = SPI_MODE_0, speed = SPEED;
  uint8_t bits = 8;
  if (ioctl(fd, SPI_IOC_WR_MODE32, &mode) < 0 ||
      ioctl(fd, SPI_IOC_WR_BITS_PER_WORD, &bits) < 0 ||
      ioctl(fd, SPI_IOC_WR_MAX_SPEED_HZ, &speed) < 0 ||
      ioctl(fd, SPI_IOC_RD_MODE32, &mode) < 0 ||
      ioctl(fd, SPI_IOC_RD_BITS_PER_WORD, &bits) < 0 ||
      ioctl(fd, SPI_IOC_RD_MAX_SPEED_HZ, &speed) < 0) {
    perror("SPI configuration");
    return 1;
  }
  if (mode != SPI_MODE_0 || bits != 8 || speed != SPEED) {
    fprintf(stderr,
            "SPI parameters did not match reviewed firmware resources\n");
    return 1;
  }
  printf("spi_mode=0\nbits=8\nrequested_speed_hz=%u\nuserspace_gpio_requests="
         "none\n",
         SPEED);
  dump("tx_version", version_query, sizeof(version_query));
  long start = milliseconds();
  if (start < 0)
    return 1;
  if (transfer(fd, version_query, NULL, sizeof(version_query)) != 0)
    return 1;

  /* Small ITE reads used by the reference transport: four status bytes followed
   * by a 60-byte response window. Polling avoids requesting any GPIO line.
   * No preamble, reset, retry of A8, state/config upload, or TLS setup.
   */
  const uint8_t read_request[64] = {0xbb, 0xf1, 0x00, 0x00};
  uint8_t response[64];
  struct version_parser parser = {0};
  pause_ms(5);
  for (unsigned int i = 0; i < 128; i++) {
    long now = milliseconds();
    if (now < 0 || now - start >= 1500)
      break;
    if (transfer(fd, read_request, response, sizeof(response)) != 0)
      return 1;
    dump("rx_window", response, sizeof(response));
    if (version_feed(&parser, response + 4, 60) != 0) {
      fprintf(stderr, "Response parser capacity exceeded\n");
      return 1;
    }
    if (parser.version[0])
      break;
    pause_ms(10);
  }
  printf("ack_seen=%s\nvalid_frames=%u\nrejected_frames=%u\n",
         parser.ack ? "yes" : "no", parser.frames, parser.rejected);
  if (parser.version[0]) {
    printf("firmware=%s\nresult=version_received\n", parser.version);
    return 0;
  }
  printf("result=no_valid_version\n");
  return 2;
}

int main(int argc, char **argv) {
  if (argc == 2 && strcmp(argv[1], "--help") == 0) {
    puts("Use the reviewed run.sh as sudo. Sends one fixed firmware-version "
         "query.\n"
         "No userspace GPIO requests, reset, key writes, sensor configuration, "
         "or "
         "fallback.");
    return 0;
  }
  if (argc != 2 || geteuid() != 0 || strncmp(argv[1], "/dev/spidev", 11) != 0) {
    fprintf(stderr, "Use the reviewed run.sh as sudo\n");
    return 1;
  }
  int fd = open(argv[1], O_RDWR | O_CLOEXEC | O_NOFOLLOW);
  if (fd < 0) {
    perror("open SPI node");
    return 1;
  }
  struct stat info;
  char sysfs[128], actual[PATH_MAX];
  if (fstat(fd, &info) != 0 || !S_ISCHR(info.st_mode)) {
    fprintf(stderr, "Not a character device\n");
    close(fd);
    return 1;
  }
  snprintf(sysfs, sizeof(sysfs), "/sys/dev/char/%u:%u/device",
           major(info.st_rdev), minor(info.st_rdev));
  if (!realpath(sysfs, actual) || strcmp(actual, SENSOR) != 0) {
    fprintf(stderr,
            "Refusing a node that is not the reviewed fingerprint device\n");
    close(fd);
    return 1;
  }
  setvbuf(stdout, NULL, _IOLBF, 0);
  int result = query(fd);
  close(fd);
  return result;
}
