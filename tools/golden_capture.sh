#!/usr/bin/env bash
# Capture real tool output against LOCALHOST ONLY and store it, normalised, as
# golden files for the lab simulator's tests (README "Phase 4 plan").
#
# Nothing but 127.0.0.1 / localhost / ::1 is ever contacted. Volatile numbers
# (latency, packet timing, durations) are replaced by placeholders so the files
# are stable; tests/unit/test_sim_golden.gd applies the same normalisation to the
# emulator output.
#
# Usage: tools/golden_capture.sh [all|p4c]   (p4c = only dig, nslookup, curl, ip; needs nix-shell; downloads the tools the first time)
# Takes a few minutes (nmap -p- and filtered ports wait on timeouts).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$HERE/tests/golden"
mkdir -p "$OUT"
GOLDEN_DIR="$HERE/tools/golden"
ONLY="${1:-all}"   # all | p4c

normalise() {
  sed -E \
    -e 's#time=[0-9.]+ ms#time=T ms#' \
    -e 's#time [0-9]+ms#time Tms#' \
    -e 's#^rtt min/avg/max/mdev = .* ms#rtt min/avg/max/mdev = R ms#'
}

run_ping() { # name, args...
  local name="$1"; shift
  env -u LD_LIBRARY_PATH nix-shell -p iputils --run "ping $*" 2>&1 | normalise > "$OUT/$name.txt"
  echo "wrote tests/golden/$name.txt  (ping $*)"
}

if [ "$ONLY" = all ]; then
run_ping ping_ip3       -c 3 127.0.0.1
run_ping ping_name      -4 -c 2 localhost
run_ping ping_size      -c 2 -s 100 -i 0.2 127.0.0.1
run_ping ping_quiet     -c 3 -q 127.0.0.1
run_ping ping_numeric   -4 -c 2 -n localhost
run_ping ping_nohost    -c 1 nosuchhost.invalid
run_ping ping_nodest
run_ping ping_badcount  -c x 127.0.0.1
run_ping ping_zerocount -c 0 127.0.0.1

# nmap, ss and netstat run inside `unshare -rnm`: a private network namespace with
# only a loopback interface, so nothing can leave this machine and the listeners
# are exactly the ones tools/golden/*.py create.
env -u LD_LIBRARY_PATH nix-shell -p nmap iproute2 net-tools nftables python3 util-linux --run \
  "unshare -rnm sh '$GOLDEN_DIR/nmap_env.sh' '$OUT' '$GOLDEN_DIR'"
env -u LD_LIBRARY_PATH nix-shell -p iproute2 net-tools python3 util-linux --run \
  "unshare -rnm sh '$GOLDEN_DIR/net_env.sh' '$OUT' '$GOLDEN_DIR'"
rm -f "$OUT/.resolv.conf"

fi

# dig, nslookup, curl and ip (P4c): a real named (BIND), a web server and an eth0
# inside `unshare -rnm`, again with nothing able to leave the machine. See the
# header of tools/golden/lab_net.sh.
WORK="$(mktemp -d)"
env -u LD_LIBRARY_PATH nix-shell -p dnsutils bind curl nftables python3 util-linux iproute2 --run \
  "unshare -rnm sh '$GOLDEN_DIR/lab_net.sh' '$OUT' '$GOLDEN_DIR' '$WORK'"
env -u LD_LIBRARY_PATH nix-shell -p iproute2 util-linux curl --run \
  "unshare -rnm sh '$GOLDEN_DIR/iface_net.sh' '$OUT' '$GOLDEN_DIR'"
rm -rf "$WORK"

{
  env -u LD_LIBRARY_PATH nix-shell -p iputils --run 'ping -V' 2>&1 | head -1
  env -u LD_LIBRARY_PATH nix-shell -p nmap --run 'nmap --version' 2>&1 | head -1
  env -u LD_LIBRARY_PATH nix-shell -p iproute2 --run 'ss -V' 2>&1 | head -1
  env -u LD_LIBRARY_PATH nix-shell -p net-tools --run 'netstat -V' 2>&1 | head -1
  env -u LD_LIBRARY_PATH nix-shell -p dnsutils --run 'dig -v' 2>&1 | head -1
  env -u LD_LIBRARY_PATH nix-shell -p bind --run 'named -V' 2>&1 | head -1
  env -u LD_LIBRARY_PATH nix-shell -p curl --run 'curl --version' 2>&1 | head -1 | cut -d' ' -f1-2
  env -u LD_LIBRARY_PATH nix-shell -p iproute2 --run 'ip -V' 2>&1 | head -1
} > "$OUT/VERSIONS.txt"
echo "recorded:"; cat "$OUT/VERSIONS.txt"
