# oe-core wrynose builds pylibfdt v1.7.2 with SWIG 4.4, so getprop() on a
# missing property raises TypeError instead of FdtException. That stops
# qcom-capsule-tool patch-capsule-cert's DTB walk at the root node, and it
# never finds QcCapsuleRootCert. Fixed in dtc 1.8.0, which the main build's
# oe-core has, so the patch applies to 1.7 only.
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += "${@'file://0001-pylibfdt-libfdt.i-fix-backwards-compatibility-of-return-values.patch' if d.getVar('PV').startswith('1.7.') else ''}"
