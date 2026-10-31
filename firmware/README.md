# Demo firmware

Shared Zephyr application for the UNO Q and VENTUNO Q STM32 MCUs. It drives
the board's 8 × 13 LED matrix and serves the LED matrix service that Linux uses
over `/dev/mcu-console`, and prints a heartbeat once per second. Until Linux
opens a session, the matrix shows a self-test pattern.

- `src/`: application code.
- `prj.conf`: shared Kconfig settings.
- `boards/`: board definitions, application overlays and board-specific settings.

See [Building Zephyr](../docs/BUILDING-ZEPHYR.md) for build commands and board
support, the [MCU interface specification](../docs/lighting-protocol/MCU-INTERFACE.md)
for Linux communication and console access, and
[Linux startup](../docs/BUILDING-OS.md#linux-startup) for firmware packaging and
the loader service.
