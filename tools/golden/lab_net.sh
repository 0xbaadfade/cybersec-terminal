#!/bin/sh
# Runs INSIDE `unshare -rnm` (an empty network namespace: nothing leaves this
# machine). Rebuilds lab-dmz-01's name service and web server on the namespace's
# own loopback so the REAL dig, nslookup and curl can be captured against them:
#   named (BIND) on 10.20.0.2 serving tools/golden/zones; it recurses, but its only
#   forwarder (10.20.0.99) does not exist, so names outside corp.local fail,
#   a web server on 10.20.0.10:80 and a silent one on 10.20.0.30:80,
#   10.20.0.40 where port 80 is dropped (filtered), 10.20.0.77 where DNS is dropped.
OUT="$1"; HERE="$2"; WORK="$3"
export TZ=UTC
ip link set lo up
for a in 1 2 10 11 20 30 40 50 77; do ip addr add 10.20.0.$a/32 dev lo; done
printf 'nameserver 10.20.0.2\nsearch corp.local\n' > "$WORK/resolv.conf"
mount --bind "$WORK/resolv.conf" /etc/resolv.conf
sed -e "s#@WORK@#$WORK#g" -e "s#@HERE@#$HERE#g" "$HERE/named.conf" > "$WORK/named.conf"
named -g -c "$WORK/named.conf" > "$WORK/named.log" 2>&1 & P1=$!
python3 "$HERE/http_server.py" 10.20.0.10 & P2=$!
nft add table inet t
nft add chain inet t out '{ type filter hook output priority 0 ; }'
nft add rule inet t out ip daddr 10.20.0.40 tcp dport 80 drop
nft add rule inet t out ip daddr 10.20.0.77 udp dport 53 drop
nft add rule inet t out ip daddr 10.20.0.77 tcp dport 53 drop
sleep 3

normalise() {
  sed -E \
    -e 's#\r+$##' \
    -e 's#id: [0-9]+$#id: ID#' \
    -e 's#^; COOKIE: [0-9a-f]+ \(good\)#; COOKIE: C (good)#' \
    -e 's#Query time: [0-9]+ msec#Query time: Q msec#' \
    -e 's#^;; WHEN: .*#;; WHEN: W#' \
        -e 's#^Date: .*#Date: DATE#' \
    -e 's#after [0-9]+ ms#after N ms#' \
    -e 's#after [0-9]+ milliseconds#after N milliseconds#'
}
cap() { # name, command...
  name="$1"; shift
  # script(1) gives the tool a pseudo-terminal, so it behaves as in a learner's
  # window (line-buffered stdout, no curl progress meter, dig messages in the
  # order a person sees them).
  timeout "${CAPT:-90}" script -qec "$*" /dev/null 2>&1 | normalise > "$OUT/$name.txt"
  echo "wrote tests/golden/$name.txt  ($*)"
}

cap dig_a              dig web-03.corp.local
cap dig_at             dig @10.20.0.2 web-03.corp.local
cap dig_short          dig +short web-03.corp.local
cap dig_cname          dig www.corp.local
cap dig_short_cname    dig +short www.corp.local
cap dig_mx             dig corp.local MX
cap dig_short_mx       dig +short corp.local MX
cap dig_ns             dig corp.local NS
cap dig_txt            dig corp.local TXT
cap dig_soa            dig corp.local SOA
cap dig_t_mx           dig -t MX corp.local
cap dig_ptr            dig -x 10.20.0.30
cap dig_short_ptr      dig +short -x 10.20.0.30
cap dig_ptr_nx         dig -x 10.20.0.99
cap dig_nx             dig nosuch.corp.local
cap dig_short_nx       dig +short nosuch.corp.local
cap dig_nodata         dig web-03.corp.local MX
cap dig_refused        dig example.com
cap dig_bare           dig web-03
cap dig_noall          dig +noall +answer web-03.corp.local
cap dig_noall_cname    dig +noall +answer www.corp.local
cap dig_a_lower        dig WEB-03.Corp.Local
cap dig_dead_server    dig @10.20.0.77 web-03.corp.local
cap dig_x_bad          dig -x 1.2.3
cap dig_x_text         dig -x notanaddress
cap dig_server_name_bad dig @nosuch.invalid web-03.corp.local
cap dig_noserver       dig @10.20.0.11 web-03.corp.local

cap nslookup_a         nslookup web-03.corp.local
cap nslookup_bare      nslookup web-03
cap nslookup_server    nslookup web-03.corp.local 10.20.0.2
cap nslookup_cname     nslookup www.corp.local
cap nslookup_ptr       nslookup 10.20.0.30
cap nslookup_ptr_nx    nslookup 10.20.0.99
cap nslookup_mx        nslookup -type=MX corp.local
cap nslookup_ns        nslookup -type=NS corp.local
cap nslookup_txt       nslookup -type=TXT corp.local
cap nslookup_soa       nslookup -type=SOA corp.local
cap nslookup_nx        nslookup nosuch.corp.local
cap nslookup_refused   nslookup example.com
cap nslookup_nodata    nslookup -type=MX web-03.corp.local
cap nslookup_dead      nslookup web-03.corp.local 10.20.0.77
cap nslookup_noserver  nslookup web-03.corp.local 10.20.0.11
cap nslookup_bare_nx   nslookup nosuch

cap curl_I             curl --no-styled-output -I http://10.20.0.10/
cap curl_head_long     curl --no-styled-output --head http://10.20.0.10/
cap curl_I_bare        curl --no-styled-output -I web-03
cap curl_i             curl --no-styled-output -i http://10.20.0.10/
cap curl_body          curl --no-styled-output http://10.20.0.10/
cap curl_s_I           curl --no-styled-output -s -I http://10.20.0.10/
cap curl_301           curl --no-styled-output -I http://10.20.0.10/old
cap curl_403           curl --no-styled-output -I http://10.20.0.10/admin
cap curl_404           curl --no-styled-output -I http://10.20.0.10/missing
cap curl_404_body      curl --no-styled-output http://10.20.0.10/missing
cap curl_refused       curl --no-styled-output -I http://10.20.0.11
cap curl_refused_port  curl --no-styled-output -I http://10.20.0.10:8080/
cap curl_empty         curl --no-styled-output -I http://10.20.0.30
cap curl_empty_body    curl --no-styled-output http://10.20.0.30
cap curl_timeout       curl --no-styled-output -I --connect-timeout 2 http://10.20.0.40
CAPT=200 cap curl_timeout_default curl --no-styled-output -I http://10.20.0.40
cap curl_m_timeout     curl --no-styled-output -I -m 2 http://10.20.0.40
cap curl_nohost        curl --no-styled-output -I http://nosuch.corp.local
cap curl_nourl         curl
cap curl_s_refused     curl --no-styled-output -s -I http://10.20.0.11
cap curl_s_nohost      curl --no-styled-output -s -I http://nosuch.corp.local
cap curl_https_refused curl --no-styled-output -I https://10.20.0.10/
kill $P1 $P2 2>/dev/null
