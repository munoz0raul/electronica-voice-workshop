#!/bin/bash
# Doorbell OTA entrypoint.  Runs as root inside a privileged container.
#
# Does three things the static docker-compose.yml cannot:
#   1. Finds the board-specific DSP cdsp dir (varies by SoC) and symlinks it
#      to /usr/lib/dsp/cdsp, where the in-container FastRPC lib probes for the
#      shell + QNN skel.  [ -e glob ] does not expand globs in bash; ls|grep is
#      used instead.  See run_doorbell_container_qli.sh NPU note B.
#   2. Derives DOORBELL_SOC_TAG from the HTP skel version number so doorbell.py
#      _detect_soc() selects the correct context binary without needing the
#      device-tree, which is inaccessible inside a Docker container.
#   3. Sets HOME=/app so doorbell.py finds ~/qnn_context (baked in) and
#      ~/.insightface (mounted read-only from the host via the compose volume).

set -euo pipefail

# --- DSP skel detection + /usr/lib/dsp/cdsp symlink --------------------------
DSP_CDSP_DIR=""
DOORBELL_SOC_TAG=""
for d in $(find /usr/share/qcom -type d -path '*/dsp/cdsp' 2>/dev/null); do
    if [ -e "$d/fastrpc_shell_unsigned_3" ] && \
       ls "$d"/libQnnHtpV*Skel.so 2>/dev/null | grep -q .; then
        DSP_CDSP_DIR="$d"
        htp_skel=$(ls "$d"/libQnnHtpV*Skel.so 2>/dev/null | head -1)
        htp_ver=$(basename "$htp_skel" | sed 's/libQnnHtpV\([0-9]*\)Skel\.so/\1/')
        case "$htp_ver" in
            73) DOORBELL_SOC_TAG=qcs9075 ;;
            75) DOORBELL_SOC_TAG=qcs8275 ;;
        esac
        echo "[dorbell] DSP: $DSP_CDSP_DIR (HTP v${htp_ver}, SoC=${DOORBELL_SOC_TAG:-unknown})"
        break
    fi
done

if [ -n "$DSP_CDSP_DIR" ]; then
    mkdir -p /usr/lib/dsp
    ln -sfn "$DSP_CDSP_DIR" /usr/lib/dsp/cdsp
else
    echo "[dorbell] WARNING: no board DSP cdsp dir found; NPU will fall back to CPU" >&2
fi

export DOORBELL_SOC_TAG

# --- Runtime environment ------------------------------------------------------
# HOME=/app: doorbell.py uses expanduser("~/qnn_context") and "~/.insightface".
# qnn_context is baked into /app; .insightface is mounted there by the compose.
export HOME=/app
export XDG_CONFIG_HOME=/tmp
export XDG_CACHE_HOME=/tmp
export PYTHONUNBUFFERED=1

echo "[dorbell] Starting backend=npu ..."
exec python3 /app/doorbell.py --backend npu
