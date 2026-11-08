class_name SimWinTools
extends RefCounted
## Helpers shared by the Windows-flavoured tools. Everything here is UNVERIFIED
## against a real Windows machine (README "Phase 4c-2 as built").

const MONTHS: Array = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
		"October", "November", "December"]
const DAYS: Array = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]


## Windows accepts /x as well as -x; the flag parser knows only the dash.
static func dash_options(argv: Array) -> Array:
	return argv.map(func(a): return ("-" + (a as String).substr(1)) if (a as String).length() == 2 and (a as String).begins_with("/") and (a as String)[1].to_lower() != (a as String)[1].to_upper() else a)


## "00-11-22-AA-BB-CC" from the lab's colon-separated MAC.
static func mac_dashes(mac: String) -> String:
	return mac.to_upper().replace(":", "-")


## "Friday, November 6, 2026 9:14:03 AM", as ipconfig prints a lease time.
static func lease_time(unix: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(unix)
	var hour12: int = d["hour"] % 12
	if hour12 == 0:
		hour12 = 12
	return "%s, %s %d, %d %d:%02d:%02d %s" % [DAYS[d["weekday"]], MONTHS[d["month"] - 1], d["day"], d["year"],
			hour12, d["minute"], d["second"], "AM" if d["hour"] < 12 else "PM"]


## A stable IPv6 link-local address for a workstation (Windows uses a random
## interface id, not the MAC).
static func link_local(lab: SimLab) -> String:
	var rng := SimNet.rng_for(lab.seed_value, "ipv6:" + lab.you["name"])
	var groups: Array = []
	for _n in 4:
		groups.append("%x" % rng.randi_range(0x1000, 0xffff))
	return "fe80::" + ":".join(groups)


## "10.20.0.50" -> "255.255.255.0" for the lab network's prefix.
static func netmask(lab: SimLab) -> String:
	var prefix := int(lab.cidr()["prefix"])
	return SimNet.ip_string((0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF)
