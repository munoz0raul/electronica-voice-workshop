#!/usr/bin/env bash
# Poll the workshop repo for app changes and ship them as a new OTA Target.
#
# Runs on the VENTUNO Q from poll-and-build.timer. On each tick it fetches the
# repo over the Ethernet uplink, and when anything under apps/ has changed since
# the last build it rebuilds the changed app image(s), stages a Target for each
# board (UNO Q + VENTUNO Q, both apps), uploads them to the local update-server,
# and optionally creates a rollout to the demo group. Both boards' aktualizr-lite
# agents pull only the changed OCI blobs (a model swap is ~14 MB).
#
# Config is in /etc/default/poll-and-build (EnvironmentFile). Nothing here is
# secret: the private-repo credential (deploy key or token) and the fiocli
# sign-in are provisioned once on the box, not baked into the image.
set -euo pipefail

# --- config (overridable via /etc/default/poll-and-build) --------------------
: "${REPO_URL:=https://github.com/munoz0raul/electronica-voice-workshop}"
: "${BRANCH:=main}"
: "${WORKDIR:=/var/lib/poll-and-build}"
: "${CHECKOUT:=${WORKDIR}/repo}"
: "${STATE:=${WORKDIR}/last-built-sha}"
# Each board's OS half. stage-target.sh copies it into every Target so the board
# sees an app-only update (no reboot). Provisioned once; see the recipe README.
: "${OSTREE_REPO:=${WORKDIR}/uno-q-ostree_repo}"
: "${VENTUNO_OSTREE_REPO:=${WORKDIR}/ventuno-q-ostree_repo}"
# Only rebuild when something under this path changes (skip OS/docs commits).
: "${WATCH_PATH:=apps}"
# The app set staged into each Target (the whole board, so unchanged apps ride
# along by their existing digest and cost no download).
: "${APPS:=webapp-led-mcu-voice webapp-led-mcu-voice-assets}"
: "${TAG:=main}"
: "${GROUP:=demo}"
# 1: upload AND roll out to GROUP. 0: upload only (instructor fires the rollout).
: "${AUTO_ROLLOUT:=1}"
# buildx builder build-apps.sh uses; native arm64, so the container driver needs
# no QEMU. Created on first run if absent.
: "${BUILDX_BUILDER:=host-builder}"
export BUILDX_BUILDER

log() { echo "poll-and-build: $*"; }
die() { echo "poll-and-build: ERROR: $*" >&2; exit 1; }

mkdir -p "${WORKDIR}"

# One run at a time: a slow build must not overlap the next timer tick.
exec 9>"${WORKDIR}/.lock"
flock -n 9 || { log "another run holds the lock; skipping"; exit 0; }

# --- fetch -------------------------------------------------------------------
if [ ! -d "${CHECKOUT}/.git" ]; then
    log "cloning ${REPO_URL} (${BRANCH}) -> ${CHECKOUT}"
    git clone --branch "${BRANCH}" "${REPO_URL}" "${CHECKOUT}"
fi
cd "${CHECKOUT}"
git remote set-url origin "${REPO_URL}"
git fetch -q origin "${BRANCH}"

new=$(git rev-parse "origin/${BRANCH}")
last=$(cat "${STATE}" 2>/dev/null || echo "")

if [ "${new}" = "${last}" ]; then
    exit 0   # nothing new since the last build
fi

# A commit that touches nothing under WATCH_PATH (e.g. docs) is recorded and
# skipped, so the next real app change still diffs against a known-good base.
if [ -n "${last}" ] && git diff --quiet "${last}" "${new}" -- "${WATCH_PATH}"; then
    log "new commit ${new:0:7} does not touch ${WATCH_PATH}/; skipping build"
    echo "${new}" > "${STATE}"
    exit 0
fi

last_short=${last:0:7}
log "building for ${new:0:7} (was ${last_short:-none})"
git checkout -q "${new}"

# --- which apps changed ------------------------------------------------------
if [ -z "${last}" ]; then
    changed=(${APPS})                     # first run: build everything
else
    mapfile -t changed < <(git diff --name-only "${last}" "${new}" -- apps/ \
        | awk -F/ 'NF>=2 {print $2}' | sort -u)
fi
[ ${#changed[@]} -gt 0 ] || changed=(${APPS})
log "rebuilding: ${changed[*]}"

# --- build -------------------------------------------------------------------
# build-apps.sh needs a docker-container buildx builder; create it once.
if ! docker buildx inspect "${BUILDX_BUILDER}" >/dev/null 2>&1; then
    log "creating buildx builder ${BUILDX_BUILDER} (docker-container)"
    docker buildx create --name "${BUILDX_BUILDER}" --driver docker-container
fi
./build-apps.sh --rebuild "${changed[@]}"

# Every app in the Target needs its image present, even unchanged ones.
for app in ${APPS}; do
    [ -e "images/${app}.oci.tar" ] || die "images/${app}.oci.tar missing; build ${app} once"
done

# --- stage + upload ----------------------------------------------------------
[ -d "${OSTREE_REPO}" ] || die "UNO Q ostree_repo not found at ${OSTREE_REPO} (provision it once)"

name="voice-${new:0:7}"
log "staging UNO Q target"
tools/stage-target.sh uno-q "${OSTREE_REPO}" ${APPS}
log "uploading uno-q target as ${name} (tag ${TAG})"
fiocli updates upload "${TAG}" "${name}" ./targets/uno-q/

if [ -d "${VENTUNO_OSTREE_REPO}" ]; then
    # The update server requires a unique name per tag, so VENTUNO Q gets its
    # own update name with a "-ventuno" suffix.  Its rollout targets the same
    # group; aktualizr-lite on each device applies only the target matching
    # its hardware-id, so UNO Q and VENTUNO Q see different OS commits even
    # though both updates roll out to the same group.
    vname="${name}-ventuno"
    log "staging VENTUNO Q target"
    tools/stage-target.sh ventuno-q "${VENTUNO_OSTREE_REPO}" ${APPS}
    log "uploading ventuno-q target as ${vname} (tag ${TAG})"
    fiocli updates upload "${TAG}" "${vname}" ./targets/ventuno-q/
else
    log "VENTUNO Q ostree_repo not found at ${VENTUNO_OSTREE_REPO}; skipping ventuno-q target"
    vname=""
fi

if [ "${AUTO_ROLLOUT}" = "1" ]; then
    log "rolling out ${name} to group ${GROUP}"
    fiocli updates create-rollout "${name}" "auto-${new:0:7}" --groups "${GROUP}"
    if [ -n "${vname}" ]; then
        log "rolling out ${vname} to group ${GROUP}"
        fiocli updates create-rollout "${vname}" "auto-${new:0:7}-ventuno" --groups "${GROUP}"
    fi
fi

echo "${new}" > "${STATE}"
log "done: ${name}"
