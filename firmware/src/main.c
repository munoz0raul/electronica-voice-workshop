/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Qualcomm Innovation Center, Inc. All rights reserved. */
#include <string.h>
#include <zephyr/kernel.h>
#include <zephyr/sys/printk.h>

#include "matrix.h"

static void set_pixel(uint8_t *bitmap, int row, int col)
{
	int idx = row * MATRIX_COLS + col;

	bitmap[idx / 8] |= BIT(idx % 8);
}

/*
 * Matrix self-test: whole panel on, then row 0 plus column 0 (an "L" whose
 * corner is pixel 0,0) for orientation, then a vertical bar per heartbeat.
 */
static void show_test_frame(uint32_t revision)
{
	uint8_t bitmap[MATRIX_BYTES] = {0};

	if (revision == 0) {
		memset(bitmap, 0xff, sizeof(bitmap));
	} else if (revision <= 3000 / CONFIG_DEMO_BAR_PERIOD_MS) {
		for (int col = 0; col < MATRIX_COLS; col++) {
			set_pixel(bitmap, 0, col);
		}
		for (int row = 0; row < MATRIX_ROWS; row++) {
			set_pixel(bitmap, row, 0);
		}
	} else {
		for (int row = 0; row < MATRIX_ROWS; row++) {
			set_pixel(bitmap, row, revision % MATRIX_COLS);
		}
	}
	matrix_render_at(revision, 0, bitmap);
}

int main(void)
{
	int ret;
	unsigned int heartbeat = 0;
	struct matrix_status st;

	printk("Demo firmware started (%s)\n", IS_ENABLED(CONFIG_XIP) ? "flash" : "RAM");
	ret = matrix_init();
	printk("LED matrix: %s (%d)\n", ret == 0 ? "scanning" : "failed", ret);
	show_test_frame(0);

	uint32_t frame = 0;
	int64_t next_beat = k_uptime_get() + 1000;

	while (1) {
		k_sleep(K_MSEC(CONFIG_DEMO_BAR_PERIOD_MS));
		/* Linux owns the matrix once it opens a session */
		if (!matrix_svc_active()) {
			show_test_frame(++frame);
		}
		if (k_uptime_get() < next_beat) {
			continue;
		}
		next_beat += 1000;
		matrix_get_status(&st);
		printk("MCU heartbeat: %u (matrix rev %u, %u applied, %u us late)\n", ++heartbeat,
		       st.applied_revision, st.applied_count, st.applied_late_us);
	}
}
