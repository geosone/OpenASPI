/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Host services for the native (32/64-bit C) ASPI layer.
 *
 * The native layer runs inside an operating system kernel without a C
 * library: GDOS polled, later the GonWare server executive with interrupts.
 * The embedding system implements these functions; the layer calls nothing
 * else. Physical addresses are 64 bits on every architecture.
 */

#ifndef OPENASPI_NATIVE_HOST_H
#define OPENASPI_NATIVE_HOST_H

#include <stddef.h>
#include <stdint.h>

#if defined(__GNUC__) || defined(__clang__)
#define OA_PRINTF(f, a) __attribute__((format(printf, f, a)))
#else
#define OA_PRINTF(f, a)
#endif

/* Log levels for oa_host_log(). */
#define OA_LOG_ERROR 0
#define OA_LOG_WARN  1
#define OA_LOG_INFO  2
#define OA_LOG_DEBUG 3

void oa_host_log(int level, const char *fmt, ...) OA_PRINTF(2, 3);

/* Monotonic time in microseconds, and a busy wait. */
uint64_t oa_host_time_us(void);
void oa_host_delay_us(uint32_t us);

/* Memory a bus master can reach: zeroed, physically contiguous, aligned to
 * `align` (a power of two, at least 16) and, with `below_4g`, wholly below
 * 4 GiB for controllers without 64-bit addressing. Returns the CPU pointer
 * and stores the bus address; NULL when out of memory. */
void *oa_host_dma_alloc(size_t size, size_t align, int below_4g, uint64_t *bus_addr);
void oa_host_dma_free(void *p, size_t size);

/* Bus address of a CPU buffer the caller handed in (for zero-copy
 * transfers); 0 when the host cannot tell, then the transport bounces
 * through its own DMA memory. */
uint64_t oa_host_virt_to_bus(const void *p);

/* Map device registers (uncached). NULL on failure. */
volatile void *oa_host_map_mmio(uint64_t phys, size_t size);

/* PCI configuration space; `dev` packs segment, bus, device, function as
 * OA_PCI_ADDR(). Reads of absent functions return all ones. */
#define OA_PCI_ADDR(seg, bus, dev, fn) \
	(((uint32_t)(seg) << 16) | ((uint32_t)(bus) << 8) | ((uint32_t)(dev) << 3) | (uint32_t)(fn))
uint32_t oa_host_pci_read32(uint32_t dev, unsigned off);
void oa_host_pci_write32(uint32_t dev, unsigned off, uint32_t val);

/* Port I/O. Hosts without it (AArch64) return all ones and drop writes;
 * transports that need it (legacy IDE) check oa_host_has_port_io(). */
int oa_host_has_port_io(void);
uint8_t oa_host_inb(uint16_t port);
uint16_t oa_host_inw(uint16_t port);
uint32_t oa_host_inl(uint16_t port);
void oa_host_outb(uint16_t port, uint8_t v);
void oa_host_outw(uint16_t port, uint16_t v);
void oa_host_outl(uint16_t port, uint32_t v);

#endif
