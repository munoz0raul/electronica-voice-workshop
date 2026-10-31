/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Qualcomm Innovation Center, Inc. All rights reserved. */
/*
 * 8 x 13 charlieplexed LED matrix on the UNO Q / VENTUNO Q MCU.
 *
 * See docs/lighting-protocol/MCU-INTERFACE.md for bitmap layout, orientation,
 * queue semantics and scheduled presentation.
 */
#ifndef DEMO_MATRIX_H_
#define DEMO_MATRIX_H_

#include <stdbool.h>
#include <stdint.h>

#define MATRIX_ROWS 8
#define MATRIX_COLS 13
#define MATRIX_PIXELS (MATRIX_ROWS * MATRIX_COLS)
#define MATRIX_BYTES ((MATRIX_PIXELS + 7) / 8)
#define MATRIX_QUEUE_DEPTH 4

struct matrix_status {
	/* Revision and MCU uptime (us) of the last applied frame */
	uint32_t applied_revision;
	uint64_t applied_us;
	/* Applied minus queued deadline for that frame, in us */
	uint32_t applied_late_us;
	uint32_t pending;
	uint32_t applied_count;
	uint32_t rejected_count;
};

int matrix_init(void);

/*
 * Queue a frame for the first scan boundary at or after deadline_us (MCU
 * uptime; 0 = next boundary). Deadlines must not go backwards.
 * Returns 0, -ENOSPC when the queue is full, -EINVAL for a deadline earlier
 * than the last queued frame, or -ENODEV before matrix_init().
 */
int matrix_render_at(uint32_t revision, uint64_t deadline_us,
		     const uint8_t bitmap[MATRIX_BYTES]);

/* Drop queued frames; the visible image is kept. */
void matrix_cancel_pending(void);

void matrix_get_status(struct matrix_status *status);

/* True once Linux has opened a matrix service session (HELLO). */
bool matrix_svc_active(void);

/* MCU uptime in us, the time base for deadlines */
uint64_t matrix_now_us(void);

#endif /* DEMO_MATRIX_H_ */
