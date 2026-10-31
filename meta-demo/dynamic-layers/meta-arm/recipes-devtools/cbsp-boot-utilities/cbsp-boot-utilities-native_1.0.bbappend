# patch-capsule-cert (needed by qcom-capsule.bbclass in this layer) landed
# in 1417f07: a19e5b6, which meta-qcom wrynose pins, plus only that change.
# Remove once wrynose carries it.
SRCREV = "1417f0796fee922723dc1b509e51eb7b72ca2be4"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# The patch is against the repository root; S is uefi_capsule_generation/.
SRC_URI += "file://0001-BinToHex-pad-a-short-trailing-chunk-on-the-right.patch;striplevel=2"
