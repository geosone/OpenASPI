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

#include "openaspi/types.h"

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
oa_u64 oa_host_time_us(void);
void oa_host_delay_us(oa_u32 us);

/* Memory a bus master can reach: zeroed, physically contiguous, aligned to
 * `align` (a power of two, at least 16) and, with `below_4g`, wholly below
 * 4 GiB for controllers without 64-bit addressing. Returns the CPU pointer
 * and stores the bus address; NULL when out of memory. */
void *oa_host_dma_alloc(size_t size, size_t align, int below_4g, oa_u64 *bus_addr);
void oa_host_dma_free(void *p, size_t size);

/* Bus address of a CPU buffer the caller handed in (for zero-copy
 * transfers); 0 when the host cannot tell, then the transport bounces
 * through its own DMA memory. */
oa_u64 oa_host_virt_to_bus(const void *p);

/* Map device registers (uncached). NULL on failure. */
volatile void *oa_host_map_mmio(oa_u64 phys, size_t size);

/* Full barrier between DMA memory and device registers: what the CPU wrote
 * to descriptors or buffers is visible to the device before a following
 * register write (doorbell), and a register read (completion) comes before
 * the CPU reads what the device wrote. A compiler barrier on x86, DSB on
 * ARM. */
void oa_host_mb(void);

/* PCI configuration space; `dev` packs segment, bus, device, function as
 * OA_PCI_ADDR(). Reads of absent functions return all ones. */
#define OA_PCI_ADDR(seg, bus, dev, fn) \
	(((oa_u32)(seg) << 16) | ((oa_u32)(bus) << 8) | ((oa_u32)(dev) << 3) | (oa_u32)(fn))
oa_u32 oa_host_pci_read32(oa_u32 dev, unsigned off);
void oa_host_pci_write32(oa_u32 dev, unsigned off, oa_u32 val);

/* Port I/O. Hosts without it (AArch64) return all ones and drop writes;
 * transports that need it (legacy IDE) check oa_host_has_port_io(). */
int oa_host_has_port_io(void);
oa_u8 oa_host_inb(oa_u16 port);
oa_u16 oa_host_inw(oa_u16 port);
oa_u32 oa_host_inl(oa_u16 port);
void oa_host_outb(oa_u16 port, oa_u8 v);
void oa_host_outw(oa_u16 port, oa_u16 v);
void oa_host_outl(oa_u16 port, oa_u32 v);

/* Interrupt-driven completion (optional). A transport that knows its interrupt
 * source registers a handler and blocks on an event the handler signals,
 * instead of polling a status register. All of this is best-effort: when the
 * host has no interrupt support, oa_host_event_create returns NULL and the
 * request functions return < 0, and the transport falls back to polling. The
 * handler runs in interrupt context -- it may only touch oa_host_event_signal
 * and port/MMIO register I/O, nothing that blocks or allocates.
 *
 * An event is a binary/counting completion: signal hands one unit to a waiter
 * (or banks it), wait takes one or times out, reset drops any banked units
 * before arming a fresh request. */
typedef struct oa_host_event oa_host_event;
oa_host_event *oa_host_event_create(void);
void oa_host_event_destroy(oa_host_event *ev);
void oa_host_event_signal(oa_host_event *ev);              /* interrupt context */
void oa_host_event_reset(oa_host_event *ev);               /* drop banked units */
int oa_host_event_wait(oa_host_event *ev, oa_u32 timeout_us); /* 1 signalled, 0 timeout */

/* Per-adapter serialization for SMP. On a host with real threads (GDOS under
 * SMP) oa_host_lock_create returns a blocking mutex the ASPI core takes around
 * each command (oa_execute), so two CPUs can never drive one host adapter's
 * registers/rings at once; acquire may block (the holder can be waiting on a
 * device IRQ), which is fine -- it is a cooperative/SMP mutex, not a spinlock.
 * On a single-threaded host it returns NULL and acquire/release are no-ops, so
 * the DOS ABI and the native tests are unaffected. */
typedef struct oa_host_lock oa_host_lock;
oa_host_lock *oa_host_lock_create(void);
void oa_host_lock_destroy(oa_host_lock *lock);
void oa_host_lock_acquire(oa_host_lock *lock); /* NULL: no-op */
void oa_host_lock_release(oa_host_lock *lock); /* NULL: no-op */

/* Bind fn(arg) to a legacy ISA IRQ line (e.g. 14/15 for legacy IDE). Returns
 * 0, or < 0 when the host cannot route it (no port I/O / not x86). */
int oa_host_irq_request(oa_u32 isa_irq, void (*fn)(void *), void *arg);
/* Bind fn(arg) to a PCI function's MSI (dev as OA_PCI_ADDR). Returns a handle
 * >= 0, or < 0 when MSI is unavailable. */
int oa_host_pci_msi(oa_u32 dev, void (*fn)(void *), void *arg);
/* Same for MSI-X, binding fn(arg) to table entry 0. Returns a handle >= 0, or
 * < 0 when MSI-X is unavailable. */
int oa_host_pci_msix(oa_u32 dev, void (*fn)(void *), void *arg);

#endif
