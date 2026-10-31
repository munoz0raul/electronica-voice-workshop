SUMMARY = "fioconfig remote action reporting the device's health"
DESCRIPTION = "Installs the demo-health remote action, which prints the \
uptime, the temperatures and the Wi-Fi link as JSON. The dashboard's Health \
button triggers it through fioconfig and reads the captured output from the \
update-server."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://demo-health"
S = "${UNPACKDIR}"

inherit allarch

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    install -D -m 0755 ${UNPACKDIR}/demo-health ${D}${datadir}/fioconfig/actions/demo-health
}

FILES:${PN} = "${datadir}/fioconfig/actions/demo-health"
# demo-sysinfo carries fioconfig's working-directory fix, which every
# captured remote action needs
RDEPENDS:${PN} = "fioconfig demo-sysinfo iw python3-core python3-json"
