SUMMARY = "OpenOCD with libgpiod v2 support for MCU RAM loading"
HOMEPAGE = "https://openocd.org/"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=599d2d1ee7fc84c0467b3d19801db870"

SRC_URI = " \
    git://github.com/openocd-org/openocd.git;protocol=https;branch=master;name=openocd \
    git://github.com/msteveb/jimtcl.git;protocol=https;nobranch=1;destsuffix=${BB_GIT_DEFAULT_DESTSUFFIX}/jimtcl;name=jimtcl \
"
SRCREV_FORMAT = "openocd_jimtcl"
SRCREV_openocd = "2075427d1585dc1bc17f75a51df91a1b20b4ad4b"
SRCREV_jimtcl = "d5243a25c488dfe751ef218828f13516e04ea2ba"
PV = "0.12+git"

DEPENDS = "libusb1 libgpiod"
inherit pkgconfig autotools-brokensep gettext

EXTRA_OECONF = "--enable-linuxgpiod --enable-internal-jimtcl --disable-jlink --disable-werror --disable-doxygen-html --datadir=${datadir}/zephyr-tools"

do_configure:prepend() {
    ./bootstrap nosubmodule
}

do_install:append() {
    mv ${D}${bindir}/openocd ${D}${bindir}/openocd-zephyr
}

FILES:${PN} += "${datadir}/zephyr-tools"
