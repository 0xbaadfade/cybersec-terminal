class_name SimNet
extends RefCounted
## Address maths and deterministic randomness for the lab simulator. Pure
## computation: nothing here touches the network.


static func _digits(s: String) -> bool:
	if s == "":
		return false
	for ch in s:
		if ch < "0" or ch > "9":
			return false
	return true


## Dotted quad to a 32-bit integer, or -1 when `text` is not one (leading
## zeros are rejected: "010" is ambiguous).
static func parse_ip(text: String) -> int:
	var parts := text.split(".")
	if parts.size() != 4:
		return -1
	var value := 0
	for p in parts:
		if not _digits(p) or p.length() > 3 or (p.length() > 1 and p.begins_with("0")):
			return -1
		var n := int(p)
		if n > 255:
			return -1
		value = value * 256 + n
	return value


static func ip_string(value: int) -> String:
	return "%d.%d.%d.%d" % [(value >> 24) & 255, (value >> 16) & 255, (value >> 8) & 255, value & 255]


## {"base", "prefix"} for "a.b.c.d/n" with n in 8..30, or {} when it is not one.
static func parse_cidr(text: String) -> Dictionary:
	var parts := text.split("/")
	if parts.size() != 2 or not _digits(parts[1]):
		return {}
	var ip := parse_ip(parts[0])
	var prefix := int(parts[1])
	if ip < 0 or prefix < 8 or prefix > 30:
		return {}
	var mask := (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF
	return {"base": ip & mask, "prefix": prefix}


static func in_cidr(ip: int, cidr: Dictionary) -> bool:
	var mask := (0xFFFFFFFF << (32 - int(cidr["prefix"]))) & 0xFFFFFFFF
	return (ip & mask) == int(cidr["base"])


## A generator seeded from the lab seed and the exact command text, so the same
## command in the same lab prints the same output every time.
static func rng_for(seed_value: int, text: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d|%s" % [seed_value, text]).hash()
	return rng


const _DAYS: Array = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const _MONTHS: Array = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


## "Fri, 06 Nov 2026 11:42:37 GMT", the form of an HTTP Date header.
static func http_date(unix: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(unix)
	return "%s, %02d %s %d %02d:%02d:%02d GMT" % [_DAYS[d["weekday"]], d["day"], _MONTHS[d["month"] - 1], d["year"],
			d["hour"], d["minute"], d["second"]]


## "Fri Nov 06 11:42:37 UTC 2026", the form of dig's WHEN line.
static func dig_date(unix: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(unix)
	return "%s %s %02d %02d:%02d:%02d UTC %d" % [_DAYS[d["weekday"]], _MONTHS[d["month"] - 1], d["day"], d["hour"],
			d["minute"], d["second"], d["year"]]
