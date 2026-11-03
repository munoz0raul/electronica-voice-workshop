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
#      allows the OpenCV highgui window to draw on the physical screen.  On
#      boards without Weston (no /tmp/.X11-unix/X0), falls back to an Xvfb
#      virtual framebuffer so OpenCV initialises; the view then appears nowhere.
#      doorbell.py serves no network port — the on-screen window is the only UI.

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
# Fallback: if Weston is not up, start an Xvfb virtual framebuffer so OpenCV
# highgui can initialise.  The view is confined to that framebuffer and appears
# nowhere; all three demo boards run Weston, so this path is unused in practice.
if [ -S /tmp/.X11-unix/X0 ]; then
    WESTON_UID=$(stat -c %u /tmp/.X11-unix/X0 2>/dev/null || echo 1000)
    echo "[dorbell] Weston XWayland detected (socket owner uid=${WESTON_UID}); using DISPLAY=:0"
    # Make /app tree readable by the weston uid (installed as root).
    chmod -R a+rX /app 2>/dev/null || true
    # .insightface mount may be root-owned; make writable for CPU first-run download.
    chmod -R a+rwX /app/.insightface 2>/dev/null || true

    # --- DSP/camera group access for the dropped uid -------------------------
    # Dropping to uid 1000 for the Weston display loses root's blanket device
    # access.  The HTP DSP session needs to open /dev/fastrpc-cdsp and
    # /dev/dma_heap/system; without membership in their owning groups the
    # session fails with status=0x72 ("Failed to load skel 1002").  The
    # privileged container exposes these nodes with their HOST gids, so we add
    # the target user to a group matching each node's gid (creating it if the
    # container has no name for that gid), mirroring the upstream script's
    # --group-add fastrpc/dmaheap/video.
    target_user=$(getent passwd "${WESTON_UID}" | cut -d: -f1 || true)
    if [ -z "${target_user}" ]; then
        target_user=dorbell
        useradd -u "${WESTON_UID}" -M -s /usr/sbin/nologin "${target_user}" 2>/dev/null || true
    fi
    # NB: bare `[ ... ] && continue` and unguarded `$(pipe)` both trip
    # set -euo pipefail, so every step below is written to never return
    # non-zero out of a condition (if/|| true), or the script dies here and
    # the container never reaches the gosu exec.
    for node in /dev/fastrpc-cdsp /dev/dma_heap/system $(ls /dev/video* 2>/dev/null); do
        [ -e "${node}" ] || continue
        gid=$(stat -c %g "${node}" 2>/dev/null) || continue
        if [ "${gid}" = 0 ]; then
            continue                          # root-owned node needs no group
        fi
        gname=$(getent group "${gid}" | cut -d: -f1 || true)
        if [ -z "${gname}" ]; then
            gname="dev_${gid}"
            groupadd -g "${gid}" "${gname}" 2>/dev/null || true
        fi
        usermod -aG "${gname}" "${target_user}" 2>/dev/null || true
    done
    echo "[dorbell] granted ${target_user} groups: $(id -Gn "${target_user}" 2>/dev/null || true)"

    export DISPLAY=:0
    export XDG_RUNTIME_DIR=/run/user/${WESTON_UID}
    echo "[dorbell] Starting backend=npu as uid=${WESTON_UID} ..."
    # gosu resets HOME from /etc/passwd; override it back to /app where the
    # baked-in qnn_context/ lives and the .insightface volume is mounted.
    # gosu initialises the target user's supplementary groups (set above).
    exec gosu "${WESTON_UID}" env HOME=/app python3 /app/doorbell.py --backend npu
else
    echo "[dorbell] No Weston display (/tmp/.X11-unix/X0 absent); using Xvfb (view appears nowhere)"
    Xvfb :1 -screen 0 1280x720x24 -nolisten tcp &
    export DISPLAY=:1
    echo "[dorbell] Starting backend=npu ..."
    exec python3 /app/doorbell.py --backend npu
fi
