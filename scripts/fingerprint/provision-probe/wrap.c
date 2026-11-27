/* SPDX-License-Identifier: MIT */
#include "wrap.h"
#include <mbedtls/gcm.h>
#include <mbedtls/md.h>
#include <mbedtls/platform_util.h>
#include <mbedtls/sha256.h>
#include <string.h>

static const uint8_t header[6] = {0x02, 0xff, 0x20, 0x00, 0x00, 0x00};
static const uint8_t runtime_seed[32] = {
    0x5c, 0xba, 0x6e, 0x25, 0x81, 0x95, 0x18, 0xde, 0x2d, 0x53, 0xe9,
    0x6d, 0xc0, 0x34, 0x7a, 0xb0, 0xd4, 0x27, 0xd4, 0x08, 0x4b, 0xda,
    0x4f, 0xae, 0x1b, 0xff, 0x2b, 0x09, 0x11, 0x2a, 0x57, 0xe5,
};
/* Label bytes from the original DLL and the public Linux payload code. */
static const uint8_t label[29] = {
    'k', 'g', 'o', 'o', 'd', 'w',  'i',  'x',  'g',  0,
    'k', 'a', 'e', 'l', 'r', 'g',  'n',  'o',  'e',  'r',
    'l', 'i', 't', 'h', 'm', 0x00, 0x00, 0x01, 0x80,
};
static const uint8_t aad[16] = {
    0x52, 0x2d, 0xc1, 0xf0, 0x99, 0x56, 0x7d, 0x07,
    0xf4, 0x7f, 0x37, 0xa3, 0x2a, 0x84, 0x42, 0x7d,
};

static int hmac(const uint8_t key[32], const uint8_t *data, size_t size,
                uint8_t out[32]) {
  const mbedtls_md_info_t *info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
  return info ? mbedtls_md_hmac(info, key, 32, data, size, out) : -1;
}
static void be32(uint8_t out[4], uint32_t value) {
  out[0] = value >> 24;
  out[1] = value >> 16;
  out[2] = value >> 8;
  out[3] = value;
}
static void derive(uint8_t aes_key[32], uint8_t mac_key[32]) {
  uint8_t message[4 + sizeof(label)], round1[32], round2[32];
  memcpy(message + 4, label, sizeof(label));
  be32(message, 1);
  hmac(runtime_seed, message, sizeof(message), round1);
  be32(message, 2);
  hmac(runtime_seed, message, sizeof(message), round2);
  memcpy(aes_key, round1, 32);
  memcpy(mac_key, round1 + 16, 16);
  memcpy(mac_key + 16, round2, 16);
}
static int sha256(const uint8_t *data, size_t size, uint8_t out[32]) {
  return mbedtls_sha256(data, size, out, 0);
}
void gxfp_wrap(const uint8_t psk[GXFP_PSK_SIZE],
               uint8_t wrapper[GXFP_WRAPPER_SIZE]) {
  uint8_t aes_key[32], mac_key[32], iv_input[6 + 8 + 64], iv[32];
  uint8_t encrypted[48], mac_input[6 + 48];
  static const uint8_t three[4] = {3, 0, 0, 0};
  derive(aes_key, mac_key);
  memcpy(iv_input, header, sizeof(header));
  memcpy(iv_input + sizeof(header), psk, 8);
  for (unsigned int i = 0; i < 16; i++)
    memcpy(iv_input + sizeof(header) + 8 + 4 * i, three, 4);
  sha256(iv_input, sizeof(iv_input), iv);

  mbedtls_gcm_context gcm;
  mbedtls_gcm_init(&gcm);
  if (mbedtls_gcm_setkey(&gcm, MBEDTLS_CIPHER_ID_AES, aes_key,
                         sizeof(aes_key) * 8) != 0 ||
      mbedtls_gcm_crypt_and_tag(&gcm, MBEDTLS_GCM_ENCRYPT, GXFP_PSK_SIZE, iv,
                                16, aad, sizeof(aad), psk, encrypted, 16,
                                encrypted + GXFP_PSK_SIZE) != 0) {
    /* Callers must run the self-test before using this path. */
    memset(wrapper, 0, GXFP_WRAPPER_SIZE);
    mbedtls_gcm_free(&gcm);
    return;
  }
  mbedtls_gcm_free(&gcm);
  memcpy(mac_input, header, sizeof(header));
  memcpy(mac_input + sizeof(header), encrypted, sizeof(encrypted));
  hmac(mac_key, mac_input, sizeof(mac_input), wrapper);
  memcpy(wrapper + 32, header, sizeof(header));
  memcpy(wrapper + 38, iv, 16);
  memcpy(wrapper + 54, encrypted, sizeof(encrypted));
}
void gxfp_wrapper_hash(const uint8_t wrapper[GXFP_WRAPPER_SIZE],
                       uint8_t digest[32]) {
  sha256(wrapper, GXFP_WRAPPER_SIZE, digest);
}
int gxfp_wrap_self_test(void) {
  static const uint8_t key[GXFP_PSK_SIZE] = {
      0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a,
      0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15,
      0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f,
  };
  static const uint8_t expected[GXFP_WRAPPER_SIZE] = {
      0x45, 0xa3, 0x73, 0x2a, 0xcf, 0x29, 0x90, 0xf4, 0xce, 0xb3, 0x0e, 0x89,
      0x96, 0xe4, 0xad, 0xd1, 0x2e, 0x88, 0x71, 0x60, 0xd6, 0xdc, 0xaa, 0x99,
      0xc8, 0xbc, 0xd8, 0x33, 0x8c, 0x77, 0x43, 0xf2, 0x02, 0xff, 0x20, 0x00,
      0x00, 0x00, 0xe7, 0xbc, 0x09, 0x96, 0x2a, 0xed, 0xfb, 0x47, 0x0f, 0xac,
      0x38, 0x87, 0xde, 0x32, 0x46, 0x5c, 0x5a, 0x71, 0xc8, 0x8f, 0xe0, 0x1d,
      0xd7, 0x76, 0xcf, 0xa5, 0x19, 0xe7, 0x0c, 0x63, 0xf8, 0x24, 0x01, 0xf8,
      0x24, 0x73, 0x24, 0xfd, 0xe9, 0xc6, 0x56, 0x23, 0x21, 0xd4, 0xd8, 0x2b,
      0x0d, 0xd5, 0x52, 0xc0, 0xbf, 0x1f, 0x74, 0x71, 0x60, 0x85, 0xb8, 0x52,
      0x65, 0x8b, 0xfe, 0x77, 0x29, 0x64,
  };
  uint8_t wrapper[GXFP_WRAPPER_SIZE];
  gxfp_wrap(key, wrapper);
  return memcmp(wrapper, expected, sizeof(wrapper)) ? -1 : 0;
}
