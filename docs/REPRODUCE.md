# Reproduce from flashing

The short path: everything it takes to go from two bare boards to a live OTA
app update, the way we ran it. The VENTUNO Q is the update-server and builds the
updates itself (the `poll-and-build` loop); the UNO Q is the end device. On your
laptop you only need a browser — all approvals happen at the server's `:8080`
web UI (`admin`/`admin`).

For the laptop-driven variant (you run `fiocli` and stage Targets by hand) see
[SETUP.md](SETUP.md); for the retrain loop see [WORKSHOP.md](WORKSHOP.md); to
rebuild the OS images see [BUILDING-OS.md](BUILDING-OS.md).

## Artifacts you must have

The repo is public, so the source (both apps, `tools/`, `meta-demo/`) comes from
a `git clone`. Three things are **large binaries kept out of git** — stash them
somewhere your reproducer can download (a GitHub release, a share, a bucket).
Paths below are where they live on the build Mac.

| Artifact | What it is | File | Size |
| --- | --- | --- | --- |
| UNO Q flash image | The OS flashed on the UNO Q (QRB2210 eMMC), with `snd-usb-audio` baked in | `~/qualcomm-flash/uno-q-flash-image.tar.gz` | 428M |
| VENTUNO Q flash image | The OS flashed on the VENTUNO Q (eMMC + SAIL SPI-NOR), update-server + demo Wi-Fi | `~/qualcomm-flash/ventuno-q/ventuno-q-demo-image-ventuno-q.rootfs.qcomflash.tar.gz` | 851M |
| UNO Q `ostree_repo` | The UNO Q OS half, commit `b637abb7`. `poll-and-build` copies it into every Target so updates are **app-only** (no reboot). Must match the flashed UNO Q OS exactly | `~/qualcomm-flash/uno-q-ostree_repo-b637abb7.tgz` | 291M |

> Pack tarballs on macOS with `COPYFILE_DISABLE=1 tar --no-mac-metadata -czf …`.
> A plain `tar czf` adds AppleDouble `._*` sidecars; a stray `refs/heads/._uno-q`
> makes the server reject the upload (`ref "._uno-q" does not contain a valid
> object hash`). The three files above were packed clean.

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
public, so no deploy key is needed.

## 5. Ship an app change (the loop)

Push a change under `apps/` to `main` of the public repo — a retrained model is
just a new `apps/webapp-led-mcu-voice-assets/deployment.eim` (see
[WORKSHOP.md](WORKSHOP.md)). On the next tick `poll-and-build` on the VENTUNO Q:

1. rebuilds the changed app image on the board,
2. stages a UNO Q Target (OS `ostree_repo` + both apps),
3. uploads it to the `:8080` server, and
4. rolls it out to group `demo`.

Watch it:

```sh
ssh root@<ventuno-q-ip> 'journalctl -u poll-and-build.service -f'
```

Expect it to finish with `rolling out … to group demo` and `done`. The UNO Q's
aktualizr-lite picks up the rollout at its next check, pulls only the changed
OCI blobs (a model swap is ~14 MB) and installs them. Because the Target carries
the **same** OS `ostree_repo` as the flashed OS, it is an **app-only** update —
no reboot. On the device:

```sh
ssh -J root@<ventuno-q-ip> root@<uno-q-ip> 'journalctl -u aktualizr-lite -f'
```

`Installation completed; succeeded: 1` and both `webapp-led-mcu-voice*`
containers `Up` means it landed.

## 6. See it

**Fleet view** — `http://<ventuno-q-ip>:8080/devices` (`admin`/`admin`): the
UNO Q's current Target and version.

**The UNO Q web UI** runs on the device's `:8000`, which is on the VENTUNO's
internal network and not directly reachable from your laptop. Tunnel it through
the VENTUNO Q with a jump host + local forward, then open
`http://localhost:8000`:

```sh
ssh -L 8000:<uno-q-ip>:8000 -J root@<ventuno-q-ip> root@<uno-q-ip>
# ours:
ssh -L 8000:10.42.0.211:8000 -J root@192.168.15.99 root@10.42.0.211
```

Keep that session open; `http://localhost:8000` on the Mac is now the UNO Q's
app UI. Say "select" then a colour and watch the matrix + RGB LEDs react.
