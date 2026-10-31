SUMMARY = "RAM-linked Zephyr demo firmware for the board's STM32 MCU"
LICENSE = "MIT & Apache-2.0 & BSD-3-Clause"
LIC_FILES_CHKSUM = " \
    file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302 \
    file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10 \
    file://${COMMON_LICENSE_DIR}/BSD-3-Clause;md5=550794465ba0ec5312d6919e203a55f9 \
"

# files/ is untracked: build-os.sh builds the ELF when it's missing, and
# build-zephyr.sh --copy-to-recipe (or build-os.sh --update-zephyr) updates it.
# BitBake hashes file:// inputs, so replacing an ELF invalidates its task cache.
SRC_URI = "file://zephyr-${MACHINE}.elf"
S = "${UNPACKDIR}"

COMPATIBLE_MACHINE = "^(uno-q|ventuno-q)$"
PACKAGE_ARCH = "${MACHINE_ARCH}"

# This is an ARM MCU executable carried as data by an AArch64 Linux package.
INHIBIT_PACKAGE_STRIP = "1"
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
INSANE_SKIP:${PN} += "arch"

do_install() {
    install -d ${D}${nonarch_libdir}/firmware
    install -m 0644 ${UNPACKDIR}/zephyr-${MACHINE}.elf \
        ${D}${nonarch_libdir}/firmware/zephyr-${MACHINE}.elf
}

FILES:${PN} = "${nonarch_libdir}/firmware/zephyr-${MACHINE}.elf"
