# meta-qcom (wrynose) doesn't list QCM2290 (Uno Q); the capsule class in this
# layer handles its uefi_dtbs.elf. Remove once wrynose supports it.
COMPATIBLE_MACHINE:qcm2290 = "qcm2290"
