#!/usr/bin/env bash
# Poll the workshop repo for app changes and ship them as a new OTA Target.
#
# Runs on the VENTUNO Q from poll-and-build.timer. On each tick it fetches the
# repo over the Ethernet uplink, and when anything under apps/ has changed since
# the last build it rebuilds the changed app image(s), stages a Target for each
# board (UNO Q + VENTUNO Q, both apps), uploads them to the local update-server,
# and optionally rolls each Target out to its own boards by UUID. Both boards'
# aktualizr-lite agents pull only the changed OCI blobs (a model swap is ~14 MB).
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
: "${IQ9_OSTREE_REPO:=${WORKDIR}/iq9-ostree_repo}"
# Only rebuild when something under this path changes (skip OS/docs commits).
: "${WATCH_PATH:=apps}"
# The app set staged into each Target is discovered from the repo after
# checkout: every directory under apps/ with a docker-compose.yml. Adding or
# removing an app is just adding/removing its apps/<name>/ directory — no list
# to maintain here, in build-apps.sh, or in /etc/default/poll-and-build. Set
# APPS in the environment only to override that discovery.
APPS="${APPS:-}"
: "${TAG:=main}"
# 1: upload AND roll out each Target to its own boards. 0: upload only
# (instructor fires the rollout).
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

# Discover the app set from the checked-out commit unless APPS was overridden
# in the environment. An app is any apps/<name>/ with a docker-compose.yml.
if [ -z "${APPS}" ]; then
    APPS=$(for d in apps/*/; do
        [ -f "${d}docker-compose.yml" ] && basename "${d%/}"
    done | sort | tr '\n' ' ')
fi
log "app set: ${APPS}"

# --- which apps changed ------------------------------------------------------
if [ -z "${last}" ]; then
    changed=(${APPS})                     # first run: build everything
else
    mapfile -t changed < <(git diff --name-only "${last}" "${new}" -- apps/ \
        | awk -F/ 'NF>=2 {print $2}' | sort -u)
fi
# A removed/disabled app still appears in the diff as deleted paths; drop
# anything no longer in the app set so build-apps.sh isn't asked to build a
# directory that was moved out of apps/ (e.g. to apps.disable/).
keep=()
for c in "${changed[@]}"; do
    case " ${APPS} " in *" ${c} "*) keep+=("${c}") ;; esac
done
changed=("${keep[@]}")
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

# Upload a target; tolerate 409 (already exists) so a partial re-run caused
# by an earlier failure can skip targets that were already uploaded and
# continue staging/uploading the ones that weren't.
upload_target() {
    local tag=$1 tname=$2 dir=$3
    local out
    # && suppresses set -e so the failure is caught by the if below.
    out=$(fiocli updates upload "$tag" "$tname" "$dir" 2>&1) && return 0
    if echo "$out" | grep -q "already exists"; then
        log "target $tname already exists; skipping upload"
        return 0
    fi
    echo "$out" >&2
    return 1
}

create_rollout() {
    local uname=$1 rname=$2 uuids=$3
    local out
    out=$(fiocli updates create-rollout "$uname" "$rname" --uuids "$uuids" 2>&1) && return 0
    if echo "$out" | grep -q "already exists"; then
        log "rollout $rname already exists; skipping"
        return 0
    fi
    echo "$out" >&2
    return 1
}

# UUIDs of every registered device whose hardware matches $1 (a machine name:
# uno-q / ventuno-q / iq-9075-evk). The device name label is set from the board
# hostname (<machine>-<id>) at registration, so a "<machine>-" name prefix is a
# reliable hardware-id signal -- the server offers no per-device hardware-id
# query. Pages through the whole device list, so it scales past one page.
devices_for_machine() {
    local machine=$1 page=1 raw
    while :; do
        raw=$(fiocli devices list --columns uuid,name -p "$page" 2>/dev/null \
            | awk 'NR>1 {print $1"\t"$2}')
        [ -n "$raw" ] || break    # a page with no device rows = past the end
        echo "$raw" | awk -v m="${machine}-" 'index($2, m)==1 {print $1}'
        page=$((page+1))
    done | tr '\n' ',' | sed 's/,$//'
}

# Roll an update out to exactly the devices of its hardware type, by UUID. This
# is what keeps three single-hardware Targets from fighting over one group: a
# group rollout re-points *every* device in the group at its Target, so three
# rollouts to one group leave every board on the last one (the UNO Q then finds
# no matching Target). Scoping each rollout to its own boards' UUIDs removes the
# race -- and the count stays at three rollouts no matter how many devices.
rollout_machine() {
    local uname=$1 rname=$2 machine=$3 uuids
    uuids=$(devices_for_machine "$machine")
    if [ -z "$uuids" ]; then
        log "no ${machine} devices registered; skipping rollout of ${uname}"
        return 0
    fi
    log "rolling out ${uname} to ${machine} devices: ${uuids}"
    create_rollout "$uname" "$rname" "$uuids"
}

name="voice-${new:0:7}"
log "staging UNO Q target"
tools/stage-target.sh uno-q "${OSTREE_REPO}" ${APPS}
log "uploading uno-q target as ${name} (tag ${TAG})"
upload_target "${TAG}" "${name}" ./targets/uno-q/

if [ -d "${VENTUNO_OSTREE_REPO}" ]; then
    # The update server requires a unique name per tag, so VENTUNO Q gets its
    # own update name with a "-ventuno" suffix. rollout_machine (below) sends it
    # only to the VENTUNO Q boards by UUID, so it never competes with the UNO Q
    # or IQ-9075 rollout the way a shared-group rollout would.
    vname="${name}-ventuno"
    log "staging VENTUNO Q target"
    tools/stage-target.sh ventuno-q "${VENTUNO_OSTREE_REPO}" ${APPS}
    log "uploading ventuno-q target as ${vname} (tag ${TAG})"
    upload_target "${TAG}" "${vname}" ./targets/ventuno-q/
else
    log "VENTUNO Q ostree_repo not found at ${VENTUNO_OSTREE_REPO}; skipping ventuno-q target"
    vname=""
fi

if [ -d "${IQ9_OSTREE_REPO}" ]; then
    # Like the VENTUNO Q, the IQ-9075 EVK needs its own update name; its
    # hardware-id differs so aktualizr-lite won't apply a UNO Q target to it.
    iname="${name}-iq9"
    log "staging IQ-9075 EVK target"
    tools/stage-target.sh iq-9075-evk "${IQ9_OSTREE_REPO}" ${APPS}
    log "uploading iq-9075-evk target as ${iname} (tag ${TAG})"
    upload_target "${TAG}" "${iname}" ./targets/iq-9075-evk/
else
    log "IQ9 ostree_repo not found at ${IQ9_OSTREE_REPO}; skipping iq-9075-evk target"
    iname=""
fi

if [ "${AUTO_ROLLOUT}" = "1" ]; then
    rollout_machine "${name}" "auto-${new:0:7}" uno-q
    [ -n "${vname}" ] && rollout_machine "${vname}" "auto-${new:0:7}-ventuno" ventuno-q
    [ -n "${iname}" ] && rollout_machine "${iname}" "auto-${new:0:7}-iq9" iq-9075-evk
fi

echo "${new}" > "${STATE}"
log "done: ${name}"
