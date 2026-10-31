# Backport of meta-qcom master (a3eaabfd) for wrynose, which doesn't carry
# the edk2-based QRB2210 boot firmware. Remove once wrynose does.
DESCRIPTION = "QCOM NHLOS Firmware for Qualcomm QRB2210 platform"
LICENSE = "LICENSE.qcom-2"
LIC_FILES_CHKSUM = "file://${UNPACKDIR}/${BOOTBINARIES}/LICENSE.qcom-2;md5=165287851294f2fb8ac8cbc5e24b02b0"

FW_ARTIFACTORY = "softwarecenter.qualcomm.com/nexus/generic/product/chip/tech-package/QRB2210_bootbinaries.1.0/qrb2210_bootbinaries.1.0-test-device-public"
BOOTBINARIES = "Agatti_bootbinaries"

SRC_URI = " \
    https://${FW_ARTIFACTORY}/${PV}/${BOOTBINARIES}_${PV}.zip;name=bootbinaries \
    "

QCOM_BOOT_IMG_SUBDIR = "qrb2210"

include recipes-bsp/firmware-boot/firmware-qcom-boot-common.inc
