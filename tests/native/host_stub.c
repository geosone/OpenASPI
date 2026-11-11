/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Host services for the native layer's tests: a fake clock, malloc'ed DMA
 * memory, no PCI or port I/O. */

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "openaspi/native/host.h"

static uint64_t now_us;
int host_verbose;

void oa_host_log(int level, const char *fmt, ...)
{
	va_list ap;
	if (level > OA_LOG_WARN && !host_verbose)
		return;
	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);
}

uint64_t oa_host_time_us(void) { return now_us += 10; }
void oa_host_delay_us(uint32_t us) { now_us += us; }

void *oa_host_dma_alloc(size_t size, size_t align, int below_4g, uint64_t *bus)
{
	(void)below_4g;
	void *p = aligned_alloc(align, (size + align - 1) & ~(align - 1));
	if (p) {
		memset(p, 0, size);
		*bus = (uint64_t)(uintptr_t)p;
	}
	return p;
}
void oa_host_dma_free(void *p, size_t size) { (void)size; free(p); }
void oa_host_mb(void) { }
/* single-threaded test host: no per-adapter lock needed */
oa_host_lock *oa_host_lock_create(void) { return NULL; }
void oa_host_lock_destroy(oa_host_lock *l) { (void)l; }
void oa_host_lock_acquire(oa_host_lock *l) { (void)l; }
void oa_host_lock_release(oa_host_lock *l) { (void)l; }
uint64_t oa_host_virt_to_bus(const void *p) { return (uint64_t)(uintptr_t)p; }
volatile void *oa_host_map_mmio(uint64_t phys, size_t size) { (void)phys; (void)size; return NULL; }
uint32_t oa_host_pci_read32(uint32_t dev, unsigned off) { (void)dev; (void)off; return 0xffffffffu; }
void oa_host_pci_write32(uint32_t dev, unsigned off, uint32_t v) { (void)dev; (void)off; (void)v; }
int oa_host_has_port_io(void) { return 0; }
uint8_t oa_host_inb(uint16_t p) { (void)p; return 0xff; }
uint16_t oa_host_inw(uint16_t p) { (void)p; return 0xffff; }
uint32_t oa_host_inl(uint16_t p) { (void)p; return 0xffffffffu; }
void oa_host_outb(uint16_t p, uint8_t v) { (void)p; (void)v; }
void oa_host_outw(uint16_t p, uint16_t v) { (void)p; (void)v; }
void oa_host_outl(uint16_t p, uint32_t v) { (void)p; (void)v; }
