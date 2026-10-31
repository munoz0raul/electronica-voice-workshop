SUMMARY = "fioconfig remote action that lets a demo reset install an earlier update"
DESCRIPTION = "Installs the demo-reset remote action. It deletes \
aktualizr-lite's stored snapshot, targets and timestamp metadata, keeping \
root, so the device accepts the metadata of the earlier update a reset \
assigns it. The dashboard runs it on each device after a reset's rollouts."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://demo-reset"
S = "${UNPACKDIR}"

inherit allarch

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    install -D -m 0755 ${UNPACKDIR}/demo-reset ${D}${datadir}/fioconfig/actions/demo-reset
}

FILES:${PN} = "${datadir}/fioconfig/actions/demo-reset"
# demo-sysinfo carries fioconfig's working-directory fix, which every
# captured remote action needs
RDEPENDS:${PN} = "fioconfig demo-sysinfo aktualizr-lite python3-core python3-json python3-sqlite3"
