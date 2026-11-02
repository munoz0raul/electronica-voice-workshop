# Dragonwing Doorbell — OTA compose app for the Electronica workshop.
#
# Build context: this apps/dorbell/ directory.  The source (doorbell.py,
# qnn_context/, requirements.txt) is cloned from the public dorbell repo at
# build time so the workshop repo stays thin.  Both board SoC context binaries
# (qcs8275 for IQ-8275/VENTUNO Q, qcs9075 for IQ-9075) are baked in; start.sh
# picks the correct one at runtime via DOORBELL_SOC_TAG.
#
# Two hard constraints from the upstream Dockerfile (see container/Dockerfile
# there for the full rationale):
#   - ubuntu:24.04  (GLIBC 2.39 required by host libcdsprpc.so)
#   - python3.10 venv + qai-appbuilder 2.50.0 cp310 wheel (QAIRT 2.50 match)
#
# The InsightFace buffalo_sc ONNX models are NOT baked in — they are too large
# and board-specific to commit, and IQ9 has no internet to auto-download.
# Pre-stage them once on each board and mount via the compose volume.

FROM ubuntu:24.04
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      software-properties-common ca-certificates git && \
    add-apt-repository -y ppa:deadsnakes/ppa && \
    apt-get update && apt-get install -y --no-install-recommends \
      python3.10 python3.10-venv python3.10-dev \
      libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 \
      libatomic1 \
      libyaml-0-2 \
      v4l-utils && \
    rm -rf /var/lib/apt/lists/*

RUN python3.10 -m venv /opt/venv
ENV PATH=/opt/venv/bin:$PATH

# Clone dorbell and install Python deps.  A specific ref can be pinned via
# --build-arg DORBELL_REF=<sha> to reproduce a known-good build.
ARG DORBELL_REPO=https://github.com/munoz0raul/dorbell
ARG DORBELL_REF=main
RUN git clone "$DORBELL_REPO" /tmp/dorbell && \
    git -C /tmp/dorbell checkout "$DORBELL_REF" && \
    pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r /tmp/dorbell/container/requirements.txt

# qai-appbuilder 2.50.0 — must match the QAIRT version on the boards (2.50).
# PyPI dropped 2.50.x; the only public cp310 build is the GitHub release.
ARG QAI_APPBUILDER_WHEEL=https://github.com/qualcomm/qai-appbuilder/releases/download/v2.50.0/qai_appbuilder-2.50.0-cp310-cp310-linux_aarch64.whl
RUN pip install --no-cache-dir "$QAI_APPBUILDER_WHEEL"

WORKDIR /app

# Bake in doorbell.py and ALL board context binaries (qcs8275 + qcs9075, ~5 MB
# total).  start.sh sets DOORBELL_SOC_TAG so doorbell.py picks the right one.
RUN cp /tmp/dorbell/doorbell.py /app/ && \
    cp -r /tmp/dorbell/qnn_context /app/ && \
    rm -rf /tmp/dorbell

# Entrypoint handles DSP dir detection, DOORBELL_SOC_TAG, and privilege setup.
# Separate layer so changes above (start.sh, qnn_context) don't re-run apt.
# xvfb provides a virtual framebuffer so cv2's Qt initialises without a real
# X server; the doorbell window is invisible but the web UI on :8000 works.
RUN apt-get update && apt-get install -y --no-install-recommends xvfb \
    && rm -rf /var/lib/apt/lists/*

COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

ENTRYPOINT ["/app/start.sh"]
