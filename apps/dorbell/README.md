# dorbell — face-recognition doorbell OTA app

A face-recognition doorbell that runs on all three demo boards as a Docker
Compose application, delivered over the air the same way the voice app is. It
draws a live camera view with recognised faces on the board's physical screen
through an OpenCV highgui window. Inference runs on the NPU (Neural Processing
Unit) through the Hexagon Tensor Processor. The window is the whole interface:
keyboard keys shown on the loading screen (`B` CPU/NPU, `G` guest, `C` clear,
`Q` quit) drive it. It serves no network port.

The source (`doorbell.py`, `qnn_context/`, `requirements.txt`) lives in the
public [`munoz0raul/dorbell`](https://github.com/munoz0raul/dorbell) repo and is
cloned at image-build time, so this directory stays thin: a `Dockerfile`, a
`docker-compose.yml`, and the `start.sh` entrypoint that adapts the container to
whichever board it lands on.

## Per-board model

Each board has its own compiled inference graph. A QNN (Qualcomm Neural Network)
context binary is tied to one HTP (Hexagon Tensor Processor) version and does not
move between versions, so both boards' binaries are baked into the image (~5 MB
total) and the right pair is selected at runtime:

| Board | SoC | HTP | `DOORBELL_SOC_TAG` | Context binaries |
| --- | --- | --- | --- | --- |
| VENTUNO Q, IQ-8275 EVK | QCS8275 | v75 | `qcs8275` | `det_500m_qcs8275.bin`, `w600k_mbf_qcs8275.bin` |
| IQ-9075 EVK | SA8775P | v73 | `qcs9075` | `det_500m_qcs9075.bin`, `w600k_mbf_qcs9075.bin` |

`det_500m` detects faces; `w600k_mbf` produces the recognition embedding.
`start.sh` reads the HTP version from the board's QNN skel filename
(`libQnnHtpV<ver>Skel.so`) and maps v75→`qcs8275`, v73→`qcs9075`, then exports
`DOORBELL_SOC_TAG`. `doorbell.py` reads that variable and loads the matching
`*_<tag>.bin` pair. The CPU fallback backend uses the InsightFace `buffalo_sc`
ONNX models, which are architecture-independent and mounted from
`/root/.insightface` (see Prerequisites).

## What `start.sh` does

It runs as root inside a privileged container and handles three things the static
compose file cannot:

1. **DSP shell.** It finds the board-specific DSP (Digital Signal Processor)
   `cdsp` directory under `/usr/share/qcom` (the one holding
   `fastrpc_shell_unsigned_3` and the `libQnnHtpV*Skel.so`) and symlinks it to
   `/usr/lib/dsp/cdsp`, the path the in-container FastRPC library probes.

2. **Display.** QLI (Qualcomm Linux Image) runs Weston. Weston's bundled
   XWayland owns `/tmp/.X11-unix/X0` and authorises clients by matching UID, with
   no `.Xauthority` cookie. The container mounts that socket and `start.sh` reads
   its owner UID (1000 on these boards), then re-execs the app under that UID with
   `gosu` so the OpenCV window draws on the physical screen. On a board with no
   Weston socket it starts an `Xvfb` virtual framebuffer so OpenCV highgui
   initialises; the view is then confined to that off-screen framebuffer and
   appears nowhere. All three demo boards run Weston, so the Weston path is the
   live one.

3. **Device access for the dropped UID.** Dropping from root to UID 1000 loses
   root's blanket device access. The HTP session opens `/dev/fastrpc-cdsp` and
   `/dev/dma_heap/system`; the camera opens `/dev/video*`. In a privileged
   container these nodes carry their host group IDs, so `start.sh` adds UID 1000
   to a group matching each node's GID (creating a placeholder group name when the
   container has none). Without this the HTP session fails to load its skel
   (`status=0x00000072`).

`gosu` resets `HOME` from `/etc/passwd`, so the exec sets `HOME=/app` back, where
the baked-in `qnn_context/` lives and the `.insightface` volume mounts.

## Prerequisites on the board

- **Weston running** for the on-screen window. Present on the VENTUNO Q and
  IQ-9075 EVK images. Without it the app runs under `Xvfb` and the view appears
  nowhere.
- **A camera** on `/dev/video*` (USB webcam or MIPI (Mobile Industry Processor
  Interface) sensor). The window loads without one; recognition needs it.
- **InsightFace `buffalo_sc` ONNX models** at `/root/.insightface`, used only by
  the CPU fallback backend. They are large and board-specific, so they are left
  out of the image and mounted read-only by the compose file. The NPU backend
  does not read them; it is unaffected when they are absent.

## Compose settings

`privileged: true` gives `start.sh` the DSP symlink write and exposes every
device node without explicit `--device` flags. The compose file sets
`network_mode: host` as the other demo apps do; dorbell itself binds no port, so
host networking only simplifies parity with them. The volumes forward the host's
`/usr/share/qcom` DSP share and the flat `libcdsprpc`/`libadsprpc` FastRPC
libraries into the container's `aarch64-linux-gnu` multiarch path, and mount the
Weston socket and the `.insightface` models.

## Confirmed working

On the VENTUNO Q the startup log shows the qcs8275 path end to end:

```
[dorbell] DSP: .../dsp/cdsp (HTP v75, SoC=qcs8275)
[dorbell] Weston XWayland detected (socket owner uid=1000); using DISPLAY=:0
[dorbell] granted ubuntu groups: ... video dev_990 dev_992
[NPU] in-process HTP engine ready  (load 253ms)
[NPU] det_ctx=/app/qnn_context/det_500m_qcs8275.bin
[NPU] rec_ctx=/app/qnn_context/w600k_mbf_qcs8275.bin
```

The IQ-9075 EVK prints the same with `HTP v73`, `SoC=qcs9075`, and the
`*_qcs9075.bin` pair. The line `[Display] WARNING: no Xwayland auth found` is
expected: Weston authorises by UID, so no auth cookie is found or needed.
