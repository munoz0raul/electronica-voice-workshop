#!/bin/bash
#
# Copyright (c) 2025 Foundries.io
#
# SPDX-License-Identifier: BSD-3-Clause
#
# The MCU already runs the Zephyr LED-matrix firmware (SWD-loaded into SRAM at
# boot by the host's zephyr-loader.service). We drive it over MCUmgr SMP on the
# LPUART/USB-CDC, so there is no Arduino sketch to flash or reset here. Two
# things this board's OS image is missing, done at start instead of in the image:
#   1. snd-usb-audio (+ deps): side-loaded with insmod so the USB mic
#      enumerates an ALSA card. Version-locked to the running kernel.
#   2. /dev/mcu-console: the host symlink is not reproduced in the container;
#      we recreate it here, pointing at the board-appropriate UART:
#        UNO Q:     ttyHS1   (Qualcomm LPUART)
#        VENTUNO Q: ttyACM0  (USB-CDC Arduino)
#      MCU_PORT can be overridden via the environment if needed.
set -e

MODULES_DIR="${MODULES_DIR:-/app/modules}"

load_snd_usb_audio() {
    # Already there (image shipped it, or a previous start loaded it)? Done.
    if [ -d /proc/asound ] && grep -q '\[' /proc/asound/cards 2>/dev/null; then
        echo ">>> ALSA card already present; not loading snd-usb-audio"
        return 0
    fi
    echo ">>> No ALSA card; side-loading snd-usb-audio from $MODULES_DIR"
    # Dependency order: hwdep -> rawmidi -> usbmidi-lib -> usb-audio.
    for m in snd-hwdep snd-rawmidi snd-usbmidi-lib snd-usb-audio; do
        ko="$MODULES_DIR/$m.ko"
        if [ -f "$ko" ]; then
            insmod "$ko" 2>/dev/null \
                && echo "    insmod $m ok" \
                || echo "    insmod $m skipped (already loaded or vermagic mismatch)"
        else
            echo "    $ko missing"
        fi
    done
    if [ -f /proc/asound/cards ]; then
        echo ">>> /proc/asound/cards:"; cat /proc/asound/cards || true
    fi
}

load_snd_usb_audio

# Recreate /dev/mcu-console inside the container.  Host symlinks are not
# mirrored into the container's /dev; only real device nodes are.
# VENTUNO Q: MCU is USB-CDC (ttyACM*).  After a hot firmware reload the minor
# number can increment (ttyACM0 -> ttyACM1), so scan in order and take the
# first present device.  ttyACM always wins over ttyHS1 because VENTUNO Q
# exposes a stale ttyHS1 node alongside the real USB-CDC port.
# UNO Q: no ttyACM*, so the loop falls through to the ttyHS1 branch.
if [ -z "${MCU_PORT:-}" ]; then
    for _acm in /dev/ttyACM[0-9]; do
        if [ -e "$_acm" ]; then
            ln -sf "${_acm##*/}" /dev/mcu-console 2>/dev/null || true
            MCU_PORT=/dev/mcu-console
            break
        fi
    done
    if [ -z "${MCU_PORT:-}" ] && [ -e /dev/ttyHS1 ]; then
        ln -sf ttyHS1 /dev/mcu-console 2>/dev/null || true
        MCU_PORT=/dev/mcu-console
    fi
    : "${MCU_PORT:=/dev/mcu-console}"
fi
export MCU_PORT
echo ">>> MCU_PORT=$MCU_PORT"

echo ">>> Activating virtualenv"
source /opt/venv/bin/activate

# Prefer the model the assets app drops in the shared volume; fall back to the
# model baked into this image.
ASSETS_DIR="${ASSETS_DIR:-/var/local/assets}"
MODEL_NAME="${MODEL_NAME:-deployment.eim}"
ASSET_MODEL="${ASSETS_DIR}/${MODEL_NAME}"
DEFAULT_MODEL="/app/${MODEL_NAME}"

if [ -f "$ASSET_MODEL" ] && [ -r "$ASSET_MODEL" ]; then
    echo ">>> Using model from assets: $ASSET_MODEL"
    export VOICE_MODEL_PATH="$ASSET_MODEL"
else
    echo ">>> Using baked-in model: $DEFAULT_MODEL"
    export VOICE_MODEL_PATH="$DEFAULT_MODEL"
fi

echo ">>> Running voice app..."
exec python /app/webapp-led-mcu-voice.py "$VOICE_MODEL_PATH"
