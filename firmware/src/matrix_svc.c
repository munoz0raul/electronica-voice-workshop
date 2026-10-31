/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Qualcomm Innovation Center, Inc. All rights reserved. */
/*
 * LED matrix service: an MCUmgr SMP group for Linux (led-matrix-client) to
 * drive the matrix over /dev/mcu-console. See docs/lighting-protocol/
 * MCU-INTERFACE.md for the interface specification.
 *
 * Handlers validate and queue; the matrix scan interrupt performs the
 * scheduled swap. CBOR maps use short keys; times are MCU uptime in us.
 */
#include <errno.h>
#include <string.h>

#include <zcbor_common.h>
#include <zcbor_decode.h>
#include <zcbor_encode.h>
#include <zephyr/kernel.h>
#include <zephyr/mgmt/mcumgr/mgmt/handlers.h>
#include <zephyr/mgmt/mcumgr/mgmt/mgmt.h>
#include <zephyr/mgmt/mcumgr/smp/smp.h>
#include <mgmt/mcumgr/util/zcbor_bulk.h>

#include "matrix.h"
#include "mcu_log.h"

#define MATRIX_SVC_GROUP MGMT_GROUP_ID_PERUSER
#define MATRIX_SVC_VERSION 1

enum matrix_svc_cmd {
	MATRIX_SVC_HELLO = 0,
	MATRIX_SVC_CLOCK_SAMPLE = 1,
	MATRIX_SVC_RENDER_AT = 2,
	MATRIX_SVC_STATUS = 3,
	MATRIX_SVC_CANCEL_PENDING = 4,
	MATRIX_SVC_LOG = 5,
};

/* Console bytes returned per LOG response */
#define MATRIX_SVC_LOG_CHUNK 200

/* The session from the last HELLO; 0 means none. */
static uint64_t session;

bool matrix_svc_active(void)
{
	return session != 0;
}

static bool session_ok(uint64_t s)
{
	return session != 0 && s == session;
}

static int decode_session(struct smp_streamer *ctxt, uint64_t *s)
{
	size_t decoded;
	struct zcbor_map_decode_key_val keys[] = {
		ZCBOR_MAP_DECODE_KEY_DECODER("s", zcbor_uint64_decode, s),
	};

	if (zcbor_map_decode_bulk(ctxt->reader->zs, keys, ARRAY_SIZE(keys), &decoded) != 0 ||
	    decoded != 1) {
		return MGMT_ERR_EINVAL;
	}
	return session_ok(*s) ? MGMT_ERR_EOK : MGMT_ERR_EACCESSDENIED;
}

/*
 * HELLO {s: new session} -> {v, rows, cols, q, now}; flushes queued frames and
 * blanks the matrix (revision 0) until Linux sends its first frame.
 */
static int hello(struct smp_streamer *ctxt)
{
	zcbor_state_t *zse = ctxt->writer->zs;
	uint64_t s = 0;
	size_t decoded;
	struct zcbor_map_decode_key_val keys[] = {
		ZCBOR_MAP_DECODE_KEY_DECODER("s", zcbor_uint64_decode, &s),
	};

	if (zcbor_map_decode_bulk(ctxt->reader->zs, keys, ARRAY_SIZE(keys), &decoded) != 0 ||
	    decoded != 1 || s == 0) {
		return MGMT_ERR_EINVAL;
	}
	static const uint8_t blank[MATRIX_BYTES];

	matrix_cancel_pending();
	matrix_render_at(0, 0, blank);
	session = s;

	bool ok = zcbor_tstr_put_lit(zse, "v") && zcbor_uint32_put(zse, MATRIX_SVC_VERSION) &&
		  zcbor_tstr_put_lit(zse, "rows") && zcbor_uint32_put(zse, MATRIX_ROWS) &&
		  zcbor_tstr_put_lit(zse, "cols") && zcbor_uint32_put(zse, MATRIX_COLS) &&
		  zcbor_tstr_put_lit(zse, "q") && zcbor_uint32_put(zse, MATRIX_QUEUE_DEPTH) &&
		  zcbor_tstr_put_lit(zse, "now") && zcbor_uint64_put(zse, matrix_now_us());

	return ok ? MGMT_ERR_EOK : MGMT_ERR_EMSGSIZE;
}

/* CLOCK_SAMPLE {} -> {rx: uptime at handler entry, tx: uptime at reply} */
static int clock_sample(struct smp_streamer *ctxt)
{
	uint64_t rx = matrix_now_us();
	zcbor_state_t *zse = ctxt->writer->zs;
	bool ok = zcbor_tstr_put_lit(zse, "rx") && zcbor_uint64_put(zse, rx) &&
		  zcbor_tstr_put_lit(zse, "tx") && zcbor_uint64_put(zse, matrix_now_us());

	return ok ? MGMT_ERR_EOK : MGMT_ERR_EMSGSIZE;
}

