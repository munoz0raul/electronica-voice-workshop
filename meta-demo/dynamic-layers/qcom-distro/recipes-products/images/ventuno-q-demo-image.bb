# qcom-multimedia-image is the only Qualcomm image with Weston, but it also
# brings GStreamer/imsdk (whose ONNX plugin pulls onnxruntime), TFLite,
# libcamera, PipeWire and the benchmark/test packagegroups. Start from the
# console image and add only the Wayland display.
require recipes-products/images/qcom-console-image.bb

SUMMARY = "VENTUNO Q demo image: console base plus Weston"

IMAGE_FEATURES += "weston"

CORE_IMAGE_BASE_INSTALL += " \
    weston \
    weston-init \
"

REQUIRED_DISTRO_FEATURES += "wayland"

# Same guard as qcom-multimedia-image.bbappend: keep the open GPU stack and
# fail the build if closed-source userspace gets pulled in. The exceptions are
# the VENTUNO Q (monaco/qcs8300) entries from that bbappend's firmware list;
# camxfirmware-monaco is built by camxfirmware-lemans and depends on it.
BAD_RECOMMENDATIONS += " \
    libfastcvdsp-stub1 \
    libfastcvopt1 \
    libvulkan-adreno1 \
"
INCOMPATIBLE_LICENSE = "LICENSE.qcom LICENSE.qcom-2"
INCOMPATIBLE_LICENSE_EXCEPTIONS = " \
    camxfirmware-lemans:LICENSE.qcom-2 \
    camxfirmware-monaco:LICENSE.qcom-2 \
    firmware-qcom-boot-qcs8300:LICENSE.qcom-2 \
"
ERROR_QA:remove = "license-exception"
