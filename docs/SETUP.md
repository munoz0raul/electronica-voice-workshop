# Setup

From flashed boards to a running voice app. One VENTUNO Q runs the
update-server; one UNO Q is the end device. This covers the host-PC tools,
registering the boards, staging the first Target, and rolling it out.

The boards are assumed **already flashed** with the workshop OS image, and the
VENTUNO Q already booted as the update-server and Wi-Fi AP. To rebuild the
image, see [Building the OS](BUILDING-OS.md).

Run the commands from the repository root. Each phase ends with a **Check**.

## 1. Prerequisites (host PC)

- Docker with buildx, and a `docker-container` builder named `host-builder`
  that can build arm64 images. On an x86 host that needs QEMU emulation:

  ```sh
  docker run --privileged --rm tonistiigi/binfmt --install arm64
  docker buildx create --name host-builder --driver docker-container
  ```

  `BUILDX_BUILDER` names another builder.
- `composectl`, the compose-app tool `stage-app.py` uses, from the
  [composeapp releases](https://github.com/foundriesio/composeapp/releases),
  and Python 3 with PyYAML.
- `fiocli`, the update-server's client, from the
  [update-server releases](https://github.com/foundriesio/update-server/releases).
  Use the build matching the server the VENTUNO Q image runs. `~/bin` on `PATH`.

**Check:** each tool runs.

```sh
docker buildx inspect host-builder | grep Driver   # Driver: docker-container
composectl version
python3 -c 'import yaml'
fiocli --help
```

## 2. The OS repos the apps ride on

An app update carries the OS half too (`ostree_repo`). For an **app-only**
update to install on an already-flashed board, that repo must be the exact OS
the board is running — otherwise aktualizr-lite sees an OS change. Use the
`ostree_repo` from the build that flashed the boards, kept under `build/saved/`:

```
build/saved/ventuno-q-0/ostree_repo     # the VENTUNO Q's OS
build/saved/uno-q-0/ostree_repo          # the UNO Q's OS
```

If you don't have these, rebuild the matching image ([Building the OS](BUILDING-OS.md))
and copy its `ostree_repo` into `build/saved/<board>/`.

## 3. Build the app images

```sh
./build-apps.sh                 # images/<app>.oci.tar for all three apps
```

**Check:** `images/` holds `webapp-led-mcu-voice.oci.tar`,
`webapp-led-mcu-voice-assets.oci.tar` and `status-page.oci.tar`.

## 4. Register the boards

The VENTUNO Q serves the update-server on `:8080`; find its LAN address,
`<ventuno-q-ip>`, in your DHCP leases. The UNO Q is reachable through it
(`<uno-q-ip>` in `ssh root@<ventuno-q-ip> cat /var/lib/demo-wifi/dhcp.leases`).
`root`'s password is `oelinux123`.

fiocli and each board sign in with a code you approve in the web UI at
`http://<ventuno-q-ip>:8080/auth/activate` (login `admin`/`admin`).

```sh
fiocli login demo http://<ventuno-q-ip>:8080
ssh -t root@<ventuno-q-ip> 'fio-device-register -n "$(hostname)"'
ssh -t -J root@<ventuno-q-ip> root@<uno-q-ip> 'fio-device-register -n "$(hostname)"'
```

> The host PC cannot resolve `demo-server.local` the way the boards do on the
> demo Wi-Fi. Replace it with the VENTUNO Q's IP in the registration URL.

**Check:** both devices, each tagged `main`, no group yet.

```sh
fiocli devices list --columns uuid,name,group,tag
```

## 5. Put the boards in groups

Rollouts target groups. Create one for the server and one for the device, then
move each board in (group names are yours; these match the docs):

```sh
fiocli devices update <ventuno-q-uuid> --group demo-server
fiocli devices update <uno-q-uuid> --group demo
```

**Check:** `fiocli devices list --columns name,group` shows the two groups.

## 6. Stage and upload the Targets

`tools/stage-target.sh` assembles a Target directory (OS + staged apps). Upload
each with the tag `main`; the server versions each upload higher than the last.

VENTUNO Q — the status page:

```sh
tools/stage-target.sh ventuno-q build/saved/ventuno-q-0/ostree_repo status-page
fiocli updates upload main ventuno-q-0 ./targets/ventuno-q/
```

UNO Q — the voice app and its model carrier:

```sh
tools/stage-target.sh uno-q build/saved/uno-q-0/ostree_repo \
    webapp-led-mcu-voice webapp-led-mcu-voice-assets
fiocli updates upload main uno-q-voice-0 ./targets/uno-q/
```

**Check:** `fiocli updates list` shows `ventuno-q-0` and `uno-q-voice-0`, tag
`main`.

## 7. Roll out

```sh
fiocli updates create-rollout ventuno-q-0 setup-ventuno setup-ventuno --groups demo-server
fiocli updates create-rollout uno-q-voice-0 setup-uno setup-uno --groups demo
```

The UNO Q's aktualizr-lite picks up the rollout at its next check (polling is
every 5 s in the demo image), pulls the apps and starts them.

**Check:**

- The voice app's UI loads at `http://<uno-q-ip>:8000`; say "select" then a
  colour and the matrix + RGB LEDs react.
- The status page loads at `http://<ventuno-q-ip>:8081` and lists the UNO Q
  with its current Target and version. If it shows a token error, see
  [the status-page token](#status-page-token).

## Status-page token

The status page reads the update-server API, which needs a Bearer token
(`apps/status-page/README.md`). It looks for, in order: env `STATUS_TOKEN`,
`/run/secrets/status-token`, `/run/secrets/dashboard-token`.

The production path is to deliver a token to the VENTUNO Q as a fioconfig
secret named `status-token` (encrypted, mounted at `/run/secrets`). The quick
path for a local run is to set `STATUS_TOKEN` in
`apps/status-page/docker-compose.yml` before staging — but a token committed to
the repo is a secret leak, so don't push it.

**Unverified:** the upstream demo minted this token through a dashboard setup
page that this fork removed. Obtaining a valid update-server token for the
status page has not been re-tested here; confirm your update-server's token
mechanism before the workshop.

## Next

[WORKSHOP.md](WORKSHOP.md) — retrain the model and ship it as a new update.
