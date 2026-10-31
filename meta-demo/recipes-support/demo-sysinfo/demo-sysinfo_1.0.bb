SUMMARY = "fioconfig remote action reporting the device's OS, kernel and firmware"
DESCRIPTION = "Installs the demo-sysinfo remote action, which prints \
os-release, the kernel, the UEFI ESRT firmware versions and the MCU \
firmware as JSON. The dashboard triggers it through fioconfig and reads the \
captured output from the update-server."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://demo-sysinfo \
    file://fioconfig-workdir.conf \
"
S = "${UNPACKDIR}"

inherit allarch

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    install -D -m 0755 ${UNPACKDIR}/demo-sysinfo ${D}${datadir}/fioconfig/actions/demo-sysinfo
    install -D -m 0644 ${UNPACKDIR}/fioconfig-workdir.conf \
        ${D}${systemd_system_unitdir}/fioconfig.service.d/50-demo-workdir.conf
}

FILES:${PN} = " \
    ${datadir}/fioconfig/actions/demo-sysinfo \
    ${systemd_system_unitdir}/fioconfig.service.d/50-demo-workdir.conf \
"
RDEPENDS:${PN} = "fioconfig python3-core python3-crypt python3-json"
