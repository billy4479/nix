/* SPDX-License-Identifier: MIT */
#define _GNU_SOURCE
#include "../readback-probe/protocol.h"
#include "../spi/transport.h"
#include "payload.h"
#include "wrap.h"
#include <errno.h>
#include <fcntl.h>
#include <linux/magic.h>
#include <mbedtls/platform_util.h>
#include <stdio.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/random.h>
#include <sys/stat.h>
#include <sys/vfs.h>
#include <unistd.h>

#ifndef RECOVERY_DIR
#define RECOVERY_DIR "/var/lib"
#endif
#define RECOVERY_KEY "fingerprint-gxfp5120.psk"

static int open_recovery(void) {
  int dir = open(RECOVERY_DIR, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (dir < 0) {
    perror("open recovery directory");
    return -1;
  }
  struct stat st;
  struct statfs fs;
  if (fstat(dir, &st) || fstatfs(dir, &fs) || st.st_uid != geteuid() ||
      (st.st_mode & 022) || fs.f_type != EXT4_SUPER_MAGIC) {
    fprintf(stderr, "Requires a trusted recovery directory on portatilo's ext4 "
                    "filesystem\n");
    close(dir);
    return -1;
  }
  if (fstatat(dir, RECOVERY_KEY, &st, AT_SYMLINK_NOFOLLOW) == 0 ||
      errno != ENOENT) {
    fprintf(
        stderr,
        "Recovery key path already exists or cannot be checked; refusing\n");
    close(dir);
    return -1;
  }
  return dir;
}
static int save(int dir, const char *name, const uint8_t *data, size_t size) {
  int fd = openat(dir, name,
                  O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
  if (fd < 0) {
    perror("create private data file");
    return -1;
  }
  size_t offset = 0;
  while (offset < size) {
    ssize_t n = write(fd, data + offset, size - offset);
    if (n < 0 && errno == EINTR)
      continue;
    if (n <= 0) {
      close(fd);
      return -1;
    }
    offset += n;
  }
  if (fsync(fd) != 0) {
    perror("persist private data file");
    close(fd);
    return -1;
  }
  if (close(fd) != 0) {
    perror("close private data file");
    return -1;
  }
  return 0;
}
/* Read one mailbox window into a fresh parser. The next read has a new
 * command phase, so an incomplete trailing frame must not be carried over.
 */
static int receive(int fd, struct readback_parser *parser) {
  uint8_t status[4], data[256];
  if (sensor_read_mailbox(fd, status, data) != 0)
    return 1;
  parser->used = 0;
  if (readback_feed(parser, data, sizeof(data)) != 0)
    return 1;
  return 0;
}
static int read_version(int fd, uint8_t name[24], size_t *length) {
  struct readback_parser parser = {.query = QUERY_VERSION};
  long start = sensor_milliseconds();
  if (start < 0 || sensor_send(fd, QUERY_VERSION, 1, 0) != 0)
    return 1;
  sensor_pause(5);
  for (unsigned int window = 0; window < 128; window++) {
    long now = sensor_milliseconds();
    if (now < 0)
      return 1;
    if (now - start >= 1500)
      break;
    if (receive(fd, &parser) != 0)
      return 1;
    if (parser.done)
      break;
    sensor_pause(10);
  }
  printf("version_frames=%u\nversion_rejected=%u\nversion_foreign=%u\n",
         parser.frames, parser.rejected, parser.foreign);
  if (parser.malformed)
    return 1;
  if (!parser.done || parser.length > 24)
    return 2;
  memcpy(name, parser.data, parser.length);
  *length = parser.length;
  return 0;
}
/* Return 3 only when there was no matching ACK or E4 reply at all. */
static int read_hash(int fd, uint16_t counter, uint8_t digest[32]) {
  long start = sensor_milliseconds();
  if (start < 0 || sensor_send(fd, QUERY_HASH, counter, 0) != 0)
    return 1;
  struct readback_parser parser = {.query = QUERY_HASH, .require_ack = true};
  sensor_pause(5);
  for (unsigned int window = 0; window < 128; window++) {
    long now = sensor_milliseconds();
    if (now < 0)
      return 1;
    if (now - start >= 1500)
      break;
    if (receive(fd, &parser) != 0)
      return 1;
    if (parser.done)
      break;
    sensor_pause(10);
  }
  printf("hash_frames=%u\nhash_rejected=%u\nhash_foreign=%u\nhash_ack=%s\n",
         parser.frames, parser.rejected, parser.foreign,
         parser.ack ? "yes" : "no");
  if (parser.malformed)
    return 1;
  if (!parser.ack && !parser.foreign)
    return 3;
  if (parser.status)
    printf("hash_status=%u\n", parser.status);
  if (!parser.done || parser.status || parser.length != 32)
    return 2;
  memcpy(digest, parser.data, 32);
  return 0;
}
/* Keep polling after a successful upload until the new digest appears. A
 * delayed or cached old hash must not make a failed write look successful.
 */
static int verify_hash(int fd, uint16_t counter, const uint8_t expected[32],
                       uint8_t observed[32], bool *saw) {
  struct readback_parser parser = {.query = QUERY_HASH, .require_ack = true};
  long start = sensor_milliseconds();
  *saw = false;
  if (start < 0 || sensor_send(fd, QUERY_HASH, counter, 0) != 0)
    return 1;
  sensor_pause(5);
  for (unsigned int window = 0; window < 128; window++) {
    long now = sensor_milliseconds();
    if (now < 0)
      return 1;
    if (now - start >= 1500)
      break;
    if (receive(fd, &parser) != 0 || parser.malformed)
      return 1;
    if (parser.done) {
      parser.done = false;
      if (parser.status) {
        printf("verify_status=%u\n", parser.status);
        return 2;
      }
      if (parser.length == 32) {
        memcpy(observed, parser.data, 32);
        *saw = true;
        if (!memcmp(observed, expected, 32))
          return 0;
      }
    }
    sensor_pause(10);
  }
  return 2;
}
/* Send the whole padded record once, then wait for its ACK and completion.
 * There is deliberately no retry: a repeated production command after an
 * uncertain write is not assumed to be idempotent.
 */
static int upload(int fd, const uint8_t *record, size_t length,
                  uint16_t *next_counter) {
  unsigned int fragments = 0;
  for (size_t offset = 0; offset < length; offset += 252) {
    size_t chunk = length - offset < 252 ? length - offset : 252;
    uint8_t frame[GXFP_FRAGMENT_MAX];
    size_t size =
        gxfp_fragment(frame, record + offset, chunk, (*next_counter)++);
    if (!size)
      return 1;
    if (sensor_write_fragment(fd, frame, size) != 0) {
      printf("write_fragments_partial=%u\n", fragments + 1);
      return 1;
    }
    fragments++;
    sensor_pause(15);
  }
  printf("write_fragments=%u\n", fragments);

  struct readback_parser parser = {.query = QUERY_UPLOAD};
  long start = sensor_milliseconds();
  if (start < 0)
    return 1;
  for (unsigned int window = 0; window < 128; window++) {
    long now = sensor_milliseconds();
    if (now < 0)
      return 1;
    if (now - start >= 1000)
      break;
    if (receive(fd, &parser) != 0)
      return 1;
    if (parser.done)
      break;
    sensor_pause(10);
  }
  printf("write_ack=%s\nwrite_completion=%s\n", parser.ack ? "yes" : "no",
         parser.done ? "yes" : "no");
  if (parser.done)
    printf("write_status=%u\n", parser.status);
  if (parser.malformed)
    return 1;
  if (!parser.done || parser.status)
    return 2;
  return 0;
}
static int run(int fd, int recovery) {
  if (sensor_configure(fd) != 0)
    return 1;
  puts("profile=ite-20066-key-provision-v4");
  uint8_t found[24];
  size_t found_length = 0;
  int result = read_version(fd, found, &found_length);
  if (result != 0) {
    puts("result=version_unavailable");
    return result;
  }
  static const char expected[] = "GF_ITE_EC_20066";
  if (found_length != sizeof(expected) ||
      memcmp(found, expected, sizeof(expected))) {
    puts("result=unexpected_firmware_stop");
    return 2;
  }
  puts("firmware=GF_ITE_EC_20066");

  uint8_t before[32];
  uint16_t next_counter = 2;
  /* Give the MCU time to finish its version response before the next TX.
   * An unanswered read is safe to try once more. Never retry the upload. */
  sensor_pause(100);
  result = read_hash(fd, next_counter++, before);
  if (result == 3) {
    puts("hash_retry=one_read_only_retry_no_response");
    sensor_pause(100);
    result = read_hash(fd, next_counter++, before);
  }
  if (result != 0) {
    puts("result=existing_hash_unavailable_stop");
    return result == 3 ? 2 : result;
  }
  if (save(AT_FDCWD, "before-hash.bin", before, sizeof(before)) != 0)
    return 1;
  puts("existing_hash=collected");

  if (gxfp_wrap_self_test() != 0) {
    puts("result=wrapping_self_test_failed");
    return 1;
  }
  uint8_t psk[GXFP_PSK_SIZE], seed8[8], wrapper[GXFP_WRAPPER_SIZE];
  uint8_t digest[32], observed[32];
  if (getrandom(psk, sizeof(psk), 0) != (ssize_t)sizeof(psk) ||
      getrandom(seed8, sizeof(seed8), 0) != (ssize_t)sizeof(seed8)) {
    perror("getrandom");
    mbedtls_platform_zeroize(psk, sizeof(psk));
    return 1;
  }
  gxfp_wrap(psk, wrapper);
  gxfp_wrapper_hash(wrapper, digest);
  uint8_t payload[GXFP_PAYLOAD_MAX], record[GXFP_RECORD_MAX];
  size_t payload_size = gxfp_payload(payload, wrapper, seed8);
  size_t record_size = gxfp_record(record, payload, payload_size);
  if (!payload_size || !record_size) {
    mbedtls_platform_zeroize(psk, sizeof(psk));
    puts("result=payload_build_failed");
    return 1;
  }
  int saved = save(recovery, RECOVERY_KEY, psk, sizeof(psk));
  mbedtls_platform_zeroize(psk, sizeof(psk));
  if (saved != 0 || fsync(recovery) != 0) {
    if (saved == 0)
      perror("persist recovery directory entry");
    puts("result=recovery_storage_failed_no_upload");
    return 1;
  }
  puts("new_key=durably_saved");
  printf("payload_bytes=%zu\n", payload_size);

  /* Each fragment and the verification query continue the ITE sequence. */
  int written = upload(fd, record, record_size, &next_counter);
  if (written == 1) {
    puts("write_transport_error");
  }
  /* Even a missing ACK/completion may leave a stored key. Check the digest
   * with the same fixed query; do not resend the upload.
   */
  sensor_pause(100);
  bool saw = false;
  int verified = verify_hash(fd, next_counter, digest, observed, &saw);
  if (verified == 0) {
    puts("key_hash=verified");
  } else if (saw) {
    puts("key_hash=mismatch");
    if (!memcmp(observed, before, sizeof(before)))
      puts("observed_hash=existing_unchanged");
    else
      puts("observed_hash=changed_not_new");
  } else {
    puts("key_hash=unavailable");
  }

  if (written == 0 && verified == 0) {
    puts("result=key_replaced_verified");
    return 0;
  }
  if (verified == 0) {
    puts("result=key_replaced_completion_unconfirmed");
    return 2;
  }
  if (written == 0) {
    puts("result=key_replacement_unverified");
    return 2;
  }
  if (saw) {
    if (!memcmp(observed, before, sizeof(before)))
      puts("result=key_write_failed_existing_hash_unchanged");
    else
      puts("result=key_write_failed_hash_changed_not_new");
  } else {
    puts("result=key_write_failed_state_unknown");
  }
  return 2;
}
int main(int argc, char **argv) {
  if (argc == 2 && !strcmp(argv[1], "--help")) {
    puts("Use the reviewed run.sh as sudo. Replaces the fingerprint sensor's "
         "32-byte PSK once.\n"
         "Generates and saves a new key in " RECOVERY_DIR "/" RECOVERY_KEY
         " before writing. No upload retries, "
         "reset,\nconfiguration, TLS, scan, enrollment, GPIO requests, "
         "arbitrary commands or fallback.");
    return 0;
  }
  if (argc != 3 || strcmp(argv[1], "--replace-psk")) {
    fprintf(stderr, "Use the reviewed run.sh as sudo\n");
    return 1;
  }
  struct stat directory;
  if (stat(".", &directory) || directory.st_uid != geteuid() ||
      (directory.st_mode & 077)) {
    fprintf(stderr,
            "Requires a private directory owned by the executing user\n");
    return 1;
  }
  umask(077);
  if (prctl(PR_SET_DUMPABLE, 0UL, 0UL, 0UL, 0UL) != 0) {
    perror("disable process dumps");
    return 1;
  }
  int recovery = open_recovery();
  if (recovery < 0)
    return 1;
  setvbuf(stdout, NULL, _IOLBF, 0);
  int fd = sensor_open(argv[2]);
  int result = fd < 0 ? 1 : run(fd, recovery);
  if (fd >= 0)
    close(fd);
  close(recovery);
  return result;
}
