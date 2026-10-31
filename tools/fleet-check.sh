#!/usr/bin/env bash
# Check the demo boards: the VENTUNO Q access point and every UNO Q with a
# DHCP lease from it.
set -uo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") --ventuno USER@HOST [options]

Checks the VENTUNO Q access point and every UNO Q that has a DHCP lease from
it, and prints one block per board:

  VENTUNO Q  AP services and channel, stations, chrony reference, MCU loader
  UNO Q      Wi-Fi link and factory MAC, chrony sync to the AP, MCU loader,
             demo-server.local resolution (connected stations only; leases
             of boards that are gone are listed as stale)

With MCU checks (default), it also queries each MCU over /dev/mcu-console
with session-less commands only (CLOCK_SAMPLE, LOG). It never sends HELLO,
so the matrix and a running led-matrix-client are not disturbed.

Options:
  --ventuno USER@HOST  VENTUNO Q to start from (required), e.g. its wired
                       address root@192.168.101.247
  --direct             reach UNO Qs directly instead of through the VENTUNO Q
                       as an ssh jump host (this host is on the demo Wi-Fi)
  --install-keys       where key login fails, install this host's ssh key with
                       sshpass, reading the password from \$SSHPASS
  --no-mcu             skip the MCU link checks (e.g. while led-matrix-client
                       owns /dev/mcu-console)
  -h, --help           show this help

Exit status: 0 if every board was checked, 1 if any could not be reached.
EOF
}

ventuno=""
direct=false
install_keys=false
mcu=true
while [ $# -gt 0 ]; do
    case $1 in
    --ventuno) ventuno=${2:-}; shift 2 ;;
    --direct) direct=true; shift ;;
    --install-keys) install_keys=true; shift ;;
    --no-mcu) mcu=false; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done
if [ -z "$ventuno" ]; then
    echo "error: --ventuno is required" >&2
    usage >&2
    exit 2
fi
if $install_keys && { ! command -v sshpass >/dev/null || [ -z "${SSHPASS:-}" ]; }; then
    echo "error: --install-keys needs sshpass and the password in \$SSHPASS" >&2
    exit 2
fi

mcu_link="$(dirname -- "$(readlink -f -- "$0")")/lighting-poc/mcu_link.py"
ssh_opts=(-o BatchMode=yes -o ConnectTimeout=8 -o ConnectionAttempts=2
          -o StrictHostKeyChecking=accept-new)

# ssh to a board; UNO Qs go through the VENTUNO Q unless --direct
board_ssh() {
    local target=$1
    shift
    local opts=("${ssh_opts[@]}")
    if [ "$target" != "$ventuno" ] && ! $direct; then
        opts+=(-o "ProxyJump=$ventuno")
    fi
    ssh "${opts[@]}" "$target" "$@"
}

# Log in, installing this host's key first if asked and needed
reachable() {
    local target=$1
    board_ssh "$target" true 2>/dev/null && return 0
    $install_keys || return 1
    local opts=(-o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new)
    [ "$target" != "$ventuno" ] && ! $direct && opts+=(-o "ProxyJump=$ventuno")
    sshpass -e ssh-copy-id "${opts[@]}" "$target" >/dev/null 2>&1 &&
        board_ssh "$target" true 2>/dev/null
}

# MCU link checks on a board (session-less SMP commands only)
mcu_check() {
    local target=$1
    $mcu || return 0
    if [ ! -r "$mcu_link" ]; then
        echo "mcu:      $mcu_link not found"
        return 0
    fi
    board_ssh "$target" 'cat > /tmp/mcu_link.py' < "$mcu_link" || return 0
    board_ssh "$target" '
        if [ ! -e /dev/mcu-console ]; then echo "mcu:      no /dev/mcu-console"; exit 0; fi
        up=$(timeout 5 python3 /tmp/mcu_link.py clock 2>&1 | sed -n "s/.*.rx.: \([0-9]*\).*/\1/p")
        if [ -n "$up" ]; then
            echo "mcu:      link ok, MCU up $((up / 1000000)) s"
        else
            echo "mcu:      link NO RESPONSE (no matrix service firmware?)"
        fi
        timeout 5 python3 /tmp/mcu_link.py log 2>/dev/null | tail -n 2 | sed "s/^/mcu log:  /"'
}

