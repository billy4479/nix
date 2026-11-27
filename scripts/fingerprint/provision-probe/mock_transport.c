/* SPDX-License-Identifier: MIT */
/* Fake sensor transport for provisioning flow tests. No hardware, no ioctls.
 * It reconstructs the uploaded record, then answers with scripted ACK,
 * completion and hash replies.
 */
#include "../readback-probe/protocol.h"
#include "../spi/transport.h"
#include "payload.h"
#include "wrap.h"
#include <assert.h>
#include <errno.h>
#include <linux/magic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/vfs.h>
#include <unistd.h>

static enum sensor_query current;
static unsigned int windows;
static unsigned int hash_sends, hash_windows;
static uint8_t record[512];
static size_t record_length;
/* before-hash file, recovery key file, then recovery directory */
static unsigned int syncs;
static int recovery_synced;

static int scenario(const char *name) {
  const char *value = getenv("SCENARIO");
  return value && !strcmp(value, name);
}
int __wrap_fstatfs(int fd, struct statfs *fs) {
  (void)fd;
  fs->f_type = scenario("volatile_fs") ? TMPFS_MAGIC : EXT4_SUPER_MAGIC;
  return 0;
}
ssize_t __real_write(int fd, const void *buf, size_t count);
ssize_t __wrap_write(int fd, const void *buf, size_t count) {
  if (syncs == 1 && scenario("key_write_failed")) {
    errno = ENOSPC;
    return -1;
  }
  return __real_write(fd, buf, count);
}
int __real_fsync(int fd);
int __wrap_fsync(int fd) {
  syncs++;
  if ((syncs == 2 && scenario("key_sync_failed")) ||
      (syncs == 3 && scenario("directory_sync_failed"))) {
    errno = EIO;
    return -1;
  }
  int result = __real_fsync(fd);
  if (syncs == 3 && result == 0)
    recovery_synced = 1;
  return result;
}
static int status_failure(void) {
  return scenario("status") || scenario("status_changed");
}
static void frame(uint8_t *out, uint8_t command, const uint8_t *data,
                  size_t size) {
  out[0] = 0xa0;
  out[1] = size + 4;
  out[2] = 0;
  out[3] = out[0] + out[1] + out[2];
  out[4] = command;
  out[5] = size + 1;
  out[6] = 0;
  if (size)
    memcpy(out + 7, data, size);
  uint8_t checksum = 0xaa;
  for (size_t i = 4; i < 7 + size; i++)
    checksum -= out[i];
  out[7 + size] = checksum;
}
static void ack(uint8_t *out, uint8_t command) {
  uint8_t data[2] = {command, 1};
  frame(out, 0xb0, data, sizeof(data));
}
static void old_hash(uint8_t digest[32]) { memset(digest, 0xa5, 32); }
static int uploaded_wrapper(uint8_t wrapper[GXFP_WRAPPER_SIZE]) {
  if (record_length < 31 + GXFP_WRAPPER_SIZE || record[0] != 0xa0 ||
      record[4] != 0xe0)
    return -1;
  uint32_t tag1 =
      record[7] | record[8] << 8 | record[9] << 16 | (uint32_t)record[10] << 24;
  uint32_t tag2 = record[23] | record[24] << 8 | record[25] << 16 |
                  (uint32_t)record[26] << 24;
  uint32_t length = record[27] | record[28] << 8 | record[29] << 16 |
                    (uint32_t)record[30] << 24;
  if (tag1 != 0xbb010002 || tag2 != 0xbb010003 || length != GXFP_WRAPPER_SIZE)
    return -1;
  memcpy(wrapper, record + 31, GXFP_WRAPPER_SIZE);
  return 0;
}
static void hash_reply(uint8_t *out, const uint8_t digest[32]) {
  uint8_t data[41] = {0};
  data[1] = 3;
  data[2] = 0;
  data[3] = 1;
  data[4] = 0xbb;
  data[5] = 32;
  memcpy(data + 9, digest, 32);
  frame(out, 0xe4, data, sizeof(data));
}
int sensor_open(const char *node) {
  (void)node;
  return 0;
}
int sensor_configure(int fd) {
  (void)fd;
  return 0;
}
int sensor_send(int fd, enum sensor_query query, uint16_t counter,
                uint16_t timestamp) {
  (void)fd;
  (void)counter;
  (void)timestamp;
  current = query;
  windows = 0;
  if (query == QUERY_HASH) {
    hash_sends++;
    hash_windows = 0;
  }
  return 0;
}
int sensor_write_fragment(int fd, const uint8_t *fragment, size_t length) {
  (void)fd;
  if (length < 4 || length > 256)
    return -1;
  size_t chunk = length - 4;
  if (record_length + chunk <= sizeof(record)) {
    memcpy(record + record_length, fragment + 4, chunk);
    record_length += chunk;
  }
  assert(recovery_synced);
  if (scenario("interrupted_upload"))
    _exit(99);
  uint8_t psk[GXFP_PSK_SIZE], expected[GXFP_WRAPPER_SIZE],
      actual[GXFP_WRAPPER_SIZE];
  FILE *key = fopen("recovery/fingerprint-gxfp5120.psk", "rb");
  assert(key && fread(psk, 1, sizeof(psk), key) == sizeof(psk));
  assert(fgetc(key) == EOF && fclose(key) == 0);
  gxfp_wrap(psk, expected);
  assert(uploaded_wrapper(actual) == 0 &&
         !memcmp(expected, actual, sizeof(actual)));
  current = QUERY_UPLOAD;
  windows = 0;
  return 0;
}
int sensor_read_mailbox(int fd, uint8_t status[4], uint8_t response[256]) {
  (void)fd;
  memset(status, 0, 4);
  memset(response, 0, 256);
  unsigned int step = windows++;
  if (current == QUERY_VERSION) {
    if (step == 0)
      ack(response, 0xa8);
    else if (step == 1) {
      static const char name[] = "GF_ITE_EC_20066";
      frame(response, 0xa8, (const uint8_t *)name, sizeof(name));
    }
    return 0;
  }
  if (current == QUERY_UPLOAD) {
    if (step == 0 && !scenario("no_ack"))
      ack(response, 0xe0);
    else if (step == 1 && !scenario("no_ack")) {
      uint8_t data[1] = {status_failure() ? 7 : 0};
      if (!scenario("no_completion"))
        frame(response, 0xe0, data, sizeof(data));
    }
    return 0;
  }
  if (current == QUERY_HASH) {
    uint8_t digest[32], wrapper[GXFP_WRAPPER_SIZE];
    if (hash_sends == 1) {
      if (scenario("existing_hash_refused")) {
        uint8_t data[1] = {7};
        frame(response, 0xe4, data, sizeof(data));
        return 0;
      }
      old_hash(digest);
      hash_reply(response, digest);
      return 0;
    }
    if (uploaded_wrapper(wrapper) == 0)
      gxfp_wrapper_hash(wrapper, digest);
    else
      old_hash(digest);
    if (scenario("hash_mismatch"))
      old_hash(digest);
    if (scenario("hash_stale") && hash_windows < 3)
      old_hash(digest);
    if (scenario("no_completion")) {
      /* The write may have landed even without a clean completion. */
      if (uploaded_wrapper(wrapper) == 0)
        gxfp_wrapper_hash(wrapper, digest);
    }
    if (status_failure()) {
      if (scenario("status_changed"))
        memset(digest, 0x5a, 32);
      else
        old_hash(digest);
    } else if (scenario("no_ack")) {
      old_hash(digest);
    }
    hash_windows++;
    hash_reply(response, digest);
    return 0;
  }
  return 0;
}
long sensor_milliseconds(void) { return (long)windows; }
void sensor_pause(long milliseconds) { (void)milliseconds; }
