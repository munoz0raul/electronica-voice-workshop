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

Everything it takes to go from two bare boards to the live retrain→OTA loop, the
way we ran it. The VENTUNO Q is the update-server and builds the updates itself
(the `poll-and-build` loop); the UNO Q is the end device. On your laptop you only
need a browser and `git` — all approvals happen at the server's `:8080` web UI
(`admin`/`admin`). To rebuild the OS images themselves, see
[BUILDING-OS.md](BUILDING-OS.md); for the matrix firmware, [BUILDING-ZEPHYR.md](BUILDING-ZEPHYR.md).

## Artifacts you must have

The repo is public, so the source (both apps, `tools/`, `meta-demo/`) comes from
a `git clone`. Three things are **large binaries kept out of git**; they are
published as release assets under
[`images-2026-11-01`](https://github.com/munoz0raul/electronica-voice-workshop/releases/tag/images-2026-11-01).

| Artifact | What it is | Download | Size |
| --- | --- | --- | --- |
| UNO Q flash image | The OS flashed on the UNO Q (QRB2210 eMMC), with `snd-usb-audio` baked in | [`uno-q-flash-image.tar.gz`](https://github.com/munoz0raul/electronica-voice-workshop/releases/download/images-2026-11-01/uno-q-flash-image.tar.gz) | 428M |
| VENTUNO Q flash image | The OS flashed on the VENTUNO Q (eMMC + SAIL SPI-NOR), update-server + demo Wi-Fi | [`ventuno-q-demo-image-ventuno-q.rootfs.qcomflash.tar.gz`](https://github.com/munoz0raul/electronica-voice-workshop/releases/download/images-2026-11-01/ventuno-q-demo-image-ventuno-q.rootfs.qcomflash.tar.gz) | 851M |
| UNO Q `ostree_repo` | The UNO Q OS half, commit `b637abb7`. `poll-and-build` copies it into every Target so updates are **app-only** (no reboot). Must match the flashed UNO Q OS exactly | [`uno-q-ostree_repo-b637abb7.tgz`](https://github.com/munoz0raul/electronica-voice-workshop/releases/download/images-2026-11-01/uno-q-ostree_repo-b637abb7.tgz) | 291M |

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

## 1. Flash both boards

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

Boot both. Log in as `root` / `oelinux123`. The VENTUNO Q comes up as the
update-server (`:8080`) and the demo Wi-Fi AP.

Find the IPs: the VENTUNO Q's LAN address `<ventuno-q-ip>` from your DHCP leases
(ours is `192.168.15.99`); the UNO Q's `<uno-q-ip>` from the VENTUNO's own leases
(ours is `10.42.0.211`):

```sh
ssh root@<ventuno-q-ip> cat /var/lib/demo-wifi/dhcp.leases
```

## 2. Register both boards

Each board signs in with a code you approve in the browser at
`http://<ventuno-q-ip>:8080/auth/activate` (`admin`/`admin`):

```sh
ssh -t root@<ventuno-q-ip> 'fio-device-register -n "$(hostname)"'
ssh -t -J root@<ventuno-q-ip> root@<uno-q-ip> 'fio-device-register -n "$(hostname)"'
```

Both appear in **Devices** at `http://<ventuno-q-ip>:8080`, tagged `main`.

## 3. Put the UNO Q in group `demo`

In the `:8080` UI: **Devices → the UNO Q → Manage (labels)**, add a label named
`group` with value `demo`, Save. The VENTUNO Q is server-only and needs no group.
A rollout enrolls whoever is in the group **when it is created**, so do this
before any rollout runs.

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

Transfer `uno-q-ostree_repo-b637abb7.tgz` to the VENTUNO Q and extract it to
`/var/lib/poll-and-build/uno-q-ostree_repo` (the directory must contain
`refs/`, `objects/`, … directly).

The timer starts itself ~3 min after boot, then every 2 min. The repo URL is
public, so no deploy key is needed. On its first run it builds both app images on
the board and ships the first Target to the UNO Q automatically.

## 5. Confirm the app is running

The UNO Q's web UI runs on the device's `:8000`, which is on the VENTUNO's
internal network and not directly reachable from your laptop. Tunnel it through
the VENTUNO Q with a jump host + local forward, then open `http://localhost:8000`:

```sh
ssh -L 8000:<uno-q-ip>:8000 -J root@<ventuno-q-ip> root@<uno-q-ip>
# ours:
ssh -L 8000:10.42.0.211:8000 -J root@192.168.15.99 root@10.42.0.211
```

Keep that session open; `http://localhost:8000` on the Mac is now the UNO Q's app
UI. Say "select" then a colour (`blue green purple red yellow`) and watch the
8×13 matrix + RGB LEDs react. The fleet view at
`http://<ventuno-q-ip>:8080/devices` (`admin`/`admin`) lists the UNO Q with its
current Target and version.

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
2. stages a UNO Q Target (OS `ostree_repo` + both apps),
3. uploads it to the `:8080` server, and
4. rolls it out to group `demo`.

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

- **Target didn't move.** Confirm the UNO Q is in group `demo` and tagged `main`
  (`fiocli devices list --columns name,group,tag` on the VENTUNO Q). A rollout
  only reaches its group, and a device only takes updates carrying its tag. A
  rollout also enrolls whoever is in the group *at creation time*, so the device
  must be in `demo` (step 3) before the rollout runs.
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
`git push` — do the same four steps `poll-and-build` runs. This path needs host
tooling the automated path does not: Docker with a `docker-container` buildx
builder, `composectl` (for `stage-app.py`), Python 3 + PyYAML, and `fiocli`
(matching the server), with the UNO Q's `ostree_repo` under `build/saved/uno-q-0/`.

```sh
./build-apps.sh webapp-led-mcu-voice-assets                 # rebuild the changed app
tools/stage-target.sh uno-q build/saved/uno-q-0/ostree_repo \
    webapp-led-mcu-voice webapp-led-mcu-voice-assets        # stage OS + both apps
fiocli updates upload main uno-q-voice-1 ./targets/uno-q/   # bump the name each time
fiocli updates create-rollout uno-q-voice-1 retrain-1 --groups demo
```

`create-rollout` takes two positionals: the uploaded Target and a name for the
rollout. Send it to one board instead of the group with `--uuids <uno-q-uuid>`.
The staged `ostree_repo` is the same as the flashed OS, so this stays an
app-only update.
