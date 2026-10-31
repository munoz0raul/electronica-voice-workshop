/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Qualcomm Innovation Center, Inc. All rights reserved. */
#ifndef DEMO_MCU_LOG_H_
#define DEMO_MCU_LOG_H_

#include <stddef.h>
#include <stdint.h>

/*
 * Move up to max bytes of buffered console output into buf. Reports the
 * bytes still buffered and the total dropped because the buffer was full.
 */
size_t mcu_log_read(uint8_t *buf, size_t max, uint32_t *remaining, uint32_t *dropped);

#endif /* DEMO_MCU_LOG_H_ */
