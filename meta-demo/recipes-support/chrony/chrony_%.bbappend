# Demo time sync: VENTUNO Q serves its clock on the demo Wi-Fi network and
# the UNO Qs follow it (lighting PoC release-skew measurements depend on it).
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://timesyncd-chrony.conf file://chronyd.default \
    file://chrony-save-time.service file://chrony-save-time-tick.service \
    file://chrony-save-time.timer"
# Keep the time chronyd -s restores at boot current (chrony-save-time.service)
SYSTEMD_SERVICE:${PN}:append = " chrony-save-time.service chrony-save-time.timer"
SRC_URI:append:ventuno-q = " file://chrony-boot-sync.service"
SYSTEMD_SERVICE:${PN}:append:ventuno-q = " chrony-boot-sync.service"
PACKAGE_ARCH = "${MACHINE_ARCH}"

do_install:append() {
    # chronyd replaces systemd-timesyncd; skip timesyncd however it was enabled
    install -d ${D}${systemd_system_unitdir}/systemd-timesyncd.service.d
    install -m 0644 ${UNPACKDIR}/timesyncd-chrony.conf \
        ${D}${systemd_system_unitdir}/systemd-timesyncd.service.d/chrony.conf
    install -D -m 0644 ${UNPACKDIR}/chronyd.default ${D}${sysconfdir}/default/chronyd
    for unit in chrony-save-time.service chrony-save-time-tick.service chrony-save-time.timer; do
        install -m 0644 ${UNPACKDIR}/$unit ${D}${systemd_system_unitdir}/
    done
}

do_install:append:ventuno-q() {
    install -m 0644 ${UNPACKDIR}/chrony-boot-sync.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} += " \
    ${systemd_system_unitdir}/systemd-timesyncd.service.d \
    ${systemd_system_unitdir}/chrony-save-time-tick.service \
"
