/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright (c) Arduino s.r.l. and/or its affiliated companies */
/* Copyright (c) 2026 Qualcomm Innovation Center, Inc. All rights reserved. */
/*
 * Charlieplexed 8 x 13 LED matrix scan with deadline-scheduled frames.
 *
 * The pin-pair tables and the one-LED-per-10-us scan follow Arduino's
 * ArduinoCore-zephyr loader/matrix.inc (Apache-2.0, Arduino s.r.l.). Unlike
 * that backend, frames are queued with a deadline and swapped in only at a
 * full-scan boundary, so each scan shows one whole image.
 */
#include <errno.h>
#include <string.h>

#include <soc.h>
#include <zephyr/device.h>
#include <zephyr/drivers/counter.h>
#include <zephyr/kernel.h>
#include <zephyr/sys/printk.h>

#include "matrix.h"

/* LED index (row-major pixel) -> {high pin, low pin} on the matrix port */
#if defined(CONFIG_BOARD_ARDUINO_UNO_Q)
#define MATRIX_PORT GPIOF
/* Keep pins 14 and 15; 0-13 are the matrix (11-13 left as inputs) */
#define MATRIX_MODER_KEEP 0xF0000000U
static const uint8_t pins[MATRIX_PIXELS][2] = {
	{0, 1}, {1, 0}, {0, 2}, {2, 0}, {1, 2}, {2, 1}, {0, 3}, {3, 0},
	{1, 3}, {3, 1}, {2, 3}, {3, 2}, {0, 4}, {4, 0}, {1, 4}, {4, 1},
	{2, 4}, {4, 2}, {3, 4}, {4, 3}, {0, 5}, {5, 0}, {1, 5}, {5, 1},
	{2, 5}, {5, 2}, {3, 5}, {5, 3}, {4, 5}, {5, 4}, {0, 6}, {6, 0},
	{1, 6}, {6, 1}, {2, 6}, {6, 2}, {3, 6}, {6, 3}, {4, 6}, {6, 4},
	{5, 6}, {6, 5}, {0, 7}, {7, 0}, {1, 7}, {7, 1}, {2, 7}, {7, 2},
	{3, 7}, {7, 3}, {4, 7}, {7, 4}, {5, 7}, {7, 5}, {6, 7}, {7, 6},
	{0, 8}, {8, 0}, {1, 8}, {8, 1}, {2, 8}, {8, 2}, {3, 8}, {8, 3},
	{4, 8}, {8, 4}, {5, 8}, {8, 5}, {6, 8}, {8, 6}, {7, 8}, {8, 7},
	{0, 9}, {9, 0}, {1, 9}, {9, 1}, {2, 9}, {9, 2}, {3, 9}, {9, 3},
	{4, 9}, {9, 4}, {5, 9}, {9, 5}, {6, 9}, {9, 6}, {7, 9}, {9, 7},
	{8, 9}, {9, 8}, {0, 10}, {10, 0}, {1, 10}, {10, 1}, {2, 10}, {10, 2},
	{3, 10}, {10, 3}, {4, 10}, {10, 4}, {5, 10}, {10, 5}, {6, 10}, {10, 6},
};
#define MATRIX_PORT_NODE DT_NODELABEL(gpiof)
#elif defined(CONFIG_BOARD_ARDUINO_VENTUNO_Q)
#define MATRIX_PORT GPIOH
/* Keep pins 0, 1, 8, 11 and 12, which are not part of the matrix */
#define MATRIX_MODER_KEEP 0x03C3000FU
static const uint8_t pins[MATRIX_PIXELS][2] = {
	{2, 3}, {3, 2}, {2, 4}, {4, 2}, {3, 4}, {4, 3}, {2, 5}, {5, 2},
	{3, 5}, {5, 3}, {4, 5}, {5, 4}, {2, 6}, {6, 2}, {3, 6}, {6, 3},
	{4, 6}, {6, 4}, {5, 6}, {6, 5}, {2, 7}, {7, 2}, {3, 7}, {7, 3},
	{4, 7}, {7, 4}, {5, 7}, {7, 5}, {6, 7}, {7, 6}, {2, 9}, {9, 2},
	{3, 9}, {9, 3}, {4, 9}, {9, 4}, {5, 9}, {9, 5}, {6, 9}, {9, 6},
	{7, 9}, {9, 7}, {2, 10}, {10, 2}, {3, 10}, {10, 3}, {4, 10}, {10, 4},
	{5, 10}, {10, 5}, {6, 10}, {10, 6}, {7, 10}, {10, 7}, {9, 10}, {10, 9},
	{2, 13}, {13, 2}, {3, 13}, {13, 3}, {4, 13}, {13, 4}, {5, 13}, {13, 5},
	{6, 13}, {13, 6}, {7, 13}, {13, 7}, {9, 13}, {13, 9}, {10, 13}, {13, 10},
	{2, 14}, {14, 2}, {3, 14}, {14, 3}, {4, 14}, {14, 4}, {5, 14}, {14, 5},
	{6, 14}, {14, 6}, {7, 14}, {14, 7}, {9, 14}, {14, 9}, {10, 14}, {14, 10},
	{13, 14}, {14, 13}, {2, 15}, {15, 2}, {3, 15}, {15, 3}, {4, 15}, {15, 4},
	{5, 15}, {15, 5}, {6, 15}, {15, 6}, {7, 15}, {15, 7}, {9, 15}, {15, 9},
};
#define MATRIX_PORT_NODE DT_NODELABEL(gpioh)
#else
#error "No LED matrix pin table for this board"
#endif

