// SPDX-License-Identifier: GPL-2.0-only
/*
 * One-shot inspection of the already-reviewed fingerprint _CRS method.
 * No driver registration, GPIO requests, SPI transfers or memory probing.
 * _CRS reads firmware GNVS and updates its resource buffer; _INI is not called.
 */
#include <linux/acpi.h>
#include <linux/init.h>
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/slab.h>
#include <linux/string.h>

#define TARGET_PATH "\\_SB.PC00.SPI1.FPNT"
#define TARGET_HID "GXFP5120"

static char report[2048];
static size_t report_used;
static bool report_overflow;

struct resource_counts {
  unsigned int spi;
  unsigned int gpio_int;
  unsigned int gpio_io;
  unsigned int total;
};

static void append(const char *format, ...) {
  va_list args;
  int required;
  size_t remaining = sizeof(report) - report_used;

  if (report_overflow)
    return;
  va_start(args, format);
  required = vsnprintf(report + report_used, remaining, format, args);
  va_end(args);
  if (required < 0 || (size_t)required >= remaining) {
    report_overflow = true;
    return;
  }
  report_used += required;
}

static int get_report(char *buffer, const struct kernel_param *parameter) {
  return scnprintf(buffer, PAGE_SIZE, "%s", report);
}

static int reject_report(const char *value,
                         const struct kernel_param *parameter) {
  return -EPERM;
}

/* Reject load-time input too: the module parser requires a non-NULL setter. */
static const struct kernel_param_ops report_ops = {
    .get = get_report,
    .set = reject_report,
};
module_param_cb(report, &report_ops, NULL, 0444);
MODULE_PARM_DESC(report, "Stored result of the fixed GXFP5120 _CRS query");

static acpi_status inspect_resource(struct acpi_resource *resource,
                                    void *context) {
  struct resource_counts *counts = context;
  struct acpi_resource_gpio *gpio;
  struct acpi_resource_spi_serialbus *spi;

  if (++counts->total > 16)
    return AE_LIMIT;

  switch (resource->type) {
  case ACPI_RESOURCE_TYPE_SERIAL_BUS:
    if (resource->data.common_serial_bus.type != ACPI_RESOURCE_SERIAL_TYPE_SPI)
      return AE_TYPE;
    spi = &resource->data.spi_serial_bus;
    counts->spi++;
    append("spi source=%s select=%u speed_hz=%u bits=%u polarity=%u phase=%u "
           "cs_polarity=%u wire_mode=%u\n",
           spi->resource_source.string_ptr ?: "", spi->device_selection,
           spi->connection_speed, spi->data_bit_length, spi->clock_polarity,
           spi->clock_phase, spi->device_polarity, spi->wire_mode);
    break;
  case ACPI_RESOURCE_TYPE_GPIO:
    gpio = &resource->data.gpio;
    if (gpio->connection_type == ACPI_RESOURCE_GPIO_TYPE_INT) {
      counts->gpio_int++;
      append("gpio-int");
    } else if (gpio->connection_type == ACPI_RESOURCE_GPIO_TYPE_IO) {
      counts->gpio_io++;
      append("gpio-io");
    } else {
      return AE_TYPE;
    }
    if (gpio->pin_table_length != 1 || !gpio->pin_table)
      return AE_BAD_DATA;
    append(" source=%s", gpio->resource_source.string_ptr ?: "");
    append(" pin=%u", gpio->pin_table[0]);
    append(" triggering=%u polarity=%u pull=%u restriction=%u sharing=%u "
           "wake=%u\n",
           gpio->triggering, gpio->polarity, gpio->pin_config,
           gpio->io_restriction, gpio->shareable, gpio->wake_capable);
    break;
  case ACPI_RESOURCE_TYPE_END_TAG:
    break;
  default:
    return AE_TYPE;
  }
  return report_overflow ? AE_LIMIT : AE_OK;
}

static int __init gxfp_resources_init(void) {
  struct acpi_device_info *info;
  struct resource_counts counts = {};
  acpi_handle handle;
  acpi_status status;

  status = acpi_get_handle(NULL, TARGET_PATH, &handle);
  if (ACPI_FAILURE(status)) {
    pr_err("gxfp_acpi_resources: fixed device not found: %s\n",
           acpi_format_exception(status));
    return -ENODEV;
  }
  status = acpi_get_object_info(handle, &info);
  if (ACPI_FAILURE(status))
    return -ENODEV;
  if (!(info->valid & ACPI_VALID_HID) ||
      strcmp(info->hardware_id.string, TARGET_HID)) {
    kfree(info);
    pr_err("gxfp_acpi_resources: unexpected hardware ID; refusing query\n");
    return -ENODEV;
  }
  kfree(info);

  append("device=%s\npath=%s\nquery=_CRS\n", TARGET_HID, TARGET_PATH);
  status =
      acpi_walk_resources(handle, METHOD_NAME__CRS, inspect_resource, &counts);
  if (ACPI_FAILURE(status)) {
    pr_err("gxfp_acpi_resources: resource query failed: %s\n",
           acpi_format_exception(status));
    return -EINVAL;
  }
  if (counts.spi != 1 || counts.gpio_int != 1 || counts.gpio_io != 1) {
    pr_err("gxfp_acpi_resources: unexpected resource layout\n");
    return -EINVAL;
  }
  append("complete=1\n");
  if (report_overflow)
    return -EOVERFLOW;
  pr_info("gxfp_acpi_resources: query complete; read parameters/report, then "
          "unload\n");
  return 0;
}

static void __exit gxfp_resources_exit(void) {}

module_init(gxfp_resources_init);
module_exit(gxfp_resources_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Fixed-path, one-shot GXFP5120 ACPI resource inspection");
