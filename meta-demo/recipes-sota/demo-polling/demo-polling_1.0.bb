SUMMARY = "Short update and config check-in intervals for the demo"
DESCRIPTION = "Sets how often aktualizr-lite checks for updates and fioconfig \
checks for config changes, so the fleet reacts in seconds instead of the \
default 5 minutes, without sending a device config."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://90-demo-polling.toml \
    file://fioconfig.default \
"
S = "${UNPACKDIR}"

inherit allarch

# Seconds between aktualizr-lite update checks
DEMO_POLLING_SEC ?= "5"
# Seconds between fioconfig config checks
DEMO_FIOCONFIG_INTERVAL ?= "5"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    # aktualizr-lite's read-only config fragments, beside 40-hardware-id.toml
    install -d -m 0700 ${D}${libdir}/sota/conf.d
    sed -e 's|@POLLING_SEC@|${DEMO_POLLING_SEC}|g' \
        ${UNPACKDIR}/90-demo-polling.toml > ${D}${libdir}/sota/conf.d/90-demo-polling.toml
    chmod 0644 ${D}${libdir}/sota/conf.d/90-demo-polling.toml

    # Read by fioconfig.service's EnvironmentFile. OSTree ships it as
    # /usr/etc/default/fioconfig and merges it into /etc; an OS update
    # replaces it unless it was edited on the device.
    install -d ${D}${sysconfdir}/default
    sed -e 's|@FIOCONFIG_INTERVAL@|${DEMO_FIOCONFIG_INTERVAL}|g' \
        ${UNPACKDIR}/fioconfig.default > ${D}${sysconfdir}/default/fioconfig
    chmod 0644 ${D}${sysconfdir}/default/fioconfig
}

FILES:${PN} = " \
    ${libdir}/sota/conf.d/90-demo-polling.toml \
    ${sysconfdir}/default/fioconfig \
"
