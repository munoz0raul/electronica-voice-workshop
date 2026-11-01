SUMMARY = "Git-driven OTA: poll the workshop repo and stage Targets on the VENTUNO Q"
DESCRIPTION = "A systemd timer that watches the workshop repo over the Ethernet \
uplink and, when an app changes, rebuilds the image(s), stages a UNO Q Target \
(OS + apps) and uploads it to the local update-server -- optionally rolling it \
out to the demo group. A self-hosted, poll-don't-push stand-in for the \
FoundriesFactory CI loop: GitHub is only the trigger, nothing reaches in. \
RDEPENDS pulls the client/build tools the loop needs, so installing this one \
package wires up the whole toolchain."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://poll-and-build.sh \
    file://poll-and-build.service \
    file://poll-and-build.timer \
    file://poll-and-build.default \
"
S = "${UNPACKDIR}"

# The loop needs git (fetch), buildx (build-apps.sh OCI export), composectl +
# python3-pyyaml (stage-app.py) and fiocli (upload/rollout). docker itself is
# already in the image via packagegroup-foundries-docker.
RDEPENDS:${PN} = " \
    bash git curl jq \
    python3-core python3-pyyaml \
    composectl fiocli docker-buildx \
"

# Only the VENTUNO Q runs the update-server and this loop.
COMPATIBLE_MACHINE = "^ventuno-q$"

# How often the timer re-checks the repo (cheap: the service only builds on a
# real apps/ change)
POLL_INTERVAL ?= "2min"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

inherit systemd
SYSTEMD_SERVICE:${PN} = "poll-and-build.timer"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -D -m 0755 ${UNPACKDIR}/poll-and-build.sh ${D}${bindir}/poll-and-build

    install -d ${D}${sysconfdir}/default
    install -m 0644 ${UNPACKDIR}/poll-and-build.default ${D}${sysconfdir}/default/poll-and-build

    install -d ${D}${systemd_system_unitdir}
    sed -e 's|@BINDIR@|${bindir}|g' \
        -e 's|@SYSCONFDIR@|${sysconfdir}|g' \
        ${UNPACKDIR}/poll-and-build.service > ${D}${systemd_system_unitdir}/poll-and-build.service
    sed -e 's|@INTERVAL@|${POLL_INTERVAL}|g' \
        ${UNPACKDIR}/poll-and-build.timer > ${D}${systemd_system_unitdir}/poll-and-build.timer
}

FILES:${PN} = " \
    ${bindir}/poll-and-build \
    ${sysconfdir}/default/poll-and-build \
    ${systemd_system_unitdir}/poll-and-build.service \
    ${systemd_system_unitdir}/poll-and-build.timer \
"

# Keep device edits to the config across OS updates.
CONFFILES:${PN} = "${sysconfdir}/default/poll-and-build"
