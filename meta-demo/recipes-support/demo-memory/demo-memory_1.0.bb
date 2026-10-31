SUMMARY = "fioconfig remote action reporting the device's memory use"
DESCRIPTION = "Installs the demo-memory remote action, which prints system \
memory, each OTA service's and container's cgroup memory (anon versus page \
cache), per-process RSS, threads and open files, and on the update-server \
host its gateway connections and log growth, as JSON. For leak hunting over \
long runs."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://demo-memory"
S = "${UNPACKDIR}"

inherit allarch

# Where the update-server keeps its state, on the host that runs it
UPDATE_SERVER_DATADIR ?= "${localstatedir}/local/datadir"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    install -D -m 0755 ${UNPACKDIR}/demo-memory ${D}${datadir}/fioconfig/actions/demo-memory
    sed -i -e 's|@DATADIR@|${UPDATE_SERVER_DATADIR}|g' ${D}${datadir}/fioconfig/actions/demo-memory
}

FILES:${PN} = "${datadir}/fioconfig/actions/demo-memory"
# demo-sysinfo installs the fioconfig drop-in that runs actions from /tmp
RDEPENDS:${PN} = "fioconfig demo-sysinfo python3-core python3-json"
