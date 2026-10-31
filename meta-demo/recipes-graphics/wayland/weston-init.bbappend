FILESEXTRAPATHS:prepend := "${THISDIR}/weston-init:"

SRC_URI += "file://weston-vt.conf"

do_install:append() {
    install -D -m 0644 ${UNPACKDIR}/weston-vt.conf \
        ${D}${systemd_system_unitdir}/weston.service.d/weston-vt.conf
}

FILES:${PN} += "${systemd_system_unitdir}/weston.service.d/weston-vt.conf"
RDEPENDS:${PN} += "kbd"
