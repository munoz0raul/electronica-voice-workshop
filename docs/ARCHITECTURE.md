# Architecture

One **VENTUNO Q** is the server: it runs the Foundries update-server (the
FoundriesFactory replacement), the demo Wi-Fi access point, and a status page.
One **UNO Q** is the end device: it runs the voice→LED/matrix app and the
assets app that carries its model. Both run a Qualcomm Linux (QLI) OSTree image
with the Foundries OTA client built in; the UNO Q's LED matrix is driven by
Zephyr firmware on its on-board STM32U5.

```
            demo Wi-Fi (VENTUNO Q is the AP, demo-server.local)
┌──────────────────────────────────┐              ┌────────────────────────────────────┐
│ VENTUNO Q — server               │              │ UNO Q — end device                   │
│                                   │  register /  │                                      │
│  update-server (systemd)          │◀─ check-in ─▶│  aktualizr-lite ── pulls Targets     │
│    :8080 web UI + REST /v1        │    every 5s  │  fioconfig   ──── applies config     │
│    :8443 device gateway (mTLS)    │              │                                      │
│                                   │   OTA apps   │  webapp-led-mcu-voice  (:8000)       │
│  status-page (compose, :8081)     │─── + config ▶│    └─ mic → Edge Impulse → LEDs      │
│    reads /v1, shows each device's │              │    └─ /dev/ttyHS1 → Zephyr matrix    │
│    current Target + version       │              │  webapp-led-mcu-voice-assets         │
│                                   │              │    └─ drops model in /var/local/     │
│  demo-wifi AP · chrony · mDNS     │              │                                      │
└──────────────────────────────────┘              └────────────────────────────────────┘
```

## What runs where

| Device | Compose apps | Host services (from the image) |
| --- | --- | --- |
| VENTUNO Q | `status-page` | update-server, demo-wifi AP, chrony server, mDNS |
| UNO Q | `webapp-led-mcu-voice`, `webapp-led-mcu-voice-assets` | demo-wifi auto-join, chrony client, `zephyr-loader` |

Each app is a Docker Compose application delivered in a Target and run by
aktualizr-lite. The three apps are built by `build-apps.sh` and staged into
Targets by `tools/stage-target.sh`; see [SETUP.md](SETUP.md).

## The OTA flow

The update-server plays the role a FoundriesFactory plays in a hosted setup,
locally:

1. Each board registers once (`fio-device-register`) and gets device-gateway
   credentials. From then it checks in every **5 s** (`demo-polling`).
2. You build apps, stage a **Target** — an `ostree_repo` (the OS) plus staged
   compose apps — and `fiocli updates upload main <name> <dir>` it. Each upload
   is one Target, tagged `main`, versioned higher than the last.
3. `fiocli updates create-rollout` points a Target at a device **group**. At its
   next check-in, a device whose tag matches pulls the Target.
4. A Target that changes only apps (same `ostree_repo`) is an **app-only**
   update: fast, no reboot. A changed OS hash is an OS update and reboots.

The workshop loop ([WORKSHOP.md](WORKSHOP.md)) is step 2–4 repeated: a new model
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

## The status page

`status-page` is the only app on the VENTUNO Q. It reads the update-server REST
API and shows each device's current Target and version, auto-refreshing. It is
read-only and deliberately minimal — it replaces the upstream dashboard, which
also drove the wall, camera and sound demos that this fork removed.

It needs a Bearer token for `/v1` (env `STATUS_TOKEN`, or `/run/secrets/`); the
token mechanism is the one unverified piece of this fork — see
[the status-page token](SETUP.md#status-page-token). The API it uses:

| Call | Used for |
| --- | --- |
| `GET /v1/devices`, `GET /v1/devices/<uuid>` | the device list, each device's current target and `last-seen` |
| `GET /v1/updates`, `GET /v1/updates/<name>/tuf` | each Target's version, from `targets.json.signed.targets[name].custom.version` |

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

- **USB audio.** The demo image lacks `snd-usb-audio`, so `start.sh` `insmod`s a
  bundled `.ko` that must match the running kernel. The clean fix is to bake
  `kernel-module-snd-usb-audio` into the image —
  [Building the OS](BUILDING-OS.md#usb-audio).
- **MCU port.** `MCU_PORT` defaults to `/dev/ttyHS1`.

The model comes from `webapp-led-mcu-voice-assets`, which carries a baked-in
`deployment.eim`, writes it to `/var/local/assets/deployment.eim`, and restarts
the voice app when the file changes. The voice app prefers that path over its
own baked-in copy. Shipping the model this way means a retrain is an app update,
not an OS change — the whole point of the workshop.

## Host services the image provides

| Host service | Provided by |
| --- | --- |
| Wi-Fi AP (VENTUNO Q) and auto-join (UNO Q) | `demo-wifi` NetworkManager profiles |
| Service discovery (`demo-server.local`) | mDNS |
| Clock sync | chrony: VENTUNO Q serves the demo network, the UNO Q follows it |
| MCU firmware load | `zephyr-loader.service` |
| update-server (VENTUNO Q) | systemd service; state in `/var/local/datadir` |
| Container runtime + OTA | Foundries packagegroups; `demo-polling` sets the 5 s check-in |

See [Building the OS](BUILDING-OS.md) for how these are built into the image.