failed=0
echo "===== VENTUNO Q ($ventuno)"
if ! reachable "$ventuno"; then
    echo "cannot log in"
    exit 1
fi
board_ssh "$ventuno" '
    printf "host:     %s  %s\n" "$(hostname)" "$(uname -r)"
    printf "ap:       demo-wifi-ap %s, dhcp %s, mdns %s\n" \
        "$(systemctl is-active demo-wifi-ap)" "$(systemctl is-active demo-wifi-dhcp)" \
        "$(systemctl is-active demo-wifi-mdns 2>/dev/null)"
    ap=$(iw dev | awk "/Interface/ { i = \$2 } /type AP/ { print i }")
    printf "channel:  %s\n" "$(iw dev "$ap" info 2>/dev/null | sed -n "s/^\tchannel //p")"
    printf "stations: %s\n" "$(iw dev "$ap" station dump 2>/dev/null | grep -c ^Station)"
    printf "chrony:   %s\n" "$(chronyc -n tracking | grep -E "Reference ID|Stratum" | tr -s " " | paste -sd";")"
    printf "loader:   %s %s\n" "$(systemctl is-active zephyr-loader)" \
        "$(journalctl -b -u zephyr-loader --no-pager | grep -m1 -E "MCU started|zephyr-loader:")"'
mcu_check "$ventuno"

# Leases whose MAC is associated with the AP now; the rest are stale (e.g. a
# board that came back with another address)
mapfile -t leases < <(board_ssh "$ventuno" '
    ap=$(iw dev | awk "/Interface/ { i = \$2 } /type AP/ { print i }")
    iw dev "$ap" station dump | awk "/^Station/ { print \$2 }" > /tmp/fleet-stations
    awk "NR == FNR { up[\$1] = 1; next } { print \$3, \$2, (\$2 in up) ? \"up\" : \"stale\" }" \
        /tmp/fleet-stations /var/lib/demo-wifi/dhcp.leases 2>/dev/null')
echo
stale=()
active=()
for lease in "${leases[@]}"; do
    case $lease in
    *" stale") stale+=("${lease% stale}") ;;
    *) active+=("${lease% up}") ;;
    esac
done
echo "${#active[@]} connected UNO Q(s); ${#stale[@]} stale lease(s)${stale[*]:+: ${stale[*]}}"
leases=("${active[@]}")
for lease in "${leases[@]}"; do
    ip=${lease%% *}
    target="root@$ip"
    echo
    echo "===== $ip (lease MAC ${lease#* })"
    if ! reachable "$target"; then
        echo "cannot log in"
        failed=1
        continue
    fi
    board_ssh "$target" '
        printf "host:     %s  %s  up %s\n" "$(hostname)" "$(uname -r)" "$(uptime | sed "s/.*up *//; s/,.*//")"
        mac=$(cat /sys/class/net/wlan0/address)
        factory=$(dd if=/dev/disk/by-partlabel/wlanaddr bs=6 count=1 2>/dev/null | od -An -tx1 | tr -d " \n" | sed "s/\(..\)/\1:/g; s/:$//")
        printf "mac:      %s (%s)\n" "$mac" "$([ "$mac" = "$factory" ] && echo factory || echo "NOT factory $factory")"
        printf "wifi:     %s\n" "$(iw dev wlan0 link | grep -E "SSID|freq|signal|tx bitrate" | sed "s/^\t//" | paste -sd";")"
        printf "power:    %s\n" "$(iw dev wlan0 get power_save)"
        printf "chrony:   %s\n" "$(chronyc -n tracking | grep -E "Reference ID|System time|Leap" | tr -s " " | paste -sd";")"
        printf "loader:   %s %s\n" "$(systemctl is-active zephyr-loader)" \
            "$(journalctl -b -u zephyr-loader --no-pager | grep -m1 -E "MCU started|zephyr-loader:")"
        printf "link:     /dev/mcu-console -> %s\n" "$(readlink /dev/mcu-console || echo MISSING)"
        # timeout: without an /etc/hosts entry the lookup waits on the public
        # fallback DNS servers, which are unreachable from the demo network
        printf "server:   demo-server.local %s\n" \
            "$(timeout 5 ping -c 1 -W 2 demo-server.local >/dev/null 2>&1 && echo reachable || echo "NOT reachable")"'
    mcu_check "$target"
done
exit "$failed"
