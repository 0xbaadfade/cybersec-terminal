class_name SimSockets
extends RefCounted
## The workstation's sockets as ss and netstat list them, built from the lab:
## the listening ports of the learner's own machine and its open connections.
## Both tools share this selection; each prints its own layout.


## Rows {proto, listening, state (netstat spelling), local_ip, local_port,
## remote_ip, remote_port ("*" when listening), backlog, process, owner, pid, fd}.
## `protos` is a subset of ["tcp", "udp"]; `listening` and `established` pick the
## kinds. Order: udp before tcp for ss, so callers sort by their own rule.
static func rows(lab: SimLab, protos: Array, listening: bool, established: bool) -> Array:
	var out: Array = []
	var fd := 3
	for p in lab.you["ports"]:
		if p["state"] != "open" or not protos.has(p["proto"]):
			continue
		if not listening:
			fd += 1
			continue
		out.append({"proto": p["proto"], "listening": true,
				"state": "LISTEN" if p["proto"] == "tcp" else "",
				"local_ip": p["bind"], "local_port": p["port"], "remote_ip": "0.0.0.0", "remote_port": "*",
				"backlog": p["backlog"] if p["proto"] == "tcp" else 0,
				"process": p["process"], "owner": p["owner"], "pid": _pid(lab, p["process"], p["pid"]), "fd": fd})
		fd += 1
	if established:
		for c in lab.connections:
			if not protos.has(c["proto"]):
				continue
			out.append({"proto": c["proto"], "listening": false, "state": c["state"],
					"local_ip": lab.you["ip"], "local_port": c["local_port"], "remote_ip": c["remote_ip"],
					"remote_port": str(c["remote_port"]), "backlog": 0, "process": c["process"],
					"owner": c["owner"], "pid": _pid(lab, c["process"], c["pid"]), "fd": fd})
			fd += 1
	return out


## The lab's own process id when it gives one, otherwise a stable id per process
## name in the lab.
static func _pid(lab: SimLab, process: String, given: int = 0) -> int:
	if given > 0:
		return given
	if process == "":
		return 0
	return SimNet.rng_for(lab.seed_value, "pid:" + process).randi_range(400, 31999)


## Does the learner see this socket's process? Only their own, as for any
## ordinary user.
static func visible(lab: SimLab, row: Dictionary) -> bool:
	return row["process"] != "" and row["owner"] == lab.you["user"]
