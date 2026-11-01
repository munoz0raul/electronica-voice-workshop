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
./build-apps.sh                 # images/<app>.oci.tar for both apps
```

**Check:** `images/` holds `webapp-led-mcu-voice.oci.tar` and
`webapp-led-mcu-voice-assets.oci.tar`.

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

## 5. Put the UNO Q in a group

Rollouts target groups. The UNO Q is the only device that receives updates, so
put it in a group. The group is a reserved device **label** named `group`; set
it in the update-server web UI at `http://<ventuno-q-ip>:8080` (login
`admin`/`admin`): open **Devices**, pick the UNO Q, open its labels editor
(**Manage**), add a label `group` with value `demo`, and Save. The name is
yours; `demo` matches the rest of these docs.

The VENTUNO Q is the server and receives no app rollout, so it needs no group;
it stays registered and visible in the fleet.

**Check:** `fiocli devices list --columns name,group` shows the UNO Q in `demo`.

## 6. Stage and upload the UNO Q Target

`tools/stage-target.sh` assembles a Target directory (OS + staged apps). Upload
it with the tag `main`; the server versions each upload higher than the last.
Only the UNO Q receives updates; the VENTUNO Q is the server and needs no
Target (its OS is already flashed).

```sh
tools/stage-target.sh uno-q build/saved/uno-q-0/ostree_repo \
    webapp-led-mcu-voice webapp-led-mcu-voice-assets
fiocli updates upload main uno-q-voice-0 ./targets/uno-q/
```

**Check:** `fiocli updates list` shows `uno-q-voice-0`, tag `main`.

## 7. Roll out

```sh
fiocli updates create-rollout uno-q-voice-0 setup-uno --groups demo
```

The two positional arguments are the uploaded Target (`uno-q-voice-0`) and a
name for this rollout (`setup-uno`).

> A rollout enrolls the devices that are in the group when it is created, so the
> UNO Q must already be in `demo` from step 5 before you run this.

The UNO Q's aktualizr-lite picks up the rollout at its next check (polling is
every 5 s in the demo image), pulls the apps and starts them.

**Check:**

- The voice app's UI loads on the UNO Q's `:8000`; say "select" then a colour
  and the matrix + RGB LEDs react. The UNO Q is on the VENTUNO Q's internal
  network, so from your laptop tunnel it through the VENTUNO Q and open
  `http://localhost:8000`:

  ```sh
  ssh -L 8000:<uno-q-ip>:8000 -J root@<ventuno-q-ip> root@<uno-q-ip>
  ```

- The update-server's web UI at `http://<ventuno-q-ip>:8080/devices` (login
  `admin`/`admin`) lists the UNO Q with its current Target and version.

## Next

[WORKSHOP.md](WORKSHOP.md) — retrain the model and ship it as a new update.
