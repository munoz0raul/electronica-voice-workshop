# The main branches' kernel (locks/main.lock.yml). meta-qcom-arduino main
# already carries the VENTUNO Q patches linux-qcom_6.18.bbappend backports,
# so this only adds the demo's own config fragments, shared with that append.
FILESEXTRAPATHS:prepend := "${THISDIR}/linux-qcom-6.18:"

# Optional internet uplink on the VENTUNO Q: a Realtek RTL8822BU USB Wi-Fi
# dongle, so the demo AP keeps the QCA2066 to itself
SRC_URI:append:ventuno-q = " file://ventuno-q-rtw88.cfg"

# Neither board has an RTC battery: keep the kernel from setting the clock
# to the RTC's 1970 at boot so the last saved time is restored instead.
SRC_URI:append = " file://no-rtc-hctosys.cfg"
