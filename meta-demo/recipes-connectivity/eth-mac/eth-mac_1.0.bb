SUMMARY = "Stable Ethernet MAC address for the VENTUNO Q"
DESCRIPTION = "The VENTUNO Q has no factory Ethernet MAC address. A udev rule \
sets one from the emac partition when it is provisioned, otherwise one \
derived from the SoC serial number, so the board keeps its address and DHCP \
lease across reboots and reflashes."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://set-eth-mac \
    file://70-eth-mac.rules \
"
S = "${UNPACKDIR}"
COMPATIBLE_MACHINE = "^ventuno-q$"
PACKAGE_ARCH = "${MACHINE_ARCH}"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    install -D -m 0755 ${UNPACKDIR}/set-eth-mac ${D}${libexecdir}/eth-mac/set-eth-mac
    install -D -m 0644 ${UNPACKDIR}/70-eth-mac.rules \
        ${D}${nonarch_base_libdir}/udev/rules.d/70-eth-mac.rules
}

FILES:${PN} = " \
    ${libexecdir}/eth-mac \
    ${nonarch_base_libdir}/udev/rules.d/70-eth-mac.rules \
"
RDEPENDS:${PN} = "iproute2 coreutils"
