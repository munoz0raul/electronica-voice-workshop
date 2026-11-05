<!--
AI NOTE: This is the single canonical runbook for the workshop — from flashed
boards through the live retrain→OTA loop. The recommended flow is automated: the
VENTUNO Q runs `poll-and-build`, which builds, stages, uploads and rolls out
updates itself, so the operator's laptop needs only a browser and `git`. Do NOT
tell users to install host-PC build tooling (docker-buildx, composectl, fiocli)
unless they explicitly want the manual path in the "Doing it from your laptop"
appendix. The older SETUP.md / WORKSHOP.md were folded into this file and removed.
-->

# Reproduce from flashing

Everything it takes to go from bare boards to the live retrain→OTA (Over the Air) loop,
the way we ran it. The VENTUNO Q is the update-server and builds the updates itself
(the `poll-and-build` loop); the UNO Q and IQ-9075 EVK are end devices. On your laptop
you only need a browser and `git` — all approvals happen at the server's `:8080` web UI
(`admin`/`admin`). To rebuild the OS images themselves, see
[BUILDING-OS.md](BUILDING-OS.md); for the matrix firmware, [BUILDING-ZEPHYR.md](BUILDING-ZEPHYR.md).

## Artifacts you must have

The repo is public, so the source (both apps, `tools/`, `meta-demo/`) comes from
a `git clone`. Large binaries are kept out of git; they are
published as release assets under
[`images-2026-11-01`](https://github.com/munoz0raul/electronica-voice-workshop/releases/tag/images-2026-11-01).

| Artifact | What it is | Download | Size |
| --- | --- | --- | --- |
| UNO Q flash image | The OS flashed on the UNO Q (QRB2210 eMMC), with `snd-usb-audio` baked in | [`uno-q-flash-image.tar.gz`](https://github.com/munoz0raul/electronica-voice-workshop/releases/download/images-2026-11-01/uno-q-flash-image.tar.gz) | 428M |
| VENTUNO Q flash image | The OS flashed on the VENTUNO Q (eMMC + SAIL SPI-NOR), update-server + demo Wi-Fi | [`ventuno-q-demo-image-ventuno-q.rootfs.qcomflash.tar.gz`](https://github.com/munoz0raul/electronica-voice-workshop/releases/download/images-2026-11-01/ventuno-q-demo-image-ventuno-q.rootfs.qcomflash.tar.gz) | 851M |
| UNO Q `ostree_repo` | The UNO Q OS half, commit `b637abb7`. `poll-and-build` copies it into every Target so updates are **app-only** (no reboot). Must match the flashed UNO Q OS exactly | [`uno-q-ostree_repo-b637abb7.tgz`](https://github.com/munoz0raul/electronica-voice-workshop/releases/download/images-2026-11-01/uno-q-ostree_repo-b637abb7.tgz) | 291M |
| IQ-9075 EVK flash image | The OS flashed on the IQ-9075 EVK (UFS), Weston desktop with `snd-usb-audio` baked in | [`iq-9075-evk-demo-image-iq-9075-evk.rootfs.qcomflash.tar.gz`](https://github.com/munoz0raul/electronica-voice-workshop/releases/download/images-2026-11-01/iq-9075-evk-demo-image-iq-9075-evk.rootfs.qcomflash.tar.gz) | 832M |
| IQ-9075 EVK `ostree_repo` | The IQ-9075 EVK OS half, commit `452aa48b`. `poll-and-build` copies it into every IQ9 Target so updates are **app-only** (no reboot). Must match the flashed IQ9 OS exactly | [`iq9-ostree_repo-452aa48b.tgz`](https://github.com/munoz0raul/electronica-voice-workshop/releases/download/images-2026-11-01/iq9-ostree_repo-452aa48b.tgz) | 578M |

After downloading, verify against the release's
[`SHA256SUMS`](https://github.com/munoz0raul/electronica-voice-workshop/releases/download/images-2026-11-01/SHA256SUMS):

```sh
shasum -a 256 -c SHA256SUMS
```

> If you ever re-pack these on macOS, use
> `COPYFILE_DISABLE=1 tar --no-mac-metadata -czf …`. A plain `tar czf` adds
> AppleDouble `._*` sidecars; a stray `refs/heads/._uno-q` makes the server
> reject the upload (`ref "._uno-q" does not contain a valid object hash`). The
> published files are packed clean.

The `ostree_repo` must be the **exact** OS on the UNO Q. If you rebuild the UNO Q
image, re-export its `ostree_repo` from the build and re-stash it, or the first
app update looks like an OS change and forces a reboot.

## 1. Flash all boards

Put each board in EDL and flash with `qdl` (details and EDL entry per board in
the `qcom-flash-mac` skill / the board Quick Start Guide). Extract each tarball
first; run from inside the image directory.

**UNO Q** (eMMC):

```sh
qdl --storage emmc prog_firehose_ddr.elf rawprogram0.xml patch0.xml
```

**VENTUNO Q** — SAIL firmware (SPI-NOR) first, then the main image (eMMC):

```sh
cd sail_nor
qdl --storage spinor prog_firehose_ddr.elf rawprogram0.xml patch0.xml
cd ..
qdl --storage emmc prog_firehose_ddr.elf rawprogram0.xml rawprogram1.xml patch0.xml patch1.xml
```

**IQ-9075 EVK** — EDL entry is `SW2-3` (see the Quick Start Guide). SAIL
firmware (SPI-NOR) first, then the main image (UFS):

```sh
cd sail_nor
qdl --storage spinor prog_firehose_ddr.elf rawprogram0.xml patch0.xml
cd ..
qdl --storage ufs prog_firehose_ddr.elf rawprogram*.xml patch*.xml
```

Boot all boards. Log in as `root` / `oelinux123`. The VENTUNO Q comes up as the
update-server (`:8080`) and the demo Wi-Fi AP.

Find the IPs: the VENTUNO Q's LAN address `<ventuno-q-ip>` from your DHCP leases
(ours is `192.168.15.99`); the UNO Q's `<uno-q-ip>` and the IQ-9075 EVK's `<iq9-ip>`
from the VENTUNO's own leases — all three use the demo Wi-Fi (ours: UNO Q `10.42.0.211`,
IQ9 `10.42.0.145`):

```sh
ssh root@<ventuno-q-ip> cat /var/lib/demo-wifi/dhcp.leases   # UNO Q and IQ9 (Wi-Fi)
```

## 2. Register all boards

Each board signs in with a code you approve in the browser at
`http://<ventuno-q-ip>:8080/auth/activate` (`admin`/`admin`):

```sh
ssh -t root@<ventuno-q-ip> 'fio-device-register -n "$(hostname)"'
ssh -t -J root@<ventuno-q-ip> root@<uno-q-ip> 'fio-device-register -n "$(hostname)"'
ssh -t -J root@<ventuno-q-ip> root@<iq9-ip> 'fio-device-register -n "$(hostname)"'
```

All three appear in **Devices** at `http://<ventuno-q-ip>:8080`, tagged `main`.

## 3. Put all boards in group `demo`

In the `:8080` UI: **Devices → the UNO Q → Manage (labels)**, add a label named
`group` with value `demo`, Save. Repeat for the VENTUNO Q (it also runs the voice
app and receives its own OTA updates) and for the IQ-9075 EVK. A rollout enrolls
whoever is in the group **when it is created**, so do this before any rollout runs.

## 4. Provision `poll-and-build` once on the VENTUNO Q

The loop is baked into the VENTUNO Q image; it needs two one-time, on-box steps
(see [the recipe README](../meta-demo/recipes-support/poll-and-build/README.md)
for the full list):

```sh
ssh root@<ventuno-q-ip>
mkdir -p /root/.config
fiocli login demo http://localhost:8080          # approve at :8080 (admin/admin)
# drop the UNO Q ostree_repo in place (matches the flashed UNO Q OS):
#   /var/lib/poll-and-build/uno-q-ostree_repo
```

Download and extract the UNO Q and IQ-9075 EVK ostree repos directly on the
VENTUNO Q (it has internet at this point):

```sh
ssh root@<ventuno-q-ip>
cd /var/lib/poll-and-build

BASE=https://github.com/munoz0raul/electronica-voice-workshop/releases/download/images-2026-11-01

curl -L -o uno-q-ostree_repo-b637abb7.tgz  "$BASE/uno-q-ostree_repo-b637abb7.tgz"
mkdir uno-q-ostree_repo
tar xzf uno-q-ostree_repo-b637abb7.tgz -C uno-q-ostree_repo --strip-components=1

curl -L -o iq9-ostree_repo-452aa48b.tgz "$BASE/iq9-ostree_repo-452aa48b.tgz"
mkdir iq9-ostree_repo
tar xzf iq9-ostree_repo-452aa48b.tgz -C iq9-ostree_repo --strip-components=1
```

> **Clock note:** `chrony-boot-sync.service` sets the clock from `pool.ntp.org`
> once at boot. If the board had no internet at boot the clock will be wrong and
> `curl` will fail with an SSL certificate error. Fix it before downloading:
> ```sh
> systemctl stop chronyd
> chronyd -q -t 30 "pool pool.ntp.org iburst"
> systemctl start chronyd
> ```

The VENTUNO Q's own `ostree_repo` is derived from the running system — no
download artifact needed. Run these once after the first boot:

```sh
cd /var/lib/poll-and-build
ostree --repo=ventuno-q-ostree_repo init --mode=archive
commit=$(ostree --repo=/ostree/repo rev-parse ostree/1/1/0)
ostree --repo=ventuno-q-ostree_repo pull-local /ostree/repo "$commit"
ostree --repo=ventuno-q-ostree_repo refs --create=ventuno-q "$commit"
```

Alternatively, if you rebuilt the IQ9 OS image, derive it from the booted IQ9:

```sh
# On the IQ9:
ssh -J root@<ventuno-q-ip> root@<iq9-ip>
mkdir -p /tmp/iq9-ostree_repo
ostree --repo=/tmp/iq9-ostree_repo init --mode=archive
commit=$(ostree --repo=/ostree/repo rev-parse ostree/1/1/0)
ostree --repo=/tmp/iq9-ostree_repo pull-local /ostree/repo "$commit"
ostree --repo=/tmp/iq9-ostree_repo refs --create=iq-9075-evk "$commit"
tar czf /tmp/iq9-ostree_repo.tgz -C /tmp iq9-ostree_repo
exit

# Transfer to the VENTUNO Q:
scp root@<iq9-ip>:/tmp/iq9-ostree_repo.tgz root@<ventuno-q-ip>:/var/lib/poll-and-build/
ssh root@<ventuno-q-ip> 'cd /var/lib/poll-and-build && tar xzf iq9-ostree_repo.tgz'
```

Verify:
```sh
ssh root@<ventuno-q-ip> 'ostree --repo=/var/lib/poll-and-build/iq9-ostree_repo refs'
# expect: iq-9075-evk
```

The timer starts itself ~3 min after boot, then every 2 min. The repo URL is
public, so no deploy key is needed. On its first run it builds both app images on
the board and ships a Target to each device in the `demo` group automatically.

## 5. Confirm the app is running

**VENTUNO Q** — the app is reachable directly:

```sh
open http://<ventuno-q-ip>:8000
```

Say "select" then a colour (`blue green purple red yellow`) and watch the 4 RGB
LEDs on the board react.

**UNO Q** — the `:8000` UI is on the VENTUNO's internal network, not reachable
directly from your laptop. Tunnel through the VENTUNO Q:

```sh
ssh -L 8000:<uno-q-ip>:8000 -J root@<ventuno-q-ip> root@<uno-q-ip>
# ours:
ssh -L 8000:10.42.0.211:8000 -J root@192.168.15.99 root@10.42.0.211
```

Keep that session open; `http://localhost:8000` is now the UNO Q's app UI.
Say "select" then a colour and watch the 8×13 matrix + sysfs status LEDs react.

**IQ-9075 EVK** — on the demo Wi-Fi subnet (same as the UNO Q), so tunnel through
the VENTUNO Q:

```sh
ssh -L 8001:<iq9-ip>:8000 -J root@<ventuno-q-ip> root@<iq9-ip>
# ours:
ssh -L 8001:10.42.0.145:8000 -J root@192.168.15.99 root@10.42.0.145
```

Keep that session open; `http://localhost:8001` is now the IQ9's app UI. Say
"select" then a colour and watch the web UI update. There is no physical LED,
matrix, or on-board MCU on the IQ9 — that is expected. Voice recognition requires
a USB webcam or mic plugged into the IQ9 (the web UI works without one; the app
logs `Voice runner error: There are no audio devices available` in a loop when no
mic is present, which is harmless).

The fleet view at `http://<ventuno-q-ip>:8080/devices` (`admin`/`admin`) lists
all three boards with their current Targets and versions.

**`dorbell`** ships in the same Targets and comes up on every board at the same
time. It is a face-recognition doorbell with no web UI: it draws a live camera
view on the board's **physical screen** through an OpenCV window and runs face
inference on the NPU (Neural Processing Unit). Confirm it on the board the screen
is attached to — plug in a camera (`/dev/video*`) and a display, and the window
appears on boot. Keyboard keys in that window drive it (`B` toggles CPU/NPU, `G`
enrolls the current face as a guest, `C` clears, `Q` quits). It binds no network
port, so there is nothing to tunnel. Confirm the NPU path from the container log:

```sh
ssh root@<ventuno-q-ip> 'docker logs $(docker ps -q -f name=dorbell) 2>&1 | grep -E "DSP|NPU"'
```

Expect the board's own SoC (System on Chip) tag — `HTP v75, SoC=qcs8275` on the
VENTUNO Q, `HTP v73, SoC=qcs9075` on the IQ-9075 EVK — then `in-process HTP
engine ready` and the matching `*_<tag>.bin` context pair. The image carries both
boards' binaries and `start.sh` selects the pair from the board's HTP (Hexagon
Tensor Processor) version; see [apps/dorbell/README.md](../apps/dorbell/README.md).

The NPU path needs nothing staged beyond the image. The `B`-key CPU fallback is
the one exception: it reads the InsightFace `buffalo_sc` ONNX (Open Neural Network
Exchange) models from `/root/.insightface` on the board, which the compose file
mounts read-only. They are left out of the image, so the CPU backend is available
only on a board where they were pre-staged (copy the directory from another board,
or let the app download them once on a board with internet). The NPU backend is
unaffected when they are absent.

## 6. The workshop loop: retrain the model and watch the new version land

This is the loop you run live. The model is shipped by
`webapp-led-mcu-voice-assets`: it carries a `deployment.eim` and drops it at
`/var/local/assets/deployment.eim`, where the voice app reads it in preference to
its own baked-in copy and restarts to pick it up. So a model update is just a new
build of the **assets** app — the voice app itself doesn't change.

**1. Retrain and export from Edge Impulse.** Retrain the keyword model, then
**Deployment → Linux (AARCH64) → build**. Keep the labels `select` plus the
colours `blue green purple red yellow`, or the matrix/LED mapping won't match.
The detection threshold is `THRESH` in
`apps/webapp-led-mcu-voice/docker-compose.yml` (`0.70`). Make sure the download
is an arm64/AARCH64 `.eim`, not x86.

**2. Drop the new model into the assets app.**

```sh
cp ~/Downloads/<your-model>.eim apps/webapp-led-mcu-voice-assets/deployment.eim
git status    # should show only deployment.eim changed
```

**3. Push to `main` of the public repo.** That is the only trigger — nothing
else to run from your laptop:

```sh
git add apps/ && git commit -m "retrain: new keyword model" && git push
```

**4. The VENTUNO Q ships it itself.** Within ~2 min `poll-and-build`:

1. rebuilds the changed app image on the board,
2. stages a UNO Q Target (`voice-<sha>`), a VENTUNO Q Target (`voice-<sha>-ventuno`), and — if `iq9-ostree_repo` is provisioned — an IQ-9075 EVK Target (`voice-<sha>-iq9`), each with its own OS `ostree_repo` plus all three apps (`webapp-led-mcu-voice`, `webapp-led-mcu-voice-assets`, `dorbell`),
3. uploads all of them to the `:8080` server, and
4. rolls out each to group `demo` (each device applies only the target matching its hardware-id).

Watch it:

```sh
ssh root@<ventuno-q-ip> 'journalctl -u poll-and-build.service -f'
```

Expect it to finish with `rolling out … to group demo` and `done`.

**5. Watch the new version land.** The UNO Q's aktualizr-lite picks up the
rollout at its next check (polling is ~5 s), pulls only the changed OCI blobs (a
model swap is ~14 MB) and installs them. Because the Target carries the **same**
OS `ostree_repo` as the flashed OS, it is an **app-only** update — no reboot.

- **Fleet view** (`http://<ventuno-q-ip>:8080/devices`): the UNO Q's Target and
  version tick up to the new upload.
- **On the device:**

  ```sh
  ssh -J root@<ventuno-q-ip> root@<uno-q-ip> 'journalctl -u aktualizr-lite -f'
  ```

  `Installation completed; succeeded: 1` with the OS hash unchanged means it
  landed. The assets app writes the new `deployment.eim` and restarts the voice
  app, which reloads the model.
- **The app:** back at `http://localhost:8000` (the tunnel from step 5), say
  "select" then a colour and confirm the retrained model reacts.

To follow the model swap on the device directly:

```sh
ssh -J root@<ventuno-q-ip> root@<uno-q-ip> \
    'docker logs -f $(docker ps -q -f name=webapp-led-mcu-voice-assets)'
```

## 7. If an update doesn't land

- **Target didn't move.** Confirm the device is in group `demo` and tagged `main`
  (`fiocli devices list --columns name,group,tag` on the VENTUNO Q). A rollout
  only reaches its group, and a device only takes updates carrying its tag. A
  rollout also enrolls whoever is in the group *at creation time*, so the device
  must be in `demo` (step 3) before the rollout runs.
- **IQ9 gets no target.** Confirm `iq9-ostree_repo` is provisioned on the VENTUNO Q
  (`ls /var/lib/poll-and-build/iq9-ostree_repo/refs/`). Without it `poll-and-build`
  skips the IQ9 target silently. Re-run the provisioning commands from step 4.
- **Target moved, model didn't change.** The assets app only restarts the voice
  app when the `.eim` content differs. Confirm the file actually changed
  (`md5sum apps/webapp-led-mcu-voice-assets/deployment.eim`).
- **Voice app won't recognise words.** Wrong labels or an x86 EIM — redo the
  export. The app logs the model path and labels at startup.
- **No audio at all.** The demo image bakes in `snd-usb-audio`, so a USB mic
  appears as an ALSA card on hotplug. Confirm the card is present
  (`ssh -J root@<ventuno-q-ip> root@<uno-q-ip> arecord -l`). The voice app
  captures through the ALSA `default` PCM, selected by `PA_ALSA_DEVICE` in
  `apps/webapp-led-mcu-voice/docker-compose.yml` (`3`, the resampling `default`
  device — the raw `hw:0,0` is fixed at 44100 Hz and the model needs 16 kHz).
- **poll-and-build upload fails with `ref "._uno-q" …`.** AppleDouble files in
  the provisioned `ostree_repo` (see the artifacts note). Clean them on the
  VENTUNO Q: `find /var/lib/poll-and-build/uno-q-ostree_repo -name '._*' -exec rm -f {} +`.
- **IQ9 voice app logs `Voice runner error: There are no audio devices available`
  in a loop.** No USB mic is plugged into the IQ9. The Flask web UI still serves
  on `:8000`; manual colour selection from the browser works. Connect a USB webcam
  or USB mic to enable voice recognition.
- **`poll-and-build` fails with `composectl rm webapp-led-mcu-voice … exit 1`.**
  This happens when the VENTUNO Q is already running the exact app version being
  staged: `stage-app.py`'s cleanup calls `composectl rm`, which refuses to remove
  blobs referenced by the live app. Workaround: run the IQ9 target manually from
  the VENTUNO Q (the IQ9 has no running app yet, so `composectl rm` never
  triggers there):
  ```sh
  ssh root@<ventuno-q-ip>
  cd /var/lib/poll-and-build
  SHA=$(git -C repo rev-parse --short HEAD)
  tools/stage-target.sh iq-9075-evk iq9-ostree_repo webapp-led-mcu-voice webapp-led-mcu-voice-assets
  fiocli updates upload main "voice-${SHA}-iq9" ./targets/iq-9075-evk/
  fiocli updates create-rollout "voice-${SHA}-iq9" "auto-${SHA}-iq9" --groups demo
  ```
- **One board logs `No Target found for the device; hw ID: <board>` and stays on
  its old Target after a push (group-rollout last-wins).** `poll-and-build` rolls
  out three single-hardware Targets (`voice-<sha>`, `-ventuno`, `-iq9`) to the one
  `demo` group in sequence, and the device-gateway points every device at the
  **most recent** rollout — the `-iq9` one, uploaded last. A device applies only
  the Target whose hardware-id matches it, so the UNO Q and VENTUNO Q find no
  matching Target in the one they were handed and hold their current Target. The
  fix is a per-device rollout that bypasses the group: find each stranded board's
  UUID in the `:8080` **Devices** list (or `fiocli devices list`) and re-point it
  at its own Target:
  ```sh
  ssh root@<ventuno-q-ip>
  fiocli updates create-rollout voice-<sha>-ventuno fix-ventuno-<sha> --uuids <ventuno-uuid>
  fiocli updates create-rollout voice-<sha>         fix-uno-q-<sha>   --uuids <uno-q-uuid>
  ```
  At its next check-in the board picks up its matching Target. (The IQ9, having
  received the last group rollout, already has its correct Target.)
- **`No Target found …` *after deleting Targets* in the `:8080` UI, with
  `aktualizr-lite` logging `TUF metadata check failure: Rollback attempt`.** The
  server generates each device's `targets.json` per tag, versioned to the latest
  matching Target's ordinal + 1. Deleting Targets in the UI makes that version go
  **backwards**; a device that already trusted a higher version rejects every
  fetch as a rollback, falls back to its stale local metadata, and finds no
  current Target in it. The update, image and rollout are all fine — only the TUF
  (The Update Framework) version regressed. Recover the stranded device by
  clearing its cached snapshot/targets/timestamp rows (keeping `root`, the trust
  anchor) so it re-bootstraps and accepts the server's current version:
  ```sh
  ssh -J root@<ventuno-q-ip> root@<device-ip>
  systemctl stop aktualizr-lite
  python3 -c "import sqlite3;d=sqlite3.connect('/var/sota/sql.db');d.execute('delete from meta where repo=0 and meta_type in (1,2,3)');d.commit()"
  systemctl start aktualizr-lite
  ```
  To avoid it: prune only low-ordinal Targets, keeping every one at or above what
  devices have installed; retire a Target by uploading a newer one that supersedes it.

## 8. Reset between runs

To demo the loop again from the original model, restore the baked-in `.eim` and
push:

```sh
git checkout apps/webapp-led-mcu-voice-assets/deployment.eim
git commit -am "reset model" && git push
```

## Doing it from your laptop instead (advanced)

The automated path above is the recommended one. If you'd rather drive updates by
hand — build the app images locally and upload/roll out yourself instead of via a
`git push` — do the same steps `poll-and-build` runs. This path needs host
tooling the automated path does not: Docker with a `docker-container` buildx
builder, `composectl` (for `stage-app.py`), Python 3 + PyYAML, and `fiocli`
(matching the server), with each board's `ostree_repo` under `build/saved/`.

```sh
./build-apps.sh webapp-led-mcu-voice-assets                 # rebuild the changed app

# UNO Q
tools/stage-target.sh uno-q build/saved/uno-q-0/ostree_repo \
    webapp-led-mcu-voice webapp-led-mcu-voice-assets dorbell
fiocli updates upload main voice-1-uno-q ./targets/uno-q/
fiocli updates create-rollout voice-1-uno-q retrain-uno-q-1 --groups demo

# VENTUNO Q
tools/stage-target.sh ventuno-q build/saved/ventuno-q-0/ostree_repo \
    webapp-led-mcu-voice webapp-led-mcu-voice-assets dorbell
fiocli updates upload main voice-1-ventuno ./targets/ventuno-q/
fiocli updates create-rollout voice-1-ventuno retrain-ventuno-1 --groups demo

# IQ-9075 EVK
tools/stage-target.sh iq-9075-evk build/saved/iq9-0/ostree_repo \
    webapp-led-mcu-voice webapp-led-mcu-voice-assets dorbell
fiocli updates upload main voice-1-iq9 ./targets/iq-9075-evk/
fiocli updates create-rollout voice-1-iq9 retrain-iq9-1 --groups demo
```

`create-rollout` takes two positionals: the uploaded Target and a name for the
rollout. Send it to one board instead of the group with `--uuids <device-uuid>`
— which is also how you recover a board stranded by the group-rollout last-wins
race (section 7). The staged `ostree_repo` must match the flashed OS exactly for
the update to be app-only (no reboot).
