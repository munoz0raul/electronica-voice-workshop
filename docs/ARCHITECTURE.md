# Architecture

One **VENTUNO Q** is the server: it runs the Foundries update-server (the
FoundriesFactory replacement) and the demo Wi-Fi access point.
One **UNO Q** and one **IQ-9075 EVK** are end devices: they run the voice→LED/matrix
app and the assets app that carries its model. All three run a Qualcomm Linux (QLI (Qualcomm Linux Image))
OSTree image with the Foundries OTA client built in; the UNO Q's LED matrix is driven by
Zephyr firmware on its on-board STM32U5. The IQ-9075 EVK has no MCU or physical
LEDs — the web UI and voice recognition work, but LED/matrix output is absent.

```
                demo Wi-Fi (VENTUNO Q is the AP, demo-server.local)
┌──────────────────────────────────┐       ┌───────────────────────────────────────┐
│ VENTUNO Q — server               │       │ UNO Q — end device                    │
│                                   │  reg /│                                       │
│  update-server (systemd)          │◀──────▶  aktualizr-lite ── pulls Targets      │
│    :8080 web UI + REST /v1        │ 5 s   │  fioconfig   ──── applies config      │
│    :8443 device gateway (mTLS)    │       │                                       │
│    /devices lists each device's   │  OTA  │  webapp-led-mcu-voice  (:8000)        │
│    current Target + version       │──────▶│    └─ mic → Edge Impulse → LEDs       │
│                                   │       │    └─ /dev/ttyHS1 → Zephyr matrix     │
│  poll-and-build (timer, 2 min)    │       │  webapp-led-mcu-voice-assets          │
│    builds apps on git push        │       │    └─ drops model in /var/local/      │
│    stages + rolls out Targets     │       └───────────────────────────────────────┘
│    for UNO Q, VENTUNO Q, IQ9      │       ┌───────────────────────────────────────┐
│                                   │  reg /│ IQ-9075 EVK — end device              │
│  webapp-led-mcu-voice  (:8000)    │◀──────▶  aktualizr-lite ── pulls Targets      │
│    └─ mic → Edge Impulse → LEDs   │  OTA  │                                       │
│  webapp-led-mcu-voice-assets      │──────▶│  webapp-led-mcu-voice  (:8000)        │
│                                   │       │    └─ mic → Edge Impulse (needs mic)  │
│  demo-wifi AP · chrony · mDNS     │       │    (no MCU · no physical LEDs)        │
└──────────────────────────────────┘       │  webapp-led-mcu-voice-assets          │
                                            │    └─ drops model in /var/local/      │
                                            └───────────────────────────────────────┘
```

## What runs where

| Device | Compose apps | Host services (from the image) |
| --- | --- | --- |
| VENTUNO Q | `webapp-led-mcu-voice`, `webapp-led-mcu-voice-assets`, `dorbell` | update-server, poll-and-build, demo-wifi AP, chrony server, mDNS |
| UNO Q | `webapp-led-mcu-voice`, `webapp-led-mcu-voice-assets`, `dorbell` | demo-wifi auto-join, chrony client, `zephyr-loader` |
| IQ-9075 EVK | `webapp-led-mcu-voice`, `webapp-led-mcu-voice-assets`, `dorbell` | demo-wifi auto-join, chrony client |

Each app is a Docker Compose application delivered in a Target and run by
aktualizr-lite. The apps are built by `build-apps.sh` and staged into
Targets by `tools/stage-target.sh`; see [REPRODUCE.md](REPRODUCE.md).

`dorbell` is a face-recognition doorbell that draws an on-screen OpenCV window
and runs face inference on the NPU (Neural Processing Unit) through the Hexagon
Tensor Processor. It serves no network port; the window is the whole UI. Its
inference graph is HTP (Hexagon Tensor Processor) version specific, so the image
carries both boards' context binaries and selects the pair at runtime from the
board's HTP version. See [apps/dorbell/README.md](../apps/dorbell/README.md).

## The OTA flow

The update-server plays the role a FoundriesFactory plays in a hosted setup,
locally:

1. Each board registers once (`fio-device-register`) and gets device-gateway
   credentials. From then it checks in every **5 s** (`demo-polling`).
2. You build apps, stage a **Target** — an `ostree_repo` (the OS) plus staged
   compose apps — and `fiocli updates upload main <name> <dir>` it. Each upload
   is one Target, tagged `main`, versioned higher than the last.
3. `fiocli updates create-rollout` points a Target at a device **group**, and
   enrolls the devices that are in that group at the moment it is created. At its
   next check-in, an enrolled device whose tag matches pulls the Target.
4. A Target that changes only apps (same `ostree_repo`) is an **app-only**
   update: fast, no reboot. A changed OS hash is an OS update and reboots.

The workshop loop ([REPRODUCE.md](REPRODUCE.md)) is step 2–4 repeated: a new model
is a new build of the assets app → a new Target → a rollout to the `demo` group.

