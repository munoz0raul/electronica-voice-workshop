# Arduino's UNO Q kernel, which meta-qcom-arduino main builds
# (locks/main.lock.yml); the QLI 2.x locks build linux-qcom 6.18 instead.
FILESEXTRAPATHS:prepend := "${THISDIR}/linux-arduino:${THISDIR}/linux-qcom-6.18:"

# On the UNO Q's boot firmware UEFI, a write to the firmware's guard
# region hard-hangs and resets the board
SRC_URI:append = " file://0001-arm64-dts-qcom-qrb2210-arduino-imola-base-reserve-guard-region.patch"

# Neither board has an RTC battery: keep the kernel from setting the clock
# to the RTC's 1970 at boot so the last saved time is restored instead.
SRC_URI:append = " file://no-rtc-hctosys.cfg"

# The Media Carrier with the Waveshare 5" DSI panel as one DTB
# (kas/uno-q-display.yml selects it)
SRC_URI:append:uno-q = " file://0002-arm64-dts-qcom-add-UNO-Q-Media-Carrier-Waveshare-5in-DTB.patch"
