# webapp-led-mcu-voice-assets

Delivers the Edge Impulse model to [`webapp-led-mcu-voice`](../webapp-led-mcu-voice).

The model (`deployment.eim`) is **baked into this image**. On start, `start.sh`
copies it into `/var/local/assets/` — the volume the voice app reads — and, if
the model changed, restarts the voice app so it reloads. Then it idles.

This is the workshop's update path: a retrained model is a new `deployment.eim`
in this directory, a rebuilt image, and a new OTA update. No GitHub token, no
device-side polling.

## Retrain and ship a new model

1. Retrain in Edge Impulse and download the Linux (AARCH64) `.eim`.
2. Replace `deployment.eim` in this directory.
3. Rebuild and roll out — see [`docs/WORKSHOP.md`](../../docs/WORKSHOP.md).

## Build

```sh
./build-apps.sh                 # builds images/webapp-led-mcu-voice-assets.oci.tar
```

## Status

The bake-and-copy flow is written but has **not** been rebuilt and run through
OTA on the device yet. The restart-by-PID mechanism needs `pid: host`
(set in the compose file).
