SUMMARY = "docker buildx CLI plugin (prebuilt arm64 binary)"
DESCRIPTION = "The buildx Docker CLI plugin. build-apps.sh needs it to export \
an OCI image layout (docker build --output type=oci): moby's builtin BuildKit \
refuses that export without buildx present. Installed as a system CLI plugin; \
the poll-and-build service creates a docker-container builder with it on first \
run (buildkit is pulled from Docker Hub over the Ethernet uplink)."
HOMEPAGE = "https://github.com/docker/buildx"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

# Prebuilt upstream release binary: there is no buildx recipe in the layers we
# pull, and building it from source would add the Go toolchain for one plugin.
SRC_URI = "https://github.com/docker/buildx/releases/download/v${PV}/buildx-v${PV}.linux-arm64;downloadfilename=docker-buildx"
SRC_URI[sha256sum] = "3b83b3731916ba433feccaaa689fe5bcdc81c641d92c8e6c2ea865dfa141c97a"

# Native arm64 binary; only the VENTUNO Q builds app images.
COMPATIBLE_MACHINE = "^ventuno-q$"

# A stripped, prebuilt Go binary: skip the usual source-build QA.
INHIBIT_PACKAGE_STRIP = "1"
INHIBIT_SYSROOT_STRIP = "1"
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
INSANE_SKIP:${PN} = "already-stripped ldflags"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    # Docker looks here for system-wide CLI plugins.
    install -D -m 0755 ${UNPACKDIR}/docker-buildx \
        ${D}${libexecdir}/docker/cli-plugins/docker-buildx
}

FILES:${PN} = "${libexecdir}/docker/cli-plugins/docker-buildx"
RDEPENDS:${PN} = "docker-moby-cli"
