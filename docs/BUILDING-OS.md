# Building the OS

Use [build-os.sh](../build-os.sh) to build Qualcomm Linux images for UNO Q and
VENTUNO Q. Run the commands below from the repository root.

## Prerequisites

- A Linux host with Docker or Podman
- [kas-container](https://kas.readthedocs.io/en/latest/userguide/kas-container.html)
  in your `PATH` (`build-os.sh` runs every build through it)
- Plenty of free disk space: a full QLI build needs well over 100 GB

## Building the OS

Run `build-os.sh` with the kas file for your board:

```sh
# Arduino VENTUNO Q
./build-os.sh --kasfile ventuno-q.yml

# Arduino UNO Q
./build-os.sh --kasfile uno-q.yml
```

The OS build packages the selected board's ELF from
`meta-demo/recipes-bsp/zephyr-firmware/files/`, which git doesn't track. When
it's missing, `build-os.sh` builds it first with
[build-zephyr.sh](BUILDING-ZEPHYR.md). To rebuild an existing one:

```sh
./build-os.sh --kasfile uno-q.yml --update-zephyr
```

The Yocto recipes install it as
`/usr/lib/firmware/zephyr-${MACHINE}.elf` and enable `zephyr-loader.service` to
load and start the MCU from SRAM at boot.

The first build fetches every layer and source and takes several hours.
Later builds reuse the downloads and sstate cache and are much faster.

By default everything goes under `build/` in this repository:

| Directory             | Contents                                 |
| --------------------- | ---------------------------------------- |
| `build/work`          | kas checkouts of the layers and the build directory |
| `build/downloads`     | Yocto/OE downloads (`DL_DIR`)            |
| `build/sstate-cache`  | Yocto/OE shared state cache (`SSTATE_DIR`) |

## build-os.sh options

| Option                | Description |
| --------------------- | ----------- |
| `--kasfile <file>`    | **Required.** kas file to build (`uno-q.yml` or `ventuno-q.yml`). |
| `--dl-dir <dir>`      | Use a central downloads directory, for example one shared between both boards or other Yocto builds. |
| `--sstate-dir <dir>`  | Use a central sstate cache directory. Sharing it between builds avoids rebuilding recipes that have not changed. |
| `--target <image>`    | Image to build (default: the kas file's `target`, see [Images](#images)). |
| `--update-zephyr`    | Build the selected board's RAM firmware and copy its ELF into the recipe before running kas. |
| `--action build\|shell` | `build` (default) runs the build; `shell` opens a kas shell in the build environment. |
| `--kas-workdir <dir>` | Where kas checks out the layers and creates the build directory. |
| `--lock <file>` | Lock file pinning the Qualcomm layers (default `locks/qli-2.1.lock.yml`, see [Layer locks](#layer-locks)). |
| `--overlay <file>` | A kas file adding to the build, such as `kas/demo-health.yml` ([Health report](#health-report)). Repeatable; it goes after the board's kas file and before the lock. |
| `--help`              | Show usage. |

For example, to share downloads and sstate between both boards:

```sh
./build-os.sh --kasfile uno-q.yml \
    --dl-dir ~/yocto/downloads \
    --sstate-dir ~/yocto/sstate-cache

./build-os.sh --kasfile ventuno-q.yml \
    --dl-dir ~/yocto/downloads \
    --sstate-dir ~/yocto/sstate-cache
```

## Layer locks

`uno-q.yml` and `ventuno-q.yml` name the Qualcomm layers; a lock file in
`locks/` picks their branches and commits. `build-os.sh` adds it after the
kas file (`kas-container build <kasfile>:<lock>`), so the lock wins.
meta-qcom's own `ci/base.lock.yml` pins oe-core and the other layers for the
chosen meta-qcom commit; meta-foundries stays at `common.yml`'s commit.

| Lock | Qualcomm layers | Kernel | os-release | Firmware capsule |
| --- | --- | --- | --- | --- |
| `qli-2.1.lock.yml` (default) | meta-qcom qli-2.1, meta-qcom-arduino wrynose | linux-qcom 6.18 | 2.1 | 1.2 (the machine's) |
| `qli-2.1.1.lock.yml` | meta-qcom qli-2.1.1: two linux-qcom-6.18 tag updates and a FastRPC fix for VENTUNO Q since 2.1 | linux-qcom 6.18 | 2.1.1 (the lock sets `DISTRO_VERSION`; upstream leaves it at 2.1) | 1.3 |
| `main.lock.yml` | meta-qcom master, meta-qcom-distro and meta-qcom-arduino main, at vetted commits (blacksail) | UNO Q: Arduino's linux-arduino 7.0. VENTUNO Q: linux-qcom-next 7.3, without its board patches | 2.99+snapshot-<revision> | 1.4 |

```sh
./build-os.sh --kasfile uno-q.yml --lock locks/main.lock.yml
```

Each lock after the base raises the capsule version
(`CAPSULE_FW_VERSION:forcevariable`), so updating to it flashes the firmware
too ([Firmware capsule updates](#firmware-capsule-updates)).

To move a lock forward, change its commits (after a good build,
`kas-container lock` writes the exact ones) rather than following a branch,
so a build that worked rebuilds the same way.

## Images

| Board | Default image | Contents |
| --- | --- | --- |
| UNO Q | `core-image-full-cmdline` | Console image |
| VENTUNO Q | `ventuno-q-demo-image` | `qcom-console-image` plus Weston (Wayland) |

`ventuno-q-demo-image` (in `meta-demo/dynamic-layers/qcom-distro/`) replaces
`qcom-multimedia-image`. It drops that image's GStreamer/imsdk, TFLite,
libcamera, PipeWire and benchmark/test packages. Like the multimedia image, it
fails the build if closed-source userspace is pulled in; boot and camera
firmware are the exceptions. Both kas files disable the meta-ai layer
(onnxruntime, onnx, llama-cpp), which nothing in the demo uses.

The `ventuno-q` machine config still installs the Hexagon DSP QAIRT libraries
(`qairt-sdk-hexagon-v75`) whatever the image.

## USB audio

The voice app records from a USB microphone, which needs the `snd-usb-audio`
kernel module. The UNO Q image bakes it in so udev autoloads it on mic hotplug
and an ALSA card appears. In Yocto a loadable kernel module is packaged as
`kernel-module-<name>`; the UNO Q image's `IMAGE_INSTALL` (in `uno-q.yml`) adds:

```
IMAGE_INSTALL:append:uno-q = " kernel-module-snd-usb-audio"
```

Its `snd-usbmidi-lib`/`snd-hwdep`/`snd-rawmidi` dependencies come along as
module RDEPENDS. This relies on the kernel building the module
(`CONFIG_SND_USB_AUDIO=m`); if the config has it off or built-in, adjust the
kernel config fragment first.

Built and flashed here, the app finds the image's ALSA card on start. As a
fallback for an image built without the module, `apps/webapp-led-mcu-voice/start.sh`
side-loads a bundled `.ko` (and its dependencies) from
`apps/webapp-led-mcu-voice/modules/` when no ALSA card is present; that bundled
`.ko` is version-locked to one kernel (`7.0.14-gf2e5cd16ede5-dirty`), so keep it
in step with the image kernel if you rely on the fallback.

## Demo Wi-Fi network

VENTUNO Q boots as a WPA2-PSK (CCMP) access point and every UNO Q joins it
automatically. Both images take the network name and passphrase from one
untracked file:

```text
meta-demo/recipes-connectivity/demo-wifi/files/wifi.conf
```

`build-os.sh` creates it from `wifi.conf.example` with a random 24-hex-digit
passphrase the first time it runs, then reuses it. Build both boards from the
same checkout (or copy the file) so they share the credentials. To rotate the
passphrase, delete `wifi.conf` and rebuild and update **both** images. The
file is gitignored; don't commit it.

| Setting | Default | Notes |
| --- | --- | --- |
| `WIFI_SSID` | `oss2026-demo` | 1–32 characters |
| `WIFI_PSK` | random | 8–63 characters |
| `WIFI_BAND` | `a` | `bg` for 2.4 GHz, `a` for 5 GHz |
| `WIFI_CHANNEL` | `auto` | A channel number pins it. `auto` lets hostapd measure the non-DFS channels (1/6/11, or 36–48 and 149–165) at startup and use the least busy one. It is chosen once per AP start, so pin a channel from an on-site survey if conditions change after setup. |
| `WIFI_ACS_FALLBACK` | `36` (`a`), `6` (`bg`) | With `auto`, the channel the AP starts on if automatic selection fails. hostapd on the QCA2066 sometimes gets no channel survey data and gives up, so the AP service then restarts hostapd on this channel. |
| `WIFI_COUNTRY` | `US` | AP regulatory country (hostapd `country_code`), advertised in beacons |
| `WIFI_AP_ADDRESS` | `10.42.0.1/24` | VENTUNO Q address; UNO Qs get DHCP leases from this subnet |

The `demo-wifi` recipe sets up each machine's side:

- VENTUNO Q: `demo-wifi-ap.service` runs hostapd with
  `/etc/demo-wifi/hostapd.conf` and assigns `WIFI_AP_ADDRESS` to `wlp3s0`.
  NetworkManager leaves that interface unmanaged. `demo-wifi-dhcp.service`
  runs a dnsmasq instance on it, with leases in `/var/lib/demo-wifi`. The AP
  unit keeps dnsmasq running across hostapd restarts. DNS listens on
  `WIFI_AP_ADDRESS` only (`/etc/dnsmasq.d/demo-wifi` keeps the image's
  `dnsmasq.service` off `wlp3s0`), answers `demo-server.local` and fails every
  other name at once.
  The demo network has no internet, and without it each lookup waited about a
  minute on unreachable public servers. For the same reason, both machines
  drop systemd-resolved's fallback DNS servers.
  NetworkManager's own AP mode (wpa_supplicant) stalled every client for a
  beacon interval several times a second on the QCA2066, raising ping times to
  ~75 ms on average and over 200 ms at worst. hostapd gives ~5 ms.
- UNO Q: the `demo-wifi` NetworkManager profile in
  `/usr/lib/NetworkManager/system-connections/`, so OTA updates replace it. It
  retries indefinitely and disables station power saving, so multicast sync
  packets aren't delayed until a DTIM wakeup. A udev rule (`70-wlan-mac.rules`)
  gives `wlan0` the board's factory MAC from the eMMC `wlanaddr` partition
  before NetworkManager brings it up. Arduino's U-Boot normally passes that
  address in the device tree; the edk2 firmware this image boots with does
  not, so without the rule ath10k picks a random MAC, and a new DHCP lease,
  on every boot.

The VENTUNO Q is reachable as `demo-server.local` (`DEMO_WIFI_SERVER_NAME` in
the recipe). `demo-wifi-mdns.service` publishes that name over mDNS for
laptops and phones on the demo network. Neither image has an mDNS resolver,
so both list the name in `/etc/hosts`, pointing at `WIFI_AP_ADDRESS`: the
UNO Qs reach the VENTUNO Q's services by it, and the VENTUNO Q enrolls with its
own update-server by it.

```sh
systemctl status demo-wifi-ap demo-wifi-dhcp   # on VENTUNO Q
iw dev wlp3s0 station dump
nmcli connection show --active                 # on an UNO Q
nmcli device wifi list
```

A changed profile under `/etc/NetworkManager/system-connections/` (for example
from `nmcli connection modify`) overrides the image's copy and survives OTA
updates. Delete it to return to the image's profile.

## Clock

Neither board has a battery-backed RTC, so the kernel doesn't set the clock
from it (`no-rtc-hctosys.cfg`) and the boards keep their own time with chrony
(the `chrony` bbappend):

| Board | At boot | While running |
| --- | --- | --- |
| VENTUNO Q | `chrony-boot-sync.service` sets the clock from internet NTP when there is an uplink; otherwise `chronyd -s` restores the last saved time | Serves its clock to the demo network (`local stratum 8`) |
| UNO Q | `chronyd -s` restores the last saved time | Follows the VENTUNO Q |

`chronyd -s` restores the drift file's modification time. A chronyd with no
time source of its own never rewrites that file, so `chrony-save-time.timer`
touches it every 15 minutes and `chrony-save-time.service` at shutdown. A
board that boots without internet starts at most 15 minutes behind its last
run, or at the time it shut down cleanly; without them the VENTUNO Q started
at its last boot with internet, which can be days old.

```sh
chronyc tracking
ls -l --time-style=full-iso /var/lib/chrony/drift
```

## Ethernet MAC address

The VENTUNO Q has no factory Ethernet MAC. Its device tree has no
`local-mac-address`, the Qualcomm EFI boot path adds none, and the `emac`
partition is blank. Arduino's U-Boot only sets the UNO Q's Wi-Fi and Bluetooth
addresses, and the VENTUNO Q doesn't use it. Without a fix, qcom-ethqos picks a
random address and systemd's `MACAddressPolicy=persistent` replaces it with one
derived from `/etc/machine-id`, so the address and DHCP lease change whenever
the board is reflashed.

The `eth-mac` recipe's udev rule sets the address before NetworkManager brings
`end0` up:

1. The first 6 bytes of the `emac` partition, if they are a valid unicast
   address.
2. Otherwise, a locally administered address from a SHA-256 of the SoC serial
   number (`/sys/devices/soc0/serial_number`) and the interface name. It is
   the same across reboots and reflashes, so the board can have a DHCP
   reservation.

To give a board a specific address, write it as 6 raw bytes:

```sh
printf '\x02\x11\x22\x33\x44\x55' | dd of=/dev/disk/by-partlabel/emac conv=notrunc
```

The flash images contain nothing for `emac`, so a reflash that keeps the
partition layout leaves a provisioned address in place.

## Firmware capsule updates

Both images carry the board's UEFI firmware capsule
(`/usr/lib/firmware/efi/firmware-qcom-capsule.cap`, built by meta-qcom's
`ci/capsule.yml`) and apply it with OS updates through aktualizr-lite's
`fioefi` bootloader mode (`rollback_mode = "fioefi"`, meta-demo `fioefi`, based
on [meta-lmp](https://github.com/foundriesio/meta-lmp)'s):

1. Before installing an OS update, aktualizr-lite compares the new OS's
   `/usr/lib/firmware/version.txt` with the running firmware's version,
   `fioefi_printenv bootfirmware_version`, read from the UEFI ESRT entry for
   the machine's `CAPSULE_GUID`. Both use the ESRT encoding of
   `CAPSULE_FW_VERSION`: `a.b.c.d` is `(c << 16) | d`, so `0.0.1.2` is 65538.
2. If they differ, `fioefi_setenv bootupgrade_available 1` copies the new
   OS's capsule to `\EFI\UpdateCapsule` on the ESP and sets the
   file-capsule-delivery bit in `OsIndications`.
3. The reboot that completes the OS update applies the capsule; UEFI deletes
   it from the ESP. A capsule still there after the reboot was not applied
   (for example, older than the firmware's lowest supported version), and
   fioefi removes it.

To apply a capsule by hand, copy it to the ESP and reboot:

```sh
mkdir -p /boot/EFI/UpdateCapsule
cp /usr/lib/firmware/efi/firmware-qcom-capsule.cap /boot/EFI/UpdateCapsule/
sync && reboot
```

To release new firmware, raise `CAPSULE_FW_VERSION` in the machine's kas file
(only its last two fields count). The resulting firmware version shows in each
board's UEFI ESRT, reported by the `demo-sysinfo` action below.

## Hostname

Every image ships one hostname per machine (`uno-q`, `ventuno-q`). On first
boot, `lmp-auto-hostname` (from meta-lmp) renames the board
`<machine>-<SoC serial>`, using `/sys/devices/soc0/serial_number`: for example
`uno-q-2560466998` or `ventuno-q-2370072472`. It runs before NetworkManager,
adds a `127.0.1.1` entry to `/etc/hosts`, and then disables itself.

Register each board with the update-server under its hostname; it is the name
the update-server lists the device by in its `:8080/devices` view.

## OS, kernel and firmware report

`demo-sysinfo` (meta-demo) installs a fioconfig remote action,
`/usr/share/fioconfig/actions/demo-sysinfo`. fioconfig lists it in the
device's `fio-remote-actions` configuration file. When run, it prints one JSON
object:

| Key | Content |
| --- | --- |
| `os` | `/etc/os-release` (`VERSION` is the QLI release, `BUILD_ID` the build) |
| `kernel` | `release` and `version` (build date) from `uname` |
| `uefi` | Each UEFI ESRT entry: firmware `class`, `version`, `last_attempt_status` |
| `mcu` | Each Zephyr ELF the image loads into the MCU: `file`, `sha256`, the `zephyr` build |
| `model` | The devicetree model |

Run it through the update-server to read a board's OS, kernel, firmware and
MCU state without ssh:

```sh
fiocli devices triggers run <uuid> demo-sysinfo
fiocli devices tests <uuid> <command-id>
```

## Health report

`demo-health` (meta-demo) installs a remote action,
`/usr/share/fioconfig/actions/demo-health`, that prints the uptime, each
thermal zone's temperature and the Wi-Fi link as one JSON object. Run it the
same way as `demo-sysinfo` (`fiocli devices triggers run <uuid> demo-health`).
The VENTUNO Q image always has it; the UNO Q image has it only when built with
`--overlay kas/demo-health.yml`.

## Reset action

`demo-reset` (meta-demo, in both images) installs a remote action,
`/usr/share/fioconfig/actions/demo-reset`
(`fiocli devices triggers run <uuid> demo-reset`). Every Target's TUF metadata
is signed once, at upload, so a device that has taken a later Target rejects an
earlier Target's metadata as a rollback attack — which blocks re-running the
workshop loop from an earlier model. The action stops aktualizr-lite, deletes
its stored snapshot, targets and timestamp metadata (the `meta` table in
`/var/sota/sql.db`) and keeps root, then starts it again. The next check
verifies whatever Target is now assigned against the same root, so an earlier
Target is accepted again. Roll the device back to the earlier Target first,
then run this.

## Shutdown action

`demo-shutdown` (meta-demo, in both images) installs a remote action,
`/usr/share/fioconfig/actions/demo-shutdown`
(`fiocli devices triggers run <uuid> demo-shutdown`), to power a board down over
the air. The UNO Q runs `halt` and VENTUNO Q runs `shutdown now`
(`DEMO_SHUTDOWN_COMMAND`). The action starts the command 5 s later from a
transient systemd timer and returns at once. fioconfig re-runs every handler at
boot, and fioconfig-oneshot skips only a run whose `COMMAND_ID` it has recorded
in `/var/sota/oneshot.demo-shutdown.state.completed`; running it uncaptured
writes that record before the board goes down, so it doesn't halt again on the
next boot. A board only has the action once it runs a Target built with it.

## Memory report

`demo-memory` (meta-demo) installs a second remote action,
`/usr/share/fioconfig/actions/demo-memory`, for finding leaks over long runs.
It prints one JSON object:

| Key | Content |
| --- | --- |
| `meminfo`, `vmstat` | System memory from `/proc/meminfo`, the OOM kill and swap counters |
| `services` | Per OTA service cgroup (aktualizr-lite, fioconfig, fioserver, docker, containerd): `current` and `peak` memory, `anon` (heap) and `file` (page cache) from `memory.stat`, OOM kills, CPU time, and each process's RSS, threads and open files |
| `containers` | The same per Docker container, by name |
| `update_server` | On the VENTUNO Q: established connections on the device gateway (`:8443`), each update's `rollouts.log` size, the size and file count of the per-device directories, free space |
| `journal` | Size of `/var/log/journal` |

A service's `current` memory includes page cache and its child processes
(aktualizr-lite's composectl runs count against aktualizr-lite). A leak shows
as `anon`, threads or open files that keep climbing. `file` grows and
shrinks with the page cache.

`tools/memwatch.sh` runs it on every device through the update-server, with
no ssh, and appends the reports to a JSON Lines file:

```sh
# One sample an hour for six hours
tools/memwatch.sh --samples 7 --interval 3600 --out memwatch.jsonl
```

## UNO Q kernel placement

The UNO Q's Wi-Fi firmware runs on the modem core, which rmtfs starts once the
`qcom_rmtfs_mem` driver maps the reserved region at `0x89b01000` (2 MiB). Only
the device tree reserves that region; the edk2 firmware's memory map reports
it as free. With KASLR, the EFI stub loads the kernel at a random physical
address, and sometimes that covers the region. The reservation then fails and
the board boots without Wi-Fi:

```text
OF: reserved mem: Reserved memory: failed to reserve memory for node 'memory@89b01000': base 0x0000000089b01000, size 2 MiB
qcom_rmtfs_mem 89b01000.memory: failed to remap rmtfs_mem region
```

`rmtfs.service` is then skipped (`ConditionPathExists=/dev/qcom_rmtfs_mem1`),
the modem never powers up, and there is no `wlan0`. `/proc/iomem` shows
`Kernel code` over `89b01000`. On 2026-10-16 one of four UNO Qs hit this after
an OS update.

`uno-q.yml` adds `nokaslr` to the kernel command line. With it, the kernel
loaded at `0x53a00000` and the region was reserved. The image only sets
kernel arguments when it is flashed: an OTA deployment keeps the running
deployment's arguments. On a board flashed without it, add it to the boot
entries on the EFI system partition (`ostree admin kargs edit-in-place`
doesn't handle this layout) and reboot:

```sh
sed -i '/^options / { / nokaslr\b/! s/$/ nokaslr/ }' /boot/loader/entries/ostree-*.conf
```

## Crash dumps

meta-qcom's CI configuration turns on crash dumps
(`qcom_scm.download_mode=1`): after a crash, the boot firmware waits for a
host to collect a memory dump over USB instead of rebooting, and the board
stays down until it is power-cycled. `common.yml` replaces that setting with
`qcom_scm.download_mode=0`, so a crash reboots the board.

Like `nokaslr`, this reaches a board only when it is flashed. On a board
flashed before it, change the boot entries and reboot:

```sh
sed -i 's/qcom_scm.download_mode=1/qcom_scm.download_mode=0/' /boot/loader/entries/ostree-*.conf
```

## Persistent journal

Both images use the `meta-demo` systemd configuration to keep journals across
reboots. A tmpfiles rule links `/var/log/journal` to `/var/lib/demo-journal` on
persistent storage, so the image's RAM-backed `/var/log` does not lose the
journal. The normal journal-flush service transfers early boot messages there.

The journal has a 64 MiB disk budget, 8 MiB file rotation and a 128 MiB
free-space reserve. The early boot RAM journal has a 16 MiB budget. Journald
automatically prunes the oldest archived files as needed; active files can
temporarily exceed these limits. Retention is based on size, because clock
correction after boot can otherwise make new diagnostics appear months old.
The journal synchronizes every 30 seconds, with critical messages synchronized
immediately; an abrupt reset can still lose unsynchronized messages.

The message catalog is rebuilt at each boot so an empty generated index does
not cause `journalctl` catalog lookup errors when `/usr` has an epoch timestamp.

```sh
journalctl --list-boots
journalctl -b -1                 # previous boot
journalctl --disk-usage
findmnt -T /var/log/journal      # should resolve to persistent storage
```

## Linux startup

The `zephyr-firmware` recipe reads the machine-named ELF from its own `files/`
directory and packages it in
`/usr/lib/firmware/zephyr-${MACHINE}.elf`. The `zephyr-loader` recipe installs
and enables `zephyr-loader.service`, its Python loader, a common OpenOCD
Cortex-M33 RAM target script (based on ST's and Arduino's OpenOCD target
scripts), and the selected machine's JSON config in
`/usr/share/zephyr-loader/`. Its `openocd-zephyr` dependency is built from
pinned OpenOCD and JimTcl sources with libgpiod v2 support.

Choose when to update the recipe's binary:

```sh
# Build firmware for development
./build-zephyr.sh --board uno-q

# Build and copy a new RAM ELF into the recipe
./build-zephyr.sh --board uno-q --copy-to-recipe

# Build the OS, building the recipe binary only if it's missing
./build-os.sh --kasfile uno-q.yml

# Update the recipe binary before building the OS
./build-os.sh --kasfile uno-q.yml --update-zephyr
```

Once built, the ELF keeps OS-only builds independent of the Zephyr build
workspace until you update it.

The loader validates the ELF's architecture, load addresses, SRAM footprint,
vector table, initial stack and entry point before requesting any GPIO lines.
It identifies the GPIO controller, resets and halts the MCU, loads and verifies
the SRAM image, sets VTOR/MSP/PC, then starts it.

The STM32H5 on VENTUNO Q needs a different reset sequence. Its boot ROM runs
with debug access closed after any reset, so the reset-vector halt used on
UNO Q never fires. The board also pulls `MCU_BOOT0` (GPIO 47) high, which makes
the ROM start ST's system bootloader. That bootloader leaves a TrustZone setup
behind: secure GPIOs and peripherals, and interrupts the firmware cannot
enable. `ventuno-q.json` therefore sets `boot0_gpio` and `flash_entry_vector`.
The loader holds BOOT0 low so the ROM starts user flash, as Arduino's own
image does. It also sets a hardware breakpoint at the flash firmware's reset
handler before resetting through SYSRESETREQ. The core stops before any flash
code runs, in a clean reset state, and the loader loads SRAM from there.
BOOT0 stays low afterwards. This requires valid firmware in flash, such as
Arduino's factory image; the loader reports an error if the flash reset
vector is invalid.

The OpenOCD script defines no flash banks. A Cortex-M33 debug access port and
the SRAM layout are configured per machine as well as the SWD/reset GPIOs.

| Machine | Reset GPIO | SWCLK GPIO | SWDIO GPIO | CPU debug AP | Initial SRAM region |
| --- | ---: | ---: | ---: | ---: | --- |
| `uno-q` | 38 | 26 | 25 | 0 | `0x20000000`, 768 KiB |
| `ventuno-q` | 78 | 71 | 70 | 1 | `0x20000000`, 256 KiB |

UNO Q's TLMM controller is identified by its kernel label `500000.pinctrl`.
VENTUNO Q selects the unique address-named pinctrl controller with enough
lines for its SWD pins; ambiguity is an error. Its pin assignments come from
page 1 of the [official schematic](https://docs.arduino.cc/resources/schematics/ABX00181-schematics.pdf)
and its CPU access port from ST's
[STM32H5 OpenOCD target](https://github.com/STMicroelectronics/OpenOCD/blob/c8d973bdad9a6fddb51459eda109b3b95d23b57a/tcl/target/stm32h5x.cfg).
The initial VENTUNO image uses SRAM1; further SRAM banks can be described when
the application needs them. The package also installs a machine-specific
`60-mcu-console.rules`. Device naming and access are defined in the
[MCU interface specification](lighting-protocol/MCU-INTERFACE.md#transport-and-ownership).

```sh
systemctl status zephyr-loader.service
journalctl -u zephyr-loader.service
systemctl restart zephyr-loader.service
```

The service is a one-shot loader and remains active after the MCU starts.
Restarting it resets and reloads the MCU from the current rootfs ELF. The MCU
needs loading again after power loss or a reset. No flash programming is part
of this startup path. Direct BitBake builds use the ELF already in the recipe's
`files/` directory.

## Update server

The VENTUNO Q image includes the `update-server` recipe: `fioserver` built
from source at an
[update-server main commit](https://github.com/foundriesio/update-server/commit/0af7868c4356234e953bec004e3078cc12ca4a5a)
after v1.0-rc3 (`SRCREV`), and `fioserver.service`. Its `go.mod` needs Go
1.27.3, so `ventuno-q.yml` adds the meta-lts-mixins `wrynose/go` layer. After
moving `SRCREV`, regenerate the module and license lists with
`bitbake -c update_modules update-server` and set `UPDATE_SERVER_VERSION` to
the new commit's `git describe --tags`. The service runs
`fioserver --datadir /var/local/datadir serve`, with the web UI and REST API
on port 8080 and the device gateway on 8443. See the
[architecture](ARCHITECTURE.md#update-server-host-service) for why it is a
host service rather than a compose app.

The datadir holds the server's PKI, TUF keys and authentication secret.
`fioserver.service` starts only once `certs/root.crt` and `auth/hmac.secret`
exist. On first boot, `fioserver-init.service` creates them, following the
upstream [quick start](https://github.com/foundriesio/update-server/blob/main/docs/quick-start.md):

```sh
mkdir -p /var/local/datadir
fioserver --datadir=/var/local/datadir devserver-init --dnsname demo-server.local
```

That gives a self-signed PKI, TUF root metadata and a web UI login of
`admin`/`admin`. `--dnsname` is the gateway's TLS name, so devices must reach
the server by it. The init service runs only while `certs/root.crt` is
missing, so it never replaces an existing datadir.

| Recipe variable | Default | Purpose |
| --- | --- | --- |
| `UPDATE_SERVER_AUTO_INIT` | `1` | `0` leaves out the init service; provision the datadir by hand or restore a backup |
| `UPDATE_SERVER_DNS_NAME` | `demo-server.local` | The gateway's TLS name |
| `UPDATE_SERVER_DATADIR` | `/var/local/datadir` | Server state |
| `UPDATE_SERVER_API_RATE_LIMIT` | `100` | Token-authenticated API requests per second per client IP, set in a new datadir's `auth/auth-config.json` (the server's default is 20). An IP that exceeds it is blocked for 30 s. On an existing datadir, edit `RateLimits.AttemptsPerSecond` there and restart `fioserver` |

`/var` survives OS updates but not a reflash, and a reflashed VENTUNO Q
initializes a new datadir whose keys don't match the enrolled devices. Keep a
copy of the datadir off the device, and restore it over the new one to keep
the existing fleet:

```sh
# Back up: stop the server so its SQLite database is consistent
ssh root@<ventuno-q> 'systemctl stop fioserver.service &&
    tar -C /var/local -czf - datadir; systemctl start fioserver.service' \
    > update-server-datadir.tgz

# Restore after a reflash, replacing the newly initialized datadir
ssh root@<ventuno-q> 'systemctl stop fioserver.service &&
    rm -rf /var/local/datadir && tar -C /var/local -xzf - &&
    systemctl start fioserver.service' < update-server-datadir.tgz
```

Treat the archive as a secret: it contains the fleet's root keys.

```sh
systemctl status fioserver.service
journalctl -u fioserver.service
```

## Check-in intervals

aktualizr-lite and fioconfig check in every 5 minutes by default. The
`demo-polling` recipe, in both images, shortens that so updates and configs
reach the fleet within seconds:

| File | Setting | Recipe variable |
| --- | --- | --- |
| `/usr/lib/sota/conf.d/90-demo-polling.toml` | `[uptane] polling_sec = 5` | `DEMO_POLLING_SEC` |
| `/etc/default/fioconfig` | `DAEMON_INTERVAL=5` | `DEMO_FIOCONFIG_INTERVAL` |

OSTree ships `/etc/default/fioconfig` as `/usr/etc/default/fioconfig` and
copies it to `/etc` on first boot. An OS update with a new interval replaces
it only if the file hasn't been edited on the device. This 5 s poll is why a
rollout reaches the UNO Q within seconds in the [workshop loop](REPRODUCE.md).
