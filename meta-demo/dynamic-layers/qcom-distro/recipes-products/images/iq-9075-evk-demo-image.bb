# qcom-multimedia-image brings GStreamer/imsdk, TFLite, libcamera, PipeWire
# and benchmark/test packagegroups — none of which the demo needs.  Use the
# console image as a base and add only the Wayland display, matching the same
# approach as ventuno-q-demo-image.bb.
require recipes-products/images/qcom-console-image.bb

SUMMARY = "IQ-9075 EVK demo image: console base plus Weston"

IMAGE_FEATURES += "weston"

CORE_IMAGE_BASE_INSTALL += " \
    weston \
    weston-init \
"

REQUIRED_DISTRO_FEATURES += "wayland"

# Prevent closed-source userspace packages from being installed.
BAD_RECOMMENDATIONS += " \
    libfastcvdsp-stub1 \
    libfastcvopt1 \
    libvulkan-adreno1 \
"
INCOMPATIBLE_LICENSE = "LICENSE.qcom LICENSE.qcom-2"

# Allow the closed-source firmware packages the QCS9075 (lemans) platform needs.
INCOMPATIBLE_LICENSE_EXCEPTIONS = " \
    camxfirmware-lemans:LICENSE.qcom-2 \
    firmware-qcom-boot-qcs9100:LICENSE.qcom-2 \
"
ERROR_QA:remove = "license-exception"
