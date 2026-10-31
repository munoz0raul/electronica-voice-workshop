/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Qualcomm Innovation Center, Inc. All rights reserved. */
/*
 * Keep recent console output for Linux: printk text still goes to the
 * console UART and is also copied into a ring buffer that the matrix
 * service's LOG command drains. When full, the oldest bytes are dropped.
 */
#include <zephyr/init.h>
#include <zephyr/kernel.h>
#include <zephyr/sys/printk-hooks.h>
#include <zephyr/sys/ring_buffer.h>

#include "mcu_log.h"

#define MCU_LOG_SIZE 2048

RING_BUF_DECLARE(log_ring, MCU_LOG_SIZE);
static struct k_spinlock lock;
static uint32_t dropped;
static printk_hook_fn_t console_hook;

static int log_hook(int c)
{
	uint8_t byte = c;
	k_spinlock_key_t key = k_spin_lock(&lock);

	if (ring_buf_space_get(&log_ring) == 0) {
		uint8_t old;

		ring_buf_get(&log_ring, &old, 1);
		dropped++;
	}
	ring_buf_put(&log_ring, &byte, 1);
	k_spin_unlock(&lock, key);

	return console_hook ? console_hook(c) : c;
}

size_t mcu_log_read(uint8_t *buf, size_t max, uint32_t *remaining, uint32_t *dropped_out)
{
	k_spinlock_key_t key = k_spin_lock(&lock);
	size_t len = ring_buf_get(&log_ring, buf, max);

	*remaining = ring_buf_size_get(&log_ring);
	*dropped_out = dropped;
	k_spin_unlock(&lock, key);
	return len;
}

static int mcu_log_init(void)
{
	/* Runs after the console driver has installed its hook */
	console_hook = __printk_get_hook();
	__printk_hook_install(log_hook);
	return 0;
}

SYS_INIT(mcu_log_init, APPLICATION, 0);
