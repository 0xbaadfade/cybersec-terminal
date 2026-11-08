#!/bin/sh
# Runs INSIDE `unshare -rnm`: ip against an eth0 that looks like analyst-ws.
OUT="$1"; HERE="$2"
export TZ=UTC
ip link set lo up
# The other end of the veth pair lives in a second namespace so that only lo and
# eth0 show up, as on the lab's workstation.
unshare -n sleep 300 & PEER=$!
sleep 1
ip link add eth0 type veth peer name eth0p netns $PEER
ip link set eth0 address 52:54:00:12:34:56
nsenter -t $PEER -n ip link set eth0p up
ip addr add 10.20.0.50/24 brd + dev eth0
ip link set eth0 up
ip route add default via 10.20.0.1
sleep 3
# A veth end shows its peer (eth0@if2, link-netnsid 0); a lab workstation's NIC does not.
normalise() { sed -E -e 's# +$##' -e 's#^eth0@if[0-9]+#eth0    #' -e 's#eth0@if[0-9]+#eth0#' -e 's# link-netnsid [0-9]+##' -e 's# tentative##' -e 's#after [0-9]+ ms#after N ms#' -e 's#after [0-9]+ milliseconds#after N milliseconds#'; }
cap() { # name, command...
  name="$1"; shift
  "$@" 2>&1 | normalise > "$OUT/$name.txt"
  echo "wrote tests/golden/$name.txt  ($*)"
}

cap ip_addr          ip addr
cap ip_a_show_eth0   ip a show eth0
cap ip_addr_dev      ip addr show dev eth0
cap ip_br            ip -br addr
cap ip_4             ip -4 addr
cap ip_4_br          ip -4 -br addr
cap ip_br_4          ip -br -4 addr
cap ip_link          ip link
cap ip_br_link       ip -br link
cap ip_route         ip route
cap ip_route_show    ip route show
cap ip_no_dev        ip addr show dev eth9
cap ip_bad_object    ip frobnicate
cap ip_noargs        ip
cap ip_addr_lo       ip addr show lo
cap curl_noroute   curl --no-styled-output -I http://10.20.0.99/
cap curl_noroute_m curl --no-styled-output -I -m 2 http://10.20.0.99/
kill $PEER 2>/dev/null
