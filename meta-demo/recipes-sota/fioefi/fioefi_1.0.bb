SUMMARY = "Apply the image's Qualcomm UEFI firmware capsule with OS updates"
DESCRIPTION = "fioefi_printenv and fioefi_setenv for aktualizr-lite's fioefi \
bootloader mode, which this enables. When an OS update carries a capsule \
whose version differs from the running firmware's, aktualizr-lite has fioefi \
stage it on the ESP, and UEFI applies it on the reboot that completes the \
update. Based on meta-lmp's fioefi."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://fioefi.sh.in \
    file://30-fioefi.toml \
"
S = "${UNPACKDIR}"

# CAPSULE_GUID and CAPSULE_FW_VERSION come from the machine's kas file
PACKAGE_ARCH = "${MACHINE_ARCH}"
COMPATIBLE_MACHINE = "^(uno-q|ventuno-q)$"

CAPSULE_FILE = "${VIRTUAL-RUNTIME_qcom-capsule-firmware}.cap"

# The ESRT version of CAPSULE_FW_VERSION: qcom-capsule-tool encodes "a.b.c.d"
# as (c << 16) | d
def fioefi_esrt_version(d):
    parts = (d.getVar('CAPSULE_FW_VERSION') or '').split('.')
    if len(parts) != 4 or not all(p.isdigit() for p in parts):
        bb.fatal("CAPSULE_FW_VERSION must be a.b.c.d, got %r" % d.getVar('CAPSULE_FW_VERSION'))
    return str((int(parts[2]) << 16) | int(parts[3]))

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    sed -e 's|@CAPSULE_GUID@|${CAPSULE_GUID}|' \
        -e 's|@CAPSULE_NAME@|${CAPSULE_FILE}|' \
        ${UNPACKDIR}/fioefi.sh.in > ${WORKDIR}/fioefi
    install -D -m 0755 ${WORKDIR}/fioefi ${D}${bindir}/fioefi
    for name in printenv setenv delenv; do
        ln -sf fioefi ${D}${bindir}/fioefi_$name
    done

    install -d -m 0700 ${D}${libdir}/sota/conf.d
    install -m 0644 ${UNPACKDIR}/30-fioefi.toml ${D}${libdir}/sota/conf.d/30-fioefi.toml

    # The firmware version this OS carries, which aktualizr-lite compares with
    # the running firmware's (fioefi_printenv bootfirmware_version)
    install -d ${D}${nonarch_libdir}/firmware
    echo "bootfirmware_version=${@fioefi_esrt_version(d)}" > ${D}${nonarch_libdir}/firmware/version.txt
}
do_install[vardeps] += "CAPSULE_GUID CAPSULE_FW_VERSION CAPSULE_FILE"

FILES:${PN} = " \
    ${bindir}/fioefi* \
    ${libdir}/sota/conf.d/30-fioefi.toml \
    ${nonarch_libdir}/firmware/version.txt \
"
RDEPENDS:${PN} = "${VIRTUAL-RUNTIME_qcom-capsule-firmware}"
