SUMMARY = "Host directory for the dashboard's demo-mode state"
DESCRIPTION = "Creates /var/local/dashboard at boot for the dashboard compose \
app to bind-mount, so its state survives the container being recreated."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://dashboard-data.conf"
S = "${UNPACKDIR}"

inherit allarch

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    install -D -m 0644 ${UNPACKDIR}/dashboard-data.conf ${D}${nonarch_libdir}/tmpfiles.d/dashboard-data.conf
}

FILES:${PN} = "${nonarch_libdir}/tmpfiles.d/dashboard-data.conf"
