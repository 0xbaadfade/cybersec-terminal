class_name SimServices
extends RefCounted
## Port-to-service names and which ports a default scan covers. A small
## hand-written table, not a copy of any tool's database: nmap and the system
## resolver (ss, netstat) name a few ports differently, so there are two tables.
## A port missing from a table prints as "unknown" (nmap) or as its number (ss).

## nmap's names for the ports a lab is likely to use. Names that were seen in a
## real capture (tests/golden) are marked in the README; the rest are from memory.
const NMAP_TCP := {
	7: "echo", 9: "discard", 13: "daytime", 17: "qotd", 19: "chargen", 20: "ftp-data", 21: "ftp",
	22: "ssh", 23: "telnet", 25: "smtp", 37: "time", 43: "whois", 53: "domain", 69: "tftp",
	79: "finger", 80: "http", 88: "kerberos-sec", 110: "pop3", 111: "rpcbind", 113: "ident",
	119: "nntp", 123: "ntp", 135: "msrpc", 139: "netbios-ssn", 143: "imap", 161: "snmp",
	179: "bgp", 389: "ldap", 443: "https", 445: "microsoft-ds", 465: "smtps", 514: "shell",
	515: "printer", 548: "afp", 554: "rtsp", 587: "submission", 631: "ipp", 636: "ldapssl",
	873: "rsync", 990: "ftps", 993: "imaps", 995: "pop3s", 1080: "socks", 1433: "ms-sql-s",
	1521: "oracle", 1723: "pptp", 2049: "nfs", 3128: "squid-http", 3306: "mysql",
	3389: "ms-wbt-server", 3690: "svn", 5060: "sip", 5432: "postgresql", 5900: "vnc",
	5985: "wsman", 6379: "redis", 8000: "http-alt", 8008: "http", 8080: "http-proxy",
	8443: "https-alt", 8888: "sun-answerbook", 9100: "jetdirect", 9200: "wap-wsp", 27017: "mongod",
}

## The system's names (what getservbyport gives ss and netstat): the same list
## with the few differences from nmap's.
const SYSTEM_TCP_OVERRIDES := {111: "sunrpc", 135: "epmap", 8008: "http-alt", 8080: "http-alt"}
const SYSTEM_UDP := {
	53: "domain", 67: "bootps", 68: "bootpc", 69: "tftp", 123: "ntp", 161: "snmp", 162: "snmp-trap",
	500: "isakmp", 514: "syslog", 5353: "mdns",
}

## A default scan covers this many ports, all of them at or below 1023 plus the
## common ones above it. It is a model of nmap's "top 1000", not its list: a lab
## port outside both groups is found only with -p.
const DEFAULT_SCAN_SIZE := 1000


static func nmap_name(port: int) -> String:
	return NMAP_TCP.get(port, "unknown")


static func system_name(port: int, proto: String) -> String:
	if proto == "udp":
		return SYSTEM_UDP.get(port, "")
	return SYSTEM_TCP_OVERRIDES.get(port, NMAP_TCP.get(port, ""))


## Every table port with exactly this service name (for `nmap -p http`).
static func ports_named(name: String) -> Array:
	var out: Array = []
	for p in NMAP_TCP:
		if NMAP_TCP[p] == name:
			out.append(p)
	out.sort()
	return out


static func in_default_scan(port: int) -> bool:
	return (port >= 1 and port <= 1023) or NMAP_TCP.has(port)