/* RENDER_AT {s, f: revision, t: deadline (0 = next scan), p: bitmap} -> {q} */
static int render_at(struct smp_streamer *ctxt)
{
	zcbor_state_t *zse = ctxt->writer->zs;
	uint64_t s = 0, t = 0;
	uint32_t f = 0;
	struct zcbor_string p = {0};
	size_t decoded;
	struct matrix_status st;
	struct zcbor_map_decode_key_val keys[] = {
		ZCBOR_MAP_DECODE_KEY_DECODER("s", zcbor_uint64_decode, &s),
		ZCBOR_MAP_DECODE_KEY_DECODER("f", zcbor_uint32_decode, &f),
		ZCBOR_MAP_DECODE_KEY_DECODER("t", zcbor_uint64_decode, &t),
		ZCBOR_MAP_DECODE_KEY_DECODER("p", zcbor_bstr_decode, &p),
	};

	if (zcbor_map_decode_bulk(ctxt->reader->zs, keys, ARRAY_SIZE(keys), &decoded) != 0 ||
	    decoded != ARRAY_SIZE(keys) || p.len != MATRIX_BYTES) {
		return MGMT_ERR_EINVAL;
	}
	if (!session_ok(s)) {
		return MGMT_ERR_EACCESSDENIED;
	}
	switch (matrix_render_at(f, t, p.value)) {
	case 0:
		break;
	case -ENOSPC:
		return MGMT_ERR_ENOMEM;
	case -EINVAL:
		return MGMT_ERR_EINVAL;
	default:
		return MGMT_ERR_EBADSTATE;
	}
	matrix_get_status(&st);
	return zcbor_tstr_put_lit(zse, "q") && zcbor_uint32_put(zse, st.pending)
		       ? MGMT_ERR_EOK
		       : MGMT_ERR_EMSGSIZE;
}

/* STATUS {s} -> {f, at, late, q, n, rej, now} */
static int status(struct smp_streamer *ctxt)
{
	zcbor_state_t *zse = ctxt->writer->zs;
	struct matrix_status st;
	uint64_t s;
	int rc = decode_session(ctxt, &s);

	if (rc != MGMT_ERR_EOK) {
		return rc;
	}
	matrix_get_status(&st);

	bool ok = zcbor_tstr_put_lit(zse, "f") && zcbor_uint32_put(zse, st.applied_revision) &&
		  zcbor_tstr_put_lit(zse, "at") && zcbor_uint64_put(zse, st.applied_us) &&
		  zcbor_tstr_put_lit(zse, "late") && zcbor_uint32_put(zse, st.applied_late_us) &&
		  zcbor_tstr_put_lit(zse, "q") && zcbor_uint32_put(zse, st.pending) &&
		  zcbor_tstr_put_lit(zse, "n") && zcbor_uint32_put(zse, st.applied_count) &&
		  zcbor_tstr_put_lit(zse, "rej") && zcbor_uint32_put(zse, st.rejected_count) &&
		  zcbor_tstr_put_lit(zse, "now") && zcbor_uint64_put(zse, matrix_now_us());

	return ok ? MGMT_ERR_EOK : MGMT_ERR_EMSGSIZE;
}

/* CANCEL_PENDING {s} -> {} ; the visible image is kept */
static int cancel_pending(struct smp_streamer *ctxt)
{
	uint64_t s;
	int rc = decode_session(ctxt, &s);

	if (rc == MGMT_ERR_EOK) {
		matrix_cancel_pending();
	}
	return rc;
}

/*
 * LOG {} -> {d: console bytes, more: still buffered, drop: total dropped}.
 * Needs no session, so diagnostics stay readable before HELLO.
 */
static int log_read(struct smp_streamer *ctxt)
{
	zcbor_state_t *zse = ctxt->writer->zs;
	uint8_t chunk[MATRIX_SVC_LOG_CHUNK];
	uint32_t more, drop;
	size_t len = mcu_log_read(chunk, sizeof(chunk), &more, &drop);
	bool ok = zcbor_tstr_put_lit(zse, "d") && zcbor_bstr_encode_ptr(zse, chunk, len) &&
		  zcbor_tstr_put_lit(zse, "more") && zcbor_uint32_put(zse, more) &&
		  zcbor_tstr_put_lit(zse, "drop") && zcbor_uint32_put(zse, drop);

	return ok ? MGMT_ERR_EOK : MGMT_ERR_EMSGSIZE;
}

static const struct mgmt_handler matrix_svc_handlers[] = {
	[MATRIX_SVC_HELLO] = {.mh_write = hello},
	[MATRIX_SVC_CLOCK_SAMPLE] = {.mh_read = clock_sample},
	[MATRIX_SVC_RENDER_AT] = {.mh_write = render_at},
	[MATRIX_SVC_STATUS] = {.mh_read = status},
	[MATRIX_SVC_CANCEL_PENDING] = {.mh_write = cancel_pending},
	[MATRIX_SVC_LOG] = {.mh_read = log_read},
};

static struct mgmt_group matrix_svc_group = {
	.mg_handlers = matrix_svc_handlers,
	.mg_handlers_count = ARRAY_SIZE(matrix_svc_handlers),
	.mg_group_id = MATRIX_SVC_GROUP,
};

static void matrix_svc_register(void)
{
	mgmt_register_group(&matrix_svc_group);
}

MCUMGR_HANDLER_DEFINE(matrix_svc, matrix_svc_register);
