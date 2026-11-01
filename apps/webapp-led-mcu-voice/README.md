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

## Audio capture device

The app captures through the ALSA `default` PCM, chosen by `PA_ALSA_DEVICE` in
`docker-compose.yml` (`3`). That device resamples to the model's 16 kHz mono;
the raw `hw:0,0` device (index `0`) is fixed at 44100 Hz and rejects a 16 kHz
open, so the runner gets no frames there.

## Two things done at start

The USB mic needs the `snd-usb-audio` kernel module, and the container does not
see the host's `/dev/mcu-console` symlink. `start.sh` handles both:

1. **snd-usb-audio** — the OS image bakes the module in
   (`kernel-module-snd-usb-audio`, see
   [`docs/BUILDING-OS.md`](../../docs/BUILDING-OS.md)), so the ALSA card is
   present at start. As a fallback for an image built without it, `start.sh`
   `insmod`s a bundled `.ko` from `modules/` in dependency order when no ALSA
   card is found. Those `.ko` files are version-locked to one kernel
   (`7.0.14-gf2e5cd16ede5-dirty`), so keep them in step with the image kernel if
   you rely on the fallback.
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
`PA_ALSA_DEVICE=3` capture device, `MCU_PORT` — are in the repo. The OS image is
rebuilt with `snd-usb-audio` baked in, flashed, and verified end-to-end through
the OTA path; the app's `start.sh` side-load is now a fallback.
