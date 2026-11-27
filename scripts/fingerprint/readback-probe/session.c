/* SPDX-License-Identifier: MIT */
#define _GNU_SOURCE
#include "session.h"
#include "../spi/transport.h"
#include <errno.h>
#include <fcntl.h>
#include <mbedtls/platform_util.h>
#include <mbedtls/ssl.h>
#include <psa/crypto.h>
#include <stdio.h>
#include <string.h>
#include <sys/random.h>
#include <sys/stat.h>
#include <unistd.h>

#ifndef KEY_PATH
#define KEY_PATH "/var/lib/fingerprint-gxfp5120.psk"
#endif

struct link {
  int fd;
  uint16_t counter;
  long start;
  uint8_t input[252];
  size_t length, consumed;
  unsigned int sent, received;
};

static int load_key(uint8_t key[32]) {
  int fd = open(KEY_PATH, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
  if (fd < 0)
    return -1;
  struct stat st;
  int ok = fstat(fd, &st) == 0 && S_ISREG(st.st_mode) &&
           st.st_uid == geteuid() && (st.st_mode & 0777) == 0600 &&
           st.st_size == 32 && read(fd, key, 32) == 32;
  close(fd);
  return ok ? 0 : -1;
}

static int random_bytes(void *unused, unsigned char *buf, size_t length) {
  (void)unused;
  while (length) {
    ssize_t n = getrandom(buf, length, 0);
    if (n < 0 && errno == EINTR)
      continue;
    if (n <= 0)
      return MBEDTLS_ERR_SSL_INTERNAL_ERROR;
    buf += n;
    length -= (size_t)n;
  }
  return 0;
}

static int expired(struct link *io) {
  long now = sensor_milliseconds();
  return now < 0 || now - io->start >= 5000;
}

static size_t record_size(const uint8_t *b, size_t n) {
  if (n < 5 || b[0] < 0x14 || b[0] > 0x16 || b[1] != 3 || b[2] != 3)
    return 0;
  size_t length = 5 + ((size_t)b[3] << 8 | b[4]);
  return length <= n ? length : 0;
}

static int send_tls(void *ctx, const unsigned char *buf, size_t length) {
  struct link *io = ctx;
  size_t n = record_size(buf, length);
  if (!n || n > 248 || expired(io))
    return MBEDTLS_ERR_SSL_INTERNAL_ERROR;
  uint16_t counter = io->counter++;
  uint8_t frame[256] = {0xcc, 0xf2, counter, counter >> 8,
                        0xb0, n,    0,       (uint8_t)(0xb0 + n)};
  memcpy(frame + 8, buf, n);
  if (sensor_write_fragment(io->fd, frame, (n + 11) & ~(size_t)3) != 0)
    return MBEDTLS_ERR_SSL_INTERNAL_ERROR;
  io->sent++;
  sensor_pause(15);
  return (int)n;
}

static int receive_tls(void *ctx, unsigned char *buf, size_t wanted) {
  struct link *io = ctx;
  while (io->consumed == io->length) {
    uint8_t status[4], window[256];
    if (expired(io))
      return MBEDTLS_ERR_SSL_TIMEOUT;
    if (sensor_read_mailbox(io->fd, status, window) != 0)
      return MBEDTLS_ERR_SSL_INTERNAL_ERROR;
    /* Read at the mailbox head. Later offsets can be cached older parcels. */
    size_t start = !memcmp(window, (uint8_t[4]){0}, 4) ? 4 : 0;
    for (size_t i = start; i + 4 <= sizeof(window);) {
      const uint8_t *b = window + i;
      size_t n = (size_t)b[1] | (size_t)b[2] << 8;
      if ((b[0] != 0xa0 && b[0] != 0xb0) ||
          (uint8_t)(b[0] + b[1] + b[2]) != b[3] || n == 0 ||
          n > sizeof(window) - i - 4)
        break;
      i += 4 + n;
      if (b[0] != 0xb0 || record_size(b + 4, n) != n)
        continue;
      if (io->consumed == io->length && io->length == n &&
          memcmp(b + 4, io->input, n) == 0)
        continue;
      /* Multiple records can be queued together; pass them unchanged to TLS. */
      if (io->consumed == io->length)
        io->consumed = io->length = 0;
      if (n > sizeof(io->input) - io->length)
        return MBEDTLS_ERR_SSL_INTERNAL_ERROR;
      memcpy(io->input + io->length, b + 4, n);
      io->length += n;
      io->received++;
    }
    if (io->consumed == io->length)
      sensor_pause(10);
  }
  size_t available = io->length - io->consumed;
  if (wanted > available)
    wanted = available;
  memcpy(buf, io->input + io->consumed, wanted);
  io->consumed += wanted;
  return (int)wanted;
}

int gxfp_session(int fd, const uint8_t *hello, size_t length) {
  struct link io = {.fd = fd, .counter = 3, .start = sensor_milliseconds()};
  if (io.start < 0 || length > sizeof(io.input) || !length)
    return 1;
  memcpy(io.input, hello, length);
  io.length = length;
  uint8_t key[32];
  if (load_key(key) != 0) {
    mbedtls_platform_zeroize(key, sizeof(key));
    puts("result=invalid_local_psk_file");
    return 1;
  }
  mbedtls_ssl_config config;
  mbedtls_ssl_context tls;
  mbedtls_ssl_config_init(&config);
  mbedtls_ssl_init(&tls);
  static const int suites[] = {MBEDTLS_TLS_PSK_WITH_AES_128_CBC_SHA256, 0};
  static const uint8_t identity[] = "Client_identity";
  int ret = psa_crypto_init();
  if (!ret)
    ret = mbedtls_ssl_config_defaults(&config, MBEDTLS_SSL_IS_SERVER,
                                      MBEDTLS_SSL_TRANSPORT_STREAM,
                                      MBEDTLS_SSL_PRESET_DEFAULT);
  if (!ret)
    ret = mbedtls_ssl_conf_psk(&config, key, sizeof(key), identity,
                               sizeof(identity) - 1);
  mbedtls_platform_zeroize(key, sizeof(key));
  if (!ret) {
    mbedtls_ssl_conf_rng(&config, random_bytes, NULL);
    mbedtls_ssl_conf_min_tls_version(&config, MBEDTLS_SSL_VERSION_TLS1_2);
    mbedtls_ssl_conf_max_tls_version(&config, MBEDTLS_SSL_VERSION_TLS1_2);
    mbedtls_ssl_conf_ciphersuites(&config, suites);
    ret = mbedtls_ssl_setup(&tls, &config);
  }
  if (!ret) {
    mbedtls_ssl_set_bio(&tls, &io, send_tls, receive_tls, NULL);
    ret = mbedtls_ssl_handshake(&tls);
  }
  printf("tls_records_sent=%u\ntls_records_received=%u\n", io.sent,
         io.received);
  if (ret)
    printf("tls_error=%d\nresult=tls_handshake_failed\n", ret);
  else
    puts("result=tls_handshake_verified");
  mbedtls_ssl_free(&tls);
  mbedtls_ssl_config_free(&config);
  return ret ? 2 : 0;
}
