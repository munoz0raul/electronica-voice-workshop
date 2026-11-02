#!/bin/bash
# Doorbell OTA entrypoint.  Runs as root inside a privileged container.
#
# Does three things the static docker-compose.yml cannot:
#   1. Finds the board-specific DSP cdsp dir and symlinks it to
#      /usr/lib/dsp/cdsp, where the in-container FastRPC lib probes for the
#      shell + QNN skel.  (Must run as root.)
#   2. Derives DOORBELL_SOC_TAG from the HTP skel version so doorbell.py
#      _detect_soc() selects the correct context binary.
#   3. Drops to the Weston UID (via gosu) so Weston's UID-based XWayland auth
#      allows the cv2/Qt window to draw on the physical screen.  On boards
#      without Weston (no /tmp/.X11-unix/X0), falls back to an Xvfb virtual
#      framebuffer — window is invisible but the web UI on :8000 still works.

set -euo pipefail

# --- DSP skel detection + /usr/lib/dsp/cdsp symlink (needs root) --------------
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

# --- Common env ---------------------------------------------------------------
export HOME=/app
export XDG_CONFIG_HOME=/tmp
export XDG_CACHE_HOME=/tmp
export PYTHONUNBUFFERED=1

# --- Display: Weston Xwayland or Xvfb fallback --------------------------------
# QLI runs Weston.  Weston's bundled Xwayland owns /tmp/.X11-unix/X0 and
# authorises clients by UID match (no .Xauthority cookie).  We detect the
# socket owner and re-exec as that UID using gosu after all root setup above.
#
# Fallback: if Weston is not up, start an Xvfb virtual framebuffer so cv2's
# Qt can initialise.  The doorbell window is invisible; :8000 still works.
if [ -S /tmp/.X11-unix/X0 ]; then
    WESTON_UID=$(stat -c %u /tmp/.X11-unix/X0 2>/dev/null || echo 1000)
    echo "[dorbell] Weston XWayland detected (socket owner uid=${WESTON_UID}); using DISPLAY=:0"
    # Make /app tree readable by the weston uid (installed as root).
    chmod -R a+rX /app 2>/dev/null || true
    # .insightface mount may be root-owned; make writable for CPU first-run download.
    chmod -R a+rwX /app/.insightface 2>/dev/null || true
    export DISPLAY=:0
    export XDG_RUNTIME_DIR=/run/user/${WESTON_UID}
    echo "[dorbell] Starting backend=npu as uid=${WESTON_UID} ..."
    exec gosu "${WESTON_UID}" python3 /app/doorbell.py --backend npu
else
    echo "[dorbell] No Weston display (/tmp/.X11-unix/X0 absent); using Xvfb (web UI on :8000 still works)"
    Xvfb :1 -screen 0 1280x720x24 -nolisten tcp &
    export DISPLAY=:1
    echo "[dorbell] Starting backend=npu ..."
    exec python3 /app/doorbell.py --backend npu
fi