#define SCAN_PERIOD_US 10

struct frame {
	uint32_t revision;
	uint64_t deadline_us;
	uint8_t bitmap[MATRIX_BYTES];
};

/* Two scan buffers: the ISR reads `active` and swaps at a scan boundary. */
static uint8_t scan_buf[2][MATRIX_BYTES];
static volatile uint8_t active;

/* Single-producer (threads, under the lock) / single-consumer (ISR) queue */
static struct frame queue[MATRIX_QUEUE_DEPTH];
static volatile uint32_t q_head, q_tail;
static uint64_t last_deadline_us;
static struct k_spinlock lock;

static volatile struct matrix_status status;
static bool started;

uint64_t matrix_now_us(void)
{
	return k_ticks_to_us_floor64(k_uptime_ticks());
}

static inline void led(int idx, bool on)
{
	uint32_t moder = MATRIX_PORT->MODER & MATRIX_MODER_KEEP;

	if (on) {
		uint8_t hi = pins[idx][0];
		uint8_t lo = pins[idx][1];

		MATRIX_PORT->BSRR = BIT(hi) | BIT(lo + 16);
		moder |= BIT(hi * 2) | BIT(lo * 2);
	}
	MATRIX_PORT->MODER = moder;
}

/* Scan boundary: apply the head frame once its deadline has passed. */
static void scan_boundary(void)
{
	if (q_head == q_tail) {
		return;
	}
	struct frame *f = &queue[q_head % MATRIX_QUEUE_DEPTH];
	uint64_t now = matrix_now_us();

	if (now < f->deadline_us) {
		return;
	}
	uint8_t next = active ^ 1;

	memcpy(scan_buf[next], f->bitmap, MATRIX_BYTES);
	active = next;
	status.applied_revision = f->revision;
	status.applied_us = now;
	/* Deadline 0 means "next boundary": nothing to be late for */
	status.applied_late_us =
		f->deadline_us ? (uint32_t)MIN(now - f->deadline_us, UINT32_MAX) : 0;
	status.applied_count++;
	q_head++;
}

static void scan_isr(const struct device *dev, void *user_data)
{
	static int idx;
	const uint8_t *buf = scan_buf[active];

	ARG_UNUSED(dev);
	ARG_UNUSED(user_data);

	led(idx, (buf[idx >> 3] & BIT(idx & 7)) != 0);
	if (++idx == MATRIX_PIXELS) {
		idx = 0;
		scan_boundary();
	}
}

int matrix_init(void)
{
	const struct device *counter = DEVICE_DT_GET(DT_NODELABEL(counter_matrix));
	const struct device *port = DEVICE_DT_GET(MATRIX_PORT_NODE);
	struct counter_top_cfg top = {
		.callback = scan_isr,
	};
	int err;

	/* The GPIO driver enables the port clock at init. */
	if (!device_is_ready(port) || !device_is_ready(counter)) {
		return -ENODEV;
	}
	MATRIX_PORT->MODER &= MATRIX_MODER_KEEP;

	top.ticks = counter_us_to_ticks(counter, SCAN_PERIOD_US);
	err = counter_set_top_value(counter, &top);
	if (err == 0) {
		err = counter_start(counter);
	}
	started = err == 0;
	return err;
}

int matrix_render_at(uint32_t revision, uint64_t deadline_us,
		     const uint8_t bitmap[MATRIX_BYTES])
{
	k_spinlock_key_t key;
	int err = 0;

	if (!started) {
		return -ENODEV;
	}
	key = k_spin_lock(&lock);
	if (q_tail - q_head >= MATRIX_QUEUE_DEPTH) {
		err = -ENOSPC;
	} else if (deadline_us < last_deadline_us) {
		err = -EINVAL;
	} else {
		struct frame *f = &queue[q_tail % MATRIX_QUEUE_DEPTH];

		f->revision = revision;
		f->deadline_us = deadline_us;
		memcpy(f->bitmap, bitmap, MATRIX_BYTES);
		last_deadline_us = deadline_us;
		q_tail++;
	}
	if (err) {
		status.rejected_count++;
	}
	k_spin_unlock(&lock, key);
	return err;
}

void matrix_cancel_pending(void)
{
	k_spinlock_key_t key = k_spin_lock(&lock);

	q_head = q_tail;
	last_deadline_us = 0;
	k_spin_unlock(&lock, key);
}

void matrix_get_status(struct matrix_status *out)
{
	k_spinlock_key_t key = k_spin_lock(&lock);

	out->applied_revision = status.applied_revision;
	out->applied_us = status.applied_us;
	out->applied_late_us = status.applied_late_us;
	out->applied_count = status.applied_count;
	out->rejected_count = status.rejected_count;
	out->pending = q_tail - q_head;
	k_spin_unlock(&lock, key);
}
