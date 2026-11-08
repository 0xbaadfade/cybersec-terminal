#!/bin/sh
# Runs INSIDE `unshare -rnm` (an empty network namespace: only loopback exists,
# nothing leaves this machine). Writes normalised nmap captures to $1.
# nmap runs with NMAP_UNPRIVILEGED=1 so it behaves as an ordinary user would.
OUT="$1"; HERE="$2"
export TZ=UTC NMAP_UNPRIVILEGED=1
ip link set lo up
printf 'nameserver 127.0.0.1\n' > "$OUT/.resolv.conf"
mount --bind "$OUT/.resolv.conf" /etc/resolv.conf
python3 "$HERE/nxdomain.py" & P1=$!
python3 "$HERE/listeners_nmap.py" & P2=$!
nft add table inet t
nft add chain inet t out '{ type filter hook output priority 0 ; }'
nft add rule inet t out ip daddr 127.0.0.1 tcp dport 8080 drop
nft add rule inet t out ip daddr 127.0.0.5 tcp dport '{ 80, 443 }' drop
nft add rule inet t out ip daddr 127.0.0.6 tcp dport != 443 drop
sleep 1

normalise() {
  sed -E \
    -e 's# at [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{5} \+0000$# at D#' \
    -e 's#\([0-9.]+s latency\)#(Ls latency)#' \
    -e 's#scanned in [0-9.]+ seconds#scanned in Ts seconds#' \
    -e 's#SimpleHTTPServer 0\.6 \(Python [0-9.]+\)#PYHTTP#'
}
cap() { # name, args...
  name="$1"; shift
  timeout 120 nmap "$@" 2>&1 | normalise > "$OUT/$name.txt"
  echo "wrote tests/golden/$name.txt  (nmap $*)"
}

cap nmap_default       127.0.0.1
cap nmap_p80           -p 80 127.0.0.1
cap nmap_mixed         -p 22,80,443,8080 127.0.0.1
cap nmap_range30       -p 70-100 127.0.0.1
cap nmap_sv            -sV -p 80 127.0.0.1
cap nmap_sv_closed     -n -sV -p 443 127.0.0.1
cap nmap_sn_one        -sn 127.0.0.1
cap nmap_sn_sweep      -n -sn 127.0.0.0/30
cap nmap_sn_down       -n -sn 127.0.0.5
cap nmap_sn_mixed      -n -sn 127.0.0.4/30
cap nmap_sweep_ports   -n -p 80 127.0.0.0/30
cap nmap_open_sweep    -n --open -p 80 127.0.0.0/30
cap nmap_open_none     --open -p 443 127.0.0.1
cap nmap_open_mixed    --open -p 80,443 127.0.0.1
cap nmap_open_states   -n --open -p 80,443,8080 127.0.0.1
cap nmap_pn            -Pn -p 80 127.0.0.1
cap nmap_pn_down       -n -Pn -p 80,443 127.0.0.5
cap nmap_down          -n 127.0.0.5
cap nmap_ignored       -n 127.0.0.2
cap nmap_firewall      -n 127.0.0.6
cap nmap_two_targets   -n -p 80 127.0.0.1 127.0.0.2
cap nmap_sorted        -n -p 80,22 127.0.0.1
cap nmap_cidr32        -n -p 80 127.0.0.1/32
cap nmap_octet_range   -n -sn 127.0.0.1-3
cap nmap_resolve_fail  nosuchhost.invalid
cap nmap_resolve_mixed -sn nosuchhost.invalid 127.0.0.1
cap nmap_root_ss       -sS 127.0.0.1
cap nmap_root_o        -O 127.0.0.1
cap nmap_root_su       -sU 127.0.0.1
cap nmap_p_range_bad   -p 99999 127.0.0.1
cap nmap_p_name_bad    -p abc 127.0.0.1
cap nmap_p_names       -n -p ssh,http 127.0.0.1
cap nmap_sn_p          -n -sn -p 80 127.0.0.1
cap nmap_t4            -T4 -p 80 127.0.0.1
cap nmap_all_ports     -n -p- 127.0.0.1
kill $P1 $P2 2>/dev/null
