# webapp-led-mcu-voice

The UNO Q end-device app. It runs an Edge Impulse keyword model on the USB
microphone and, on a recognised colour, lights the board's RGB status LEDs and
draws on the 8x13 LED matrix. A small web UI on `:8000` mirrors the state.

## How it works

- **Voice** — `webapp-led-mcu-voice.py` runs the Edge Impulse audio runner on
  the model at `VOICE_MODEL_PATH`. Labels are `select` plus the colours
  `blue green purple red yellow`; say `select`, then a colour.
- **Matrix** — driven over MCUmgr SMP (custom group 64) to the Zephyr firmware
  on the STM32U5, via `mcu_matrix.py` on `MCU_PORT` (`/dev/ttyHS1`). This
  replaces the old arduino-router msgpack path.
- **RGB LEDs** — host sysfs under `/sys/class/leds` (`unoq:user-*1` and the
  `unoq:{bt,wlan,panic}-*2` set). The MCU firmware has no discrete RGB LEDs.
- **Model source** — `start.sh` prefers `/var/local/assets/deployment.eim`
  (dropped there by the assets app) and falls back to the model baked into
  this image. See [`../webapp-led-mcu-voice-assets`](../webapp-led-mcu-voice-assets).

## Two things done at start, not in the OS image

The boards reused for the workshop were flashed with an OS image that does not
ship the USB-audio kernel module, and the container does not see the host's
`/dev/mcu-console` symlink. `start.sh` works around both:

1. **snd-usb-audio** — `insmod`'d from `modules/` in dependency order if no
   ALSA card is present. The `.ko` files are **version-locked to the kernel the
   boards were flashed with** (`7.0.14-gf2e5cd16ede5-dirty`). If you rebuild the
   OS with a different kernel, these stop loading (vermagic mismatch) and must
   be replaced, or — the proper fix — add `kernel-module-snd-usb-audio` to the
   OS image (see [`docs/BUILDING-OS.md`](../../docs/BUILDING-OS.md)).
2. **MCU_PORT** — set to `/dev/ttyHS1` and a `/dev/mcu-console` symlink created
   inside the container.

## Build

From the repo root:

```sh
./build-apps.sh                 # builds images/webapp-led-mcu-voice.oci.tar
```

## Status

Verified live on the UNO Q (voice -> matrix + RGB LEDs, web UI on :8000). The
on-device fixes this app makes permanent — MCUmgr matrix path, LED sysfs names,
snd-usb-audio side-load, `MCU_PORT` — were debugged on the device; the image
build itself has not been rebuilt-and-flashed through the OTA path yet.
