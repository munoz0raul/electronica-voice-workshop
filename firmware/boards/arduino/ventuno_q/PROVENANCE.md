# VENTUNO Q board definition

These files originate from [Arduino's Zephyr fork](https://github.com/arduino/zephyr/tree/bdd066a67b7168d6975bb49536b719729d209f90/boards/arduino/ventuno_q),
commit `bdd066a67b7168d6975bb49536b719729d209f90` on
`zephyr-arduino-v4.4.2`, retrieved on 2026-10-13.

They describe the STM32H5F5, its clocks and memory, and the VENTUNO Q peripheral
connections. Copyright and Apache-2.0 notices are preserved; the license is
included in `LICENSE`.

Arduino's USB HS controller/PHY nodes and CDC ACM child are included. Upstream
Zephyr 4.4.2 has no STM32H5E5/H5F5 OTG HS support, so `build-zephyr.sh` applies
`firmware/zephyr-patches/0001-drivers-usb-stm32-add-STM32H5E5-H5F5-OTG-HS-support.patch`,
a port of the fork's controller node, embedded HS PHY driver/binding and
`OTGHS_SEL` clock selector. Drop the patch once upstream carries that support.

The local `board.cmake` keeps the generic STM32CubeProgrammer SWD runner.
Arduino's J-Link and pyOCD entries identify an STM32H563, so those entries are
omitted for this STM32H5F5 board. Hardware flashing and debugging have not been
validated here. `build-zephyr.sh` performs compilation only.

The board definition is provided through `BOARD_ROOT=firmware` when using the
build script. It allows native applications to compile against upstream Zephyr
4.4.2 without using Arduino's sketch loader or changing the Zephyr source URL.
Recheck these files against Arduino's fork when upgrading Zephyr, and remove
the local definition when an appropriate upstream definition becomes available.
