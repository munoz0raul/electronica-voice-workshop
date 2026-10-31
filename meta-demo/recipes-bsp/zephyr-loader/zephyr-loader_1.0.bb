SUMMARY = "Load machine-specific Zephyr firmware into STM32 SRAM at boot"
LICENSE = "MIT & GPL-2.0-or-later"
LIC_FILES_CHKSUM = " \
    file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302 \
    file://${COMMON_LICENSE_DIR}/GPL-2.0-or-later;md5=fed54355545ffd980b814dab4a3b312c \
"

SRC_URI = " \
    file://zephyr-loader \
    file://zephyr-loader.service \
    file://${MACHINE}.json \
    file://${MACHINE}-mcu-console.rules \
    file://stm32-m33-ram.cfg \
"
S = "${UNPACKDIR}"
COMPATIBLE_MACHINE = "^(uno-q|ventuno-q)$"
PACKAGE_ARCH = "${MACHINE_ARCH}"

inherit systemd
SYSTEMD_SERVICE:${PN} = "zephyr-loader.service"
SYSTEMD_AUTO_ENABLE = "enable"
RDEPENDS:${PN} = "python3-core python3-json python3-fcntl python3-io openocd-zephyr zephyr-firmware"

do_install() {
    install -d ${D}${libexecdir} ${D}${datadir}/zephyr-loader ${D}${systemd_system_unitdir}
    install -m 0755 ${UNPACKDIR}/zephyr-loader ${D}${libexecdir}/zephyr-loader
    install -m 0644 ${UNPACKDIR}/${MACHINE}.json ${D}${datadir}/zephyr-loader/${MACHINE}.json
    install -m 0644 ${UNPACKDIR}/stm32-m33-ram.cfg ${D}${datadir}/zephyr-loader/stm32-m33-ram.cfg
    sed -e 's|@MACHINE@|${MACHINE}|g' \
        -e 's|@FIRMWAREDIR@|${nonarch_libdir}/firmware|g' \
        -e 's|@LIBEXECDIR@|${libexecdir}|g' \
        -e 's|@DATADIR@|${datadir}|g' \
        ${UNPACKDIR}/zephyr-loader.service > ${D}${systemd_system_unitdir}/zephyr-loader.service
    # /dev/mcu-console: the MCU console on either board (UART or USB CDC ACM)
    install -D -m 0644 ${UNPACKDIR}/${MACHINE}-mcu-console.rules \
        ${D}${nonarch_base_libdir}/udev/rules.d/60-mcu-console.rules
}

FILES:${PN} += " \
    ${datadir}/zephyr-loader \
    ${systemd_system_unitdir}/zephyr-loader.service \
    ${nonarch_base_libdir}/udev/rules.d/60-mcu-console.rules \
"
