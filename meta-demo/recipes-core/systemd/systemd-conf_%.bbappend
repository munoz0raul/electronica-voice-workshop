FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += " \
    file://50-demo-journal.conf \
    file://demo-journal.conf \
    file://demo-catalog-update.conf \
    file://demo-journal-flush.conf \
"

do_install:append() {
    install -D -m 0644 ${UNPACKDIR}/50-demo-journal.conf \
        ${D}${systemd_unitdir}/journald.conf.d/50-demo-journal.conf
    install -D -m 0644 ${UNPACKDIR}/demo-journal.conf \
        ${D}${nonarch_libdir}/tmpfiles.d/demo-journal.conf
    install -D -m 0644 ${UNPACKDIR}/demo-catalog-update.conf \
        ${D}${systemd_system_unitdir}/systemd-journal-catalog-update.service.d/demo.conf
    install -D -m 0644 ${UNPACKDIR}/demo-journal-flush.conf \
        ${D}${systemd_system_unitdir}/systemd-journal-flush.service.d/demo.conf
}

FILES:${PN} += " \
    ${nonarch_libdir}/tmpfiles.d/demo-journal.conf \
    ${systemd_system_unitdir}/systemd-journal-catalog-update.service.d/demo.conf \
    ${systemd_system_unitdir}/systemd-journal-flush.service.d/demo.conf \
"