## update-server host service

The update-server is **not** a compose app. As one, it would be delivered and
restarted by the OTA client that depends on it — a VENTUNO Q app update could
stop the server mid-rollout. It runs instead as a systemd service in the
VENTUNO Q image, started at boot:

- The image builds `fioserver` from
  [foundriesio/update-server](https://github.com/foundriesio/update-server) and
  runs `fioserver --datadir /var/local/datadir serve`.
- `/var/local/datadir` holds all server state. `/var` survives OSTree OS
  updates, so devices, Targets, configuration and tokens persist.
- It listens on **8080** (web UI + REST API `/v1`) and **8443** (device gateway,
  mTLS).
- On first boot `fioserver-init.service` creates a development datadir with
  `devserver-init`: self-signed PKI and an `admin`/`admin` login.

Reflashing VENTUNO Q erases `/var` and mints a new datadir, which re-keys the
PKI and invalidates every enrolled device. To keep an enrolled fleet across a
reflash, back up the datadir and restore it — see
[Building the OS](BUILDING-OS.md#update-server).

## Watching the fleet

The update-server serves its own web UI. Open `http://<ventuno-q-ip>:8080/devices`
(sign in with the `admin`/`admin` login from first boot) to see each registered
device, its group, its current Target and when it last checked in. That is the
fleet view for the workshop; this fork adds no dashboard of its own.

## The UNO Q app

`webapp-led-mcu-voice` does keyword spotting on the USB-microphone audio with an
Edge Impulse `.eim` model (labels `select` + `blue green purple red yellow`) and
drives two things on a recognised colour:

- the **8×13 LED matrix** on the STM32U5, over the SMP/MCUmgr protocol on
  `/dev/ttyHS1` (`mcu_matrix.py`; the protocol is in
  [MCU-INTERFACE.md](lighting-protocol/MCU-INTERFACE.md)), and
- the host **RGB LEDs** via sysfs.

Two start-time workarounds live in its `start.sh` (documented in
`apps/webapp-led-mcu-voice/README.md`):

- **USB audio.** The demo image ships `snd-usb-audio` (baked in as
  `kernel-module-snd-usb-audio` — [Building the OS](BUILDING-OS.md#usb-audio)),
  so a USB mic appears as an ALSA card on hotplug. The app captures through the
  ALSA `default` PCM (`PA_ALSA_DEVICE=3`). As a fallback for an image built
  without the module, `start.sh` side-loads a bundled `.ko` when no ALSA card is
  present.
- **MCU port.** `MCU_PORT` defaults to `/dev/ttyHS1`.

The model comes from `webapp-led-mcu-voice-assets`, which carries a baked-in
`deployment.eim`, writes it to `/var/local/assets/deployment.eim`, and restarts
the voice app when the file changes. The voice app prefers that path over its
own baked-in copy. Shipping the model this way means a retrain is an app update,
not an OS change — the whole point of the workshop.

## The IQ-9075 EVK app

The IQ-9075 EVK runs the same two compose apps as the UNO Q. Differences:

- **No MCU**: no `/dev/ttyHS1`, no Zephyr firmware. `mcu_matrix.py` attempts to
  open `MCU_PORT` and fails silently — all matrix/LED calls return `False` and the
  app continues normally.
- **No sysfs LEDs**: the IQ9 has no `unoq:*` LED nodes. `set_system_leds()` calls
  are swallowed by the same exception handler.
- **USB mic optional**: the image bakes in `kernel-module-snd-usb-audio`, so a USB
  webcam or mic appears as ALSA card 3 (`PA_ALSA_DEVICE=3`) on hotplug. Without
  one the voice runner logs `There are no audio devices available` and keeps
  retrying; the Flask web UI on `:8000` runs regardless.
- **Network access**: the IQ9 joins the demo Wi-Fi (10.42.0.x subnet), same as the
  UNO Q. Reach its web UI via ProxyJump:
  `ssh -L 8001:<iq9-ip>:8000 -J root@<ventuno-q-ip> root@<iq9-ip>`

## Host services the image provides

| Host service | Provided by |
| --- | --- |
| Wi-Fi AP (VENTUNO Q) and auto-join (UNO Q, IQ9) | `demo-wifi` NetworkManager profiles |
| Service discovery (`demo-server.local`) | mDNS |
| Clock sync | chrony: VENTUNO Q serves the demo network; UNO Q and IQ9 follow it |
| MCU firmware load | `zephyr-loader.service` (UNO Q only) |
| update-server (VENTUNO Q) | systemd service; state in `/var/local/datadir` |
| poll-and-build (VENTUNO Q) | systemd timer; polls repo every 2 min |
| Container runtime + OTA | Foundries packagegroups; `demo-polling` sets the 5 s check-in |

See [Building the OS](BUILDING-OS.md) for how these are built into the image.
