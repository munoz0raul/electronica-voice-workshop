# Linux–MCU matrix interface

This is the specification for the LED matrix service implemented by the
shared UNO Q and VENTUNO Q Zephyr firmware. The Linux client sends complete
bitmaps and presentation deadlines; the MCU queues frames and applies them at
matrix scan boundaries. Audio analysis, render styles, surface placement and
rotation belong on Linux. In this fork the client is
[`mcu_matrix.py`](../../apps/webapp-led-mcu-voice/mcu_matrix.py), inside the
voice app.

The implementation is in
[`matrix_svc.c`](../../firmware/src/matrix_svc.c),
[`matrix.c`](../../firmware/src/matrix.c),
[`matrix.h`](../../firmware/src/matrix.h) and
[`mcu_log.c`](../../firmware/src/mcu_log.c).
See [Building Zephyr](../BUILDING-ZEPHYR.md) for firmware builds and
[Linux startup](../BUILDING-OS.md#linux-startup) for loading the MCU firmware.

## Transport and ownership

Applications open `/dev/mcu-console`, provided by the zephyr-loader package's
machine-specific udev rule:

| Board | Underlying link |
| --- | --- |
| UNO Q | STM32 LPUART1 connected to Linux `/dev/ttyHS1`, 115200 baud, 8N1 |
| VENTUNO Q | USB CDC ACM; STM32 USB HS connected to the QCS8300 `usb_2` host controller |

The VENTUNO Q MCU enumerates with USB IDs `2fe3:0004` and product string
`VENTUNO Q MCU`. Use the stable symlink instead of a numbered USB tty.

The Linux client is the single owner of this link and keeps it open while
running. This avoids competing readers and differences in UART/USB buffering
when no reader is present. Arduino Router, if installed, must not concurrently
own `/dev/ttyHS1`.

Containers need access to the device and appropriate device cgroup permissions.
On VENTUNO Q, reloading MCU firmware recreates the USB device. Expose devices
through a directory bind and a device cgroup rule that permits the recreated
node, and reopen `/dev/mcu-console` after reconnecting.

The wire protocol uses Zephyr's
[MCUmgr SMP](https://docs.zephyrproject.org/latest/services/device_mgmt/smp_protocol.html)
and [serial transport](https://docs.zephyrproject.org/latest/services/device_mgmt/smp_transport.html):

- Custom management group **64**, with matrix-service schema version **1**.
  The schema version returned by `HELLO` is separate from SMP's wire version.
- [CBOR](https://datatracker.ietf.org/doc/html/rfc8949) maps with short text keys;
  bitmap and log data use CBOR byte strings.
- An eight-byte SMP header carries operation, payload length, group, transaction
  sequence and command ID. Multibyte header fields use network byte order.
- Read requests use operation 0; write requests use operation 2. Responses use
  the corresponding SMP response operation and transaction sequence.
- Serial framing adds a two-byte packet length and CRC16/XMODEM, then Base64
  encoding and newline-delimited fragments. The initial fragment starts with
  bytes `06 09`; continuation fragments start with `04 14`.

The CRC covers the SMP header and CBOR payload. The length counts those bytes
plus the CRC, excluding the length field itself. Both the length and CRC are
encoded as big-endian 16-bit values before Base64 encoding.

The eight-bit SMP transaction sequence correlates request/response pairs.
The separate 32-bit frame revision identifies displayed content.

## Bitmap format and orientation

Each frame contains **8 rows × 13 columns**, or 104 binary pixels packed into
exactly **13 bytes**. A set bit turns its LED on; there is no per-pixel dimming.

```text
index = row * 13 + column
byte  = index / 8
mask  = 1 << (index % 8)
```

Coordinates are row-major with the first pixel in the least-significant bit
of the first byte. Physical orientation, seen from above:

| Board | Pixel (0, 0) | Columns 0 → 12 | Rows 0 → 7 |
| --- | --- | --- | --- |
| UNO Q | USB-C end, inner edge | USB-C end → STM32 LED end | inner edge → outer edge |
| VENTUNO Q | back edge (no connectors), inner edge | back → front (ports) | inner edge → outer edge |

Linux rotates or mirrors each board's slice to match its mounting. Zephyr maps
these native pixel indices to the board's GPIO pin pairs.

## Commands

All integer fields are unsigned. `s` is a 64-bit session ID, `f` is a 32-bit
frame revision, and all timestamps are 64-bit **MCU uptime in microseconds**.
The braces below describe CBOR maps, rather than JSON wire encoding.

| ID | Command | Operation | Required request fields | Successful response fields |
| ---: | --- | --- | --- | --- |
| 0 | `HELLO` | write | `{s}` | `{v, rows, cols, q, now}` |
| 1 | `CLOCK_SAMPLE` | read | `{}` | `{rx, tx}` |
| 2 | `RENDER_AT` | write | `{s, f, t, p}` | `{q}` |
| 3 | `STATUS` | read | `{s}` | `{f, at, late, q, n, rej, now}` |
| 4 | `CANCEL_PENDING` | write | `{s}` | No command-specific fields |
| 5 | `LOG` | read | `{}` | `{d, more, drop}` |

### HELLO

`s` must be nonzero. Each successful handshake replaces the active session,
clears the pending queue and queues a blank bitmap with revision 0 for the next
scan boundary. The reply returns `v = 1`, `rows = 8`, `cols = 13`, queue
**capacity** `q = 4`, and current MCU time `now`. Linux checks these capabilities
before rendering.

Before the first handshake, the MCU displays its self-test. After a handshake,
Linux owns the display. The session has no timeout or close command; closing
the Linux device does not resume the self-test. A new handshake replaces the
session, and an MCU reset loses it. Applied/rejected counters are not reset by
the handshake.

### CLOCK_SAMPLE

This command needs no session and does not change display ownership. `rx` is
sampled at handler entry; `tx` is sampled while constructing the reply. These
are application-handler timestamps, not the times of the first/last byte on
the wire.

### RENDER_AT

```text
{
  "s": uint64 session_id,
  "f": uint32 frame_revision,
  "t": uint64 mcu_deadline_us,
  "p": bytes[13] bitmap
}
```

The handler validates the fields, checks the active session, copies the frame
into pending storage, and acknowledges **queued**. It does not wait for the
deadline or acknowledge visible rendering. Response `q` is queue occupancy
when sampled; a frame can already have been applied by that time.

`t = 0` requests the next available scan boundary. Other values specify an
MCU-local presentation deadline. Frame revisions are labels: repeated revisions
can enqueue additional frames, including different contents. Callers must not
assume retries are idempotent.

### STATUS

The active session is required. Response fields are:

| Field | Type | Meaning |
| --- | --- | --- |
| `f` | uint32 | Last applied frame revision |
| `at` | uint64 | MCU uptime at that frame's scan-boundary swap |
| `late` | uint32 | Swap time minus requested deadline, saturated at uint32 maximum; 0 for an immediate frame |
| `q` | uint32 | Number of pending frames |
| `n` | uint32 | Cumulative applied-frame count, including self-test and handshake blank frames |
| `rej` | uint32 | Cumulative driver enqueue rejections; malformed requests and wrong sessions do not increment it |
| `now` | uint64 | MCU uptime while constructing the reply |

`STATUS` does not consume or cancel frames.

### CANCEL_PENDING

The active session is required. Cancellation discards all pending frames and
resets the deadline-ordering baseline to zero. It preserves the visible bitmap,
active session and counters. Use it when abandoning a scheduled sequence or
switching from future deadlines back to immediate frames.

### LOG

This command needs no session and does not change display ownership. It drains
up to 200 bytes from the MCU's 2048-byte console ring buffer:

- `d`: console output as a byte string.
- `more`: number of bytes still buffered after the read.
- `drop`: cumulative number of oldest bytes discarded when the ring was full.

Reading consumes the returned bytes. Poll while `more` is nonzero to drain the
buffer. MCU console text also goes to the header UART at 115200 baud: USART1 on
UNO Q D1/TX (PB6) and D0/RX (PB7), and USART3 on VENTUNO Q. The startup message
identifies RAM/flash execution, and a once-per-second heartbeat reports MCU
progress. Linux loader logs are available through `journalctl -u zephyr-loader`.

## Queue and presentation semantics

The driver maintains a FIFO of four immutable pending frames, plus two scan
buffers. Handlers enqueue frames outside the scan interrupt. At each complete
scan boundary, the interrupt applies at most one due frame by copying it into
the inactive scan buffer and switching buffers. Every scan therefore displays
one complete image. The active image remains visible until replaced.

Queue admission follows these rules:

- A full queue returns an error; an acknowledged frame is not evicted to make
  room for a new arrival.
- A deadline earlier than the last accepted deadline returns an error. Equal
  deadlines are allowed. This ordering baseline persists after the queue drains
  and resets only on cancellation or handshake.
- An already-due deadline is accepted if it satisfies the ordering rule; it is
  applied at the next available scan boundary when it reaches the FIFO head.
- There is no minimum lead time or maximum future horizon. Linux chooses lead
  time and handles obsolete frames before submitting them.

The same ordering rule applies to `t = 0`. After accepting a positive deadline,
cancel the pending sequence or establish a new session before using zero.
Multiple overdue frames advance one per scan boundary in FIFO order.

The scanner visits one LED every 10 µs, giving a nominal 1.04 ms full scan.
Actual presentation timing also depends on interrupt execution and uptime
resolution; the timestamp unit alone does not guarantee microsecond precision.
If the Linux process disconnects, queued frames can still become visible and
the MCU continues scanning the last applied image.

## Errors

The test client's SMP wire version receives failures as an `rc` value. A
successful response can omit `rc`. Codes used by the service in the pinned
Zephyr 4.4.2 headers are:

| Code | Name | Meaning |
| ---: | --- | --- |
| 2 | `ENOMEM` | Pending-frame queue full |
| 3 | `EINVAL` | Malformed/missing required fields, zero handshake session, wrong bitmap length, or decreasing deadline |
| 6 | `EBADSTATE` | Matrix driver unavailable or another unexpected enqueue failure |
| 7 | `EMSGSIZE` | Response encoding did not fit |
| 11 | `EACCESSDENIED` | No active session or session does not match |

An acknowledgement can be lost after a request has changed MCU state. Reconcile
with status or cancel/restart the sequence rather than assuming a retry cannot
enqueue a second frame. A response encoding failure also does not roll back a
handler's completed state changes.

## Clock mapping and Linux client policy

The MCU does not run NTP or track civil time. Linux maps server presentation
time to its disciplined host clock, then maps host monotonic time to MCU uptime
using repeated `CLOCK_SAMPLE` exchanges. Estimate offset, drift and uncertainty;
serial asymmetry, workqueue scheduling and reply transmission affect the
estimate. Lowest-delay samples are a useful starting point, with independent
timing measurements needed to validate the result. Determine effective clock
resolution from the firmware configuration and measurements.

Linux sends scheduled frames ahead of their deadlines and monitors clock
uncertainty. On a clock discontinuity, cancel obsolete pending work and rebuild
the mapping before resuming. On MCU reset or reconnection, establish a fresh
session and mapping. These are client responsibilities; the MCU enforces the
queue rules above and reports actual swap times and lateness.

Coalesce excessive updates on Linux before publication. Network revision
tracking, duplicate suppression, cohort selection and recovery to a current
surface snapshot belong to the Linux services. The same MCU interface supports
sACN, DDP or other Linux-side network encodings.

## Bring-up and validation

`mcu_matrix.py` runs as a standalone smoke test. Stop the voice app first so it
isn't contending for the link, then run it on the board; with no argument it
opens `/dev/mcu-console`:

```sh
python3 mcu_matrix.py                 # renders a microphone icon, all-on, clear
python3 mcu_matrix.py /dev/ttyHS1     # explicit port
```

It sends HELLO to open a session and drives the matrix through the render path
below. Only one owner may hold the link at a time, so don't run it alongside
the voice app.

Recorded bring-up round trips at 50 ms frame intervals are about 15 ms on
UNO Q and 5 ms on VENTUNO Q. These are request/response measurements, not
acoustic-to-visible latency or a synchronized fleet guarantee.

For a definite-length `RENDER_AT` map using maximum-width integers, the CBOR
payload is 46 bytes. With the eight-byte SMP header, serial length, CRC,
Base64 and line markers, it occupies 83 serial bytes: approximately 7.2 ms at
115200 baud, or 7.2% of that UART direction at 10 Hz. Replies, clock samples,
queuing and processing add cost. This calculation is not an end-to-end bound.

Validate scanning, long image holds, full queues, cancellation, retries,
clock drift and reconnects under application load. Measure MCU swap
timestamps; acknowledgements and Linux release timestamps alone do not
establish visible timing.

## Design rationale

SMP provides framing, integrity checks and request/response correlation while
allowing an application-defined command group. Its handlers run through
workqueue processing, so they prepare frames; a timer-driven scan boundary
controls presentation. The implementation uses Zephyr's counter peripheral
for scanning and kernel uptime for deadlines.

The pin-pair tables and scanning approach follow Arduino's
[`Arduino_LED_Matrix` library](https://github.com/arduino/ArduinoCore-zephyr/blob/main/libraries/Arduino_LED_Matrix/src/Arduino_LED_Matrix.h)
and [`loader/matrix.inc`](https://github.com/arduino/ArduinoCore-zephyr/blob/main/loader/matrix.inc).
The service adds queued immutable frames and complete-scan swaps to that
hardware-scanning approach. A custom framed transport would require maintaining
framing, correlation and recovery; RPMsg/shared memory is not established for
these separate Linux and STM32 processors. Arduino Router/Bridge integration
is only needed if App Lab compatibility becomes a requirement.
