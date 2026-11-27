/* SPDX-License-Identifier: MIT */
#ifndef GXFP_PROVISION_PAYLOAD_H
#define GXFP_PROVISION_PAYLOAD_H
#include "wrap.h"
#include <stddef.h>
#include <stdint.h>

#define GXFP_PAYLOAD_MAX 160
#define GXFP_RECORD_MAX 256
#define GXFP_FRAGMENT_MAX 256

/* BB010002 with an empty host-cache field and an 8-byte seed, followed by
 * BB010003 carrying the 102-byte wrapper. This is the native serializer's
 * zero-length host-cache case, not a proven firmware provisioning profile.
 */
size_t gxfp_payload(uint8_t out[GXFP_PAYLOAD_MAX],
                    const uint8_t wrapper[GXFP_WRAPPER_SIZE],
                    const uint8_t seed8[8]);
/* E0 production command inside a padded A0 message-pack envelope. */
size_t gxfp_record(uint8_t out[GXFP_RECORD_MAX], const uint8_t *payload,
                   size_t size);
/* One ITE fragment: cc f2, little-endian counter, up to 252 record bytes. */
size_t gxfp_fragment(uint8_t out[GXFP_FRAGMENT_MAX], const uint8_t *chunk,
                     size_t size, uint16_t counter);
#endif
