/* SPDX-License-Identifier: MIT */
#ifndef GXFP_WRAP_H
#define GXFP_WRAP_H
#include <stddef.h>
#include <stdint.h>

#define GXFP_PSK_SIZE 32
#define GXFP_WRAPPER_SIZE 102

/* Build the authenticated, encrypted BB010003 wrapper for one 32-byte PSK.
 * Format and constants come from gfspi.dll 1.1.17.140, mode 0. The same
 * runtime seed and construction appear in the public gxfp5130 Linux payload
 * code. The wrapper is what the sensor stores; the raw PSK stays on the host.
 */
void gxfp_wrap(const uint8_t psk[GXFP_PSK_SIZE],
               uint8_t wrapper[GXFP_WRAPPER_SIZE]);
void gxfp_wrapper_hash(const uint8_t wrapper[GXFP_WRAPPER_SIZE],
                       uint8_t digest[32]);
/* Return 0 only if a public synthetic vector matches. */
int gxfp_wrap_self_test(void);
#endif
