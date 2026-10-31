require firmware-qcom-boot-qrb2210.inc

SRC_URI[bootbinaries.sha256sum] = "26a8681834363cb8bc9e8149db27388406daf22af15d3b43c9649e180afb47f2"

# The release's own UEFI: a separately built one can't be redistributed,
# and the kernel's device tree reserves the region whose writes hard-hang
# the board (meta-demo linux-qcom and linux-arduino appends)
