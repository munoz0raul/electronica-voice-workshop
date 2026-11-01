# Electronica Voice Workshop

A self-hosted Foundries.io fleet on Qualcomm Linux (QLI), cut down to one thing:
**managing container apps over the air without FoundriesFactory**. An Arduino
VENTUNO Q runs the Foundries update-server and the demo Wi-Fi; one Arduino UNO Q
runs a voice→LED/matrix app. In the workshop you retrain the keyword model,
rebuild the app that carries it, and push it to the UNO Q as an OTA update — the
same Target / Update / Rollout flow a FoundriesFactory gives you, run locally.

This is a simplified fork of
[foundriesio/workspace-oss-2026-demo](https://github.com/foundriesio/workspace-oss-2026-demo).
The OS and firmware build (the OSTree BSP half) is kept so the images stay
reproducible; the wall, slicer, dashboard, sound-level and multi-step update
demos are removed. What's left is the app-management path.

## The setup

```
┌──────────────────────────────┐        demo Wi-Fi        ┌─────────────────────────────────┐
│ VENTUNO Q  (server)          │ ◀──  OTA + config  ──▶   │ UNO Q  (end device)             │
│  - Foundries update-server   │                          │  - webapp-led-mcu-voice         │
│    (web UI on :8080)         │                          │  - webapp-led-mcu-voice-assets  │
└──────────────────────────────┘                          └─────────────────────────────────┘
```

- **VENTUNO Q** runs the update-server (the FoundriesFactory replacement) and
  runs no managed apps of its own. Watch each device's current Target and
  version in the update-server's web UI at `http://<ventuno-q-ip>:8080/devices`.
- **UNO Q** runs [`webapp-led-mcu-voice`](apps/webapp-led-mcu-voice) — Edge
  Impulse keyword spotting that lights the RGB LEDs and 8×13 matrix — alongside
  [`webapp-led-mcu-voice-assets`](apps/webapp-led-mcu-voice-assets), which
  carries the model and drops it where the voice app reads it.

## The apps

| App | Runs on | Does |
| --- | --- | --- |
| [`webapp-led-mcu-voice`](apps/webapp-led-mcu-voice) | UNO Q | Voice→LED/matrix, web UI on `:8000` |
| [`webapp-led-mcu-voice-assets`](apps/webapp-led-mcu-voice-assets) | UNO Q | Delivers the baked-in Edge Impulse model |

## Getting started

- [docs/REPRODUCE.md](docs/REPRODUCE.md) — the single end-to-end runbook: flash
  both boards, register them, provision the self-building `poll-and-build` loop,
  then run the live retrain→OTA loop. Browser-and-`git`-only on your laptop.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — components and the update flow.
- [docs/README.md](docs/README.md) — documentation index.

The boards are assumed already flashed with the workshop OS image. To rebuild
that image, see [docs/BUILDING-OS.md](docs/BUILDING-OS.md) and
[docs/BUILDING-ZEPHYR.md](docs/BUILDING-ZEPHYR.md).

## License

MIT; see [COPYING.MIT](COPYING.MIT). Files that carry their own
`SPDX-License-Identifier` are licensed as that header states.
