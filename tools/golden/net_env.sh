#!/bin/sh
# Runs INSIDE `unshare -rnm`: ss and netstat against sockets this script owns.
OUT="$1"; HERE="$2"
export TZ=UTC
ip link set lo up
python3 "$HERE/listeners_net.py" & P1=$!
sleep 2

normalise() {
  sed -E \
    -e 's#:[0-9]{5}( |$)#:PPPPP\1#g' \
    -e 's#pid=[0-9]+,fd=[0-9]+#pid=P,fd=F#' \
    -e 's#[0-9]+/python3#PID/python3#' \
    -e 's# +$##'
}
cap() { # name, command...
  name="$1"; shift
  "$@" 2>&1 | normalise > "$OUT/$name.txt"
  echo "wrote tests/golden/$name.txt  ($*)"
}

cap ss_tln       ss -tln
cap ss_uln       ss -uln
cap ss_tuln      ss -tuln
cap ss_tlnp      ss -tlnp
cap ss_tl        ss -tl
cap ss_ta        ss -ta
cap ss_tan       ss -tan
cap ss_tn        ss -tn
cap ss_bare      ss
cap ss_tulnp     ss -tulnp
cap netstat_tln  netstat -tln
cap netstat_tuln netstat -tuln
cap netstat_tlnp netstat -tlnp
cap netstat_tl   netstat -tl
cap netstat_tan  netstat -tan
cap netstat_an   netstat -an
cap netstat_tn   netstat -tn
cap netstat_bare netstat
cap netstat_ln   netstat -ln
cap netstat_uan  netstat -uan
kill $P1 2>/dev/null
