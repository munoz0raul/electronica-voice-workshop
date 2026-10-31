SUMMARY = "fioconfig remote action that shuts the board down"
DESCRIPTION = "Installs the demo-shutdown remote action. The dashboard's \
Shutdown the Demo runs it on the UNO Qs, then on the VENTUNO Q."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://demo-shutdown"
S = "${UNPACKDIR}"

# What each board runs: the UNO Qs halt, the VENTUNO Q powers off
DEMO_SHUTDOWN_COMMAND ?= "${sbindir}/halt"
DEMO_SHUTDOWN_COMMAND:ventuno-q ?= "${sbindir}/shutdown now"

PACKAGE_ARCH = "${MACHINE_ARCH}"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    install -d ${D}${datadir}/fioconfig/actions
    sed -e 's|@COMMAND@|${DEMO_SHUTDOWN_COMMAND}|g' ${UNPACKDIR}/demo-shutdown \
        > ${D}${datadir}/fioconfig/actions/demo-shutdown
    chmod 0755 ${D}${datadir}/fioconfig/actions/demo-shutdown
}

FILES:${PN} = "${datadir}/fioconfig/actions/demo-shutdown"
RDEPENDS:${PN} = "fioconfig systemd"
