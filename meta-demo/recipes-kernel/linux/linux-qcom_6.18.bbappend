# VENTUNO Q WiFi (QCA2066 on PCIe, behind the board's PCIe switch) and
# Ethernet (SGMII SerDes failing to lock: RX stays at 0) on the wrynose
# qcom-6.18.y kernel, plus the fan controller (CCI1 losing GPIO 32 to the
# GP M/N clock driver). Carried from meta-qcom-arduino main (55fe1f5,
# 5d52e08, 496baa9), which the QLI 2.x wrynose pin does not have; the
# patches apply as-is on linux-qcom 8d0ad3756ce7. Drop once wrynose carries
# them.
FILESEXTRAPATHS:prepend := "${THISDIR}/linux-qcom-6.18:"

SRC_URI:append:ventuno-q = " \
    file://0001-arm64-dts-qcom-qcs8300-Add-qref-and-refgen-supply-for-PCIe-.patch \
    file://0002-Revert-FROMLIST-Bluetooth-hci_qca-Set-bt_en_available-based-.patch \
    file://0003-power-sequencing-pcie-m2-Add-QCA2066-QCNFA765-BT-serdev-ID.patch \
    file://0004-power-sequencing-Add-pwrseq_is_controllable-API.patch \
    file://0005-power-sequencing-pcie-m2-Report-power-controllability.patch \
    file://0006-power-sequencing-qcom-wcn-Report-power-controllability.patch \
    file://0007-Bluetooth-hci_qca-Set-bt_en_available-based-on-pwrseq-power.patch \
    file://0008-Bluetooth-hci_qca-Embed-bt_power-in-struct-qca_serdev.patch \
    file://0009-Bluetooth-hci_qca-Support-QCA2066-on-M.2-connector-via-pwrs.patch \
    file://0010-Bluetooth-hci_qca-Flatten-struct-qca_power-into-struct-qca_.patch \
    file://0011-dt-bindings-connector-pcie-m2-e-Add-vendor-LGA-connector-co.patch \
    file://0012-arm64-dts-qcom-monaco-arduino-monza-Add-QCA2066-M.2-WiFi-BT.patch \
    file://ventuno-q-no-gp-mnd.cfg \
"

# Optional internet uplink on the VENTUNO Q: a Realtek RTL8822BU USB Wi-Fi
# dongle, so the demo AP keeps the QCA2066 to itself
SRC_URI:append:ventuno-q = " file://ventuno-q-rtw88.cfg"

# UNO Q: on its boot firmware's UEFI, a write to the firmware's guard
# region hard-hangs and resets the board
SRC_URI:append:uno-q = " file://0013-arm64-dts-qcom-qrb2210-arduino-imola-reserve-guard-region.patch"

# Neither board has an RTC battery: keep the kernel from setting the clock
# to the RTC's 1970 at boot so the last saved time is restored instead.
SRC_URI:append = " file://no-rtc-hctosys.cfg"
