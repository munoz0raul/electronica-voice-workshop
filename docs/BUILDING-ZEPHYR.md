# Building Zephyr firmware

Use [build-zephyr.sh](../build-zephyr.sh) for the STM32 firmware. Run the
commands below from the repository root and select your board:

```sh
./build-zephyr.sh --board uno-q
./build-zephyr.sh --board ventuno-q
```

The script defaults to `uno-q` and builds the shared application in
[`firmware/`](../firmware/README.md): the LED matrix driver (its scan follows
`loader/matrix.inc` in Arduino's
[ArduinoCore-zephyr](https://github.com/arduino/ArduinoCore-zephyr)), the matrix service
Linux uses over `/dev/mcu-console`, and a once-per-second heartbeat in the
console output. The default build executes from SRAM (`--mode ram`);
`--mode flash` produces a flash-linked image for explicit programming. Both boards use Zephyr **4.4.2** and a prebuilt
[Embedded Containers ARM image](https://github.com/embeddedcontainers/zephyr)
with Zephyr SDK **1.0.1**. The image is pinned by digest and pulled automatically
on first use. Docker is the only host build dependency; Python, west, CMake and
the ARM compiler run inside the container.

The script fetches Zephyr and its CMSIS/STM32 modules into
`build/zephyr/work/`, stores Python dependencies in `build/zephyr/venv/`, and
writes `zephyr.elf`, `zephyr.bin` and `zephyr.hex` under
`build/zephyr/output/<board>/<mode>/zephyr/`. To update the binary used by Yocto,
run `./build-zephyr.sh --board <board> --copy-to-recipe`. This copies the RAM ELF
to `meta-demo/recipes-bsp/zephyr-firmware/files/zephyr-<board>.elf`, which git
doesn't track; `build-os.sh` runs this itself when that file is missing.
The boards share downloaded dependencies
and use separate build output. Later builds reuse the workspace and output.

| Selection | Zephyr target | Board definition |
| --- | --- | --- |
| `uno-q` | `arduino_uno_q/stm32u585xx` | Included in upstream Zephyr |
| `ventuno-q` | `arduino_ventuno_q/stm32h5f5xx` | Arduino's definition from [Arduino's Zephyr fork](https://github.com/arduino/zephyr), vendored under `firmware/boards/` |

Upstream Zephyr 4.4.2 supports the VENTUNO Q's STM32H5F5 SoC but does not include
the board definition. We carry Arduino's board files separately so both boards
can build with the same upstream Zephyr release. The source revision and local
changes are recorded in
[VENTUNO Q board provenance](../firmware/boards/arduino/ventuno_q/PROVENANCE.md).

Upstream 4.4.2 also lacks the STM32H5F5's USB HS support. `build-zephyr.sh`
applies the patches in `firmware/zephyr-patches/` to its Zephyr checkout. That
directory currently holds a port of the OTG HS controller node, embedded HS
PHY driver and clock selector from Arduino's Zephyr fork. The script repatches a clean tree whenever
the Zephyr release or the patch set changes.

```sh
# Open a shell with west and the SDK configured
./build-zephyr.sh --action shell

# Build another upstream sample
./build-zephyr.sh --source samples/hello_world

# Build our firmware with additional CMake settings
./build-zephyr.sh --board ventuno-q -- -DCONFIG_LOG=y

# Reconfigure and rebuild from scratch
./build-zephyr.sh --pristine always

# Explicitly update the ELF used by the Yocto recipe
./build-zephyr.sh --board uno-q --copy-to-recipe

# Build a flash-linked image separately from the deployed RAM image
./build-zephyr.sh --board uno-q --mode flash
```

## build-zephyr.sh options

| Option | Description |
| --- | --- |
| `--board <board>` | `uno-q` (default), `ventuno-q`, or a full Zephyr target. |
| `--mode ram\|flash` | SRAM execution (default) or a flash-linked image. |
| `--copy-to-recipe` | Copy the completed RAM ELF into the selected board's recipe input file; requires a build for UNO Q or VENTUNO Q. |
| `--action build\|shell` | Build firmware (default) or open the configured container shell. |
| `--source <directory>` | Build an upstream sample or another local application (default: `firmware/`). |
| `--builddir <directory>` | Directory for sources, Python dependencies and output (default: `build/zephyr/`). |
| `--image <image>` | Override the prebuilt container image. |
| `--pristine auto\|always\|never` | Control when build output is recreated (default: `auto`). |
| `--help` | Show usage. |
| `-- <CMake arguments>` | Pass additional CMake settings to the build. |

`--builddir` selects an alternative build directory, `--board` also accepts a
full Zephyr target, `--source` accepts another local application, and `--image`
selects another prebuilt environment. The script adds `firmware/` to
`BOARD_ROOT` even when building an upstream sample or another application.
To upgrade Zephyr,
update `ZEPHYR_VERSION` near the top of `build-zephyr.sh`, or override it in the
environment (`ZEPHYR_VERSION=4.4.2 ./build-zephyr.sh`). If the release recommends
a different SDK, update `ZEPHYR_IMAGE` to a corresponding image and digest.
The module revisions come from the selected Zephyr release's west manifest.
The fetched modules cover these STM32 targets; applications needing additional
modules must extend the script's manifest allowlist.

The native RAM firmware is loaded through SWD and replaces the running MCU
application until its next reset. It is reloaded by Linux at startup. A
flash-linked image replaces the Arduino sketch loader when programmed. The
[Zephyr UNO Q documentation](https://docs.zephyrproject.org/latest/boards/arduino/uno_q/doc/index.html)
covers debugging through the board's Linux-side OpenOCD/ADB interface and
restoring the sketch loader. Our image uses a source-built OpenOCD and the
machine configs in `meta-demo/recipes-bsp/zephyr-loader/files/`.
See [Linux startup](BUILDING-OS.md#linux-startup) for loader service details
and the [MCU interface specification](lighting-protocol/MCU-INTERFACE.md) for
the link and MCU output. RAM loading and the loader service have been tested
on both boards.

## Firmware sources

The shared application lives in [`firmware/`](../firmware/README.md):

- `src/`: application code.
- `prj.conf`: shared Kconfig settings.
- `boards/`: board definitions, application overlays and board-specific settings.

## LED matrix driver and MCU interface

`firmware/src/matrix.c` drives each board's 8 × 13 charlieplexed LED matrix.
The [MCU interface specification](lighting-protocol/MCU-INTERFACE.md) defines
transport and ownership, commands, bitmap layout and orientation, scheduled
rendering, diagnostics and validation.

At boot, the self-test lights the whole panel, then an "L" marking pixel
(0, 0) for three seconds, then sweeps a vertical bar one column per
`CONFIG_DEMO_BAR_PERIOD_MS` (default 1000). For example,
`./build-zephyr.sh --board uno-q -- -DCONFIG_DEMO_BAR_PERIOD_MS=50` checks
20 frames per second; 50 ms renders cleanly on both boards.

## References

- [Arduino UNO Q user manual](https://docs.arduino.cc/tutorials/uno-q/user-manual/)
- [Arduino Zephyr core build instructions](https://github.com/arduino/ArduinoCore-zephyr#-setup-a-zephyr-build-environment)
- [Zephyr getting started](https://docs.zephyrproject.org/latest/develop/getting_started/index.html)
- [Zephyr's container guidance](https://github.com/zephyrproject-rtos/docker-image)
