# hostapd 2.11 can receive survey results for channels whose survey list was
# replaced during a regulatory update. The guard is included in 2.12.
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append = "${@' file://0001-AP-Guard-against-survey-list-not-being-initialized.patch' if d.getVar('PV') == '2.11' else ''}"
