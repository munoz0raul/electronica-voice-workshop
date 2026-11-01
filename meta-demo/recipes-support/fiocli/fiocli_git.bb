SUMMARY = "fiocli: the update-server's command-line client"
DESCRIPTION = "The admin CLI for the Foundries update-server (device, update \
and rollout management). It is cmd/cli in the update-server repo, so it builds \
from the same source and pinned Go modules as the update-server recipe; the \
poll-and-build service uses it to stage and roll out Targets against the local \
server on :8080."
HOMEPAGE = "https://github.com/foundriesio/update-server"
LICENSE = "BSD-3-Clause-Clear"
LIC_FILES_CHKSUM = "file://src/${GO_IMPORT}/LICENSE.txt;md5=626b8c5a0b1760b8d0479a6456a43cad"

# Same source and revision as update-server_git.bb: fiocli and fioserver are
# two commands in one repo. Keep SRCREV in step with update-server.
SRC_URI = " \
    git://github.com/foundriesio/update-server;protocol=https;branch=main;destsuffix=${GO_SRCURI_DESTSUFFIX} \
"
SRCREV = "0af7868c4356234e953bec004e3078cc12ca4a5a"
PV = "1.0~rc3+git"

# Reuse the update-server recipe's generated Go module list (same repo, same
# go.mod). meta-demo is on BBPATH, so require finds it. Rerun "bitbake -c
# update_modules update-server" there after moving SRCREV.
#
# Only the module *fetch* list is reused, not update-server's per-module
# licenses.inc: fiocli builds cmd/cli, whose import closure is a strict subset
# of cmd/server's, so Go never extracts the server-only modules (expirable-cache,
# x/term, echo, ...) into pkg/mod -- their LICENSE files are absent and
# do_populate_lic fails QA on them. fiocli's own license is the repo LICENSE.txt
# (LIC_FILES_CHKSUM above); the full per-module manifest ships with update-server
# in the same image.
require recipes-support/update-server/update-server-go-mods.inc

GO_IMPORT = "github.com/foundriesio/update-server"
GO_INSTALL = "${GO_IMPORT}/cmd/cli"

GO_EXTRA_LDFLAGS += "-X=${GO_IMPORT}/version.Version=v1.0-rc3-24-g0af7868"

# Only the VENTUNO Q runs the server, so only it needs the admin client.
COMPATIBLE_MACHINE = "^ventuno-q$"

inherit go-mod

# go-mod builds cmd/cli as "cli"; install it under the name everything calls it.
do_install() {
    install -D -m 0755 ${B}/${GO_BUILD_BINDIR}/cli ${D}${bindir}/fiocli
}
