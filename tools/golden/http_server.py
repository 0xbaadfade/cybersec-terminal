"""A minimal web server that sends exactly the bytes tools/golden/lab_net.sh
wants curl to see. It stands in for web-03 (10.20.0.10:80); a second instance
accepts connections on 10.20.0.30:80 and closes them without a reply (a port
that is open but does not speak HTTP). Never serves files: the table is below."""
import socket
import sys
import threading

BODY = b"<html><head><title>Corp web tier</title></head><body>It works.</body></html>\n"
OLD = b'<html><body>Moved: <a href="https://web-03.corp.local/">here</a>.</body></html>\n'
FORBIDDEN = b"<html><body>Forbidden.</body></html>\n"
NOT_FOUND = b"<html><body>Not Found.</body></html>\n"
COMMON = [
    ("Server", "Apache/2.4.6 (CentOS)"),
    ("X-Powered-By", "PHP/5.4.16"),
]
ROUTES = {
    "/": (200, "OK", COMMON + [("Last-Modified", "Mon, 02 Nov 2026 09:14:03 GMT"),
                                ("ETag", '"4d-5f2c1a7c0b4d3"'), ("Accept-Ranges", "bytes")], "text/html; charset=UTF-8", BODY),
    "/old": (301, "Moved Permanently", COMMON + [("Location", "https://web-03.corp.local/")], "text/html; charset=iso-8859-1", OLD),
    "/admin": (403, "Forbidden", COMMON, "text/html; charset=iso-8859-1", FORBIDDEN),
}


def reply(conn):
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = conn.recv(4096)
        if not chunk:
            return
        data += chunk
    method, path = data.split(b"\r\n", 1)[0].decode().split(" ")[:2]
    status, reason, headers, ctype, body = ROUTES.get(path, (404, "Not Found", COMMON, "text/html; charset=iso-8859-1", NOT_FOUND))
    out = "HTTP/1.1 %d %s\r\nDate: DATE\r\n" % (status, reason)
    for k, v in headers:
        out += "%s: %s\r\n" % (k, v)
    out += "Content-Length: %d\r\nContent-Type: %s\r\n\r\n" % (len(body), ctype)
    conn.sendall(out.encode() + (b"" if method == "HEAD" else body))


def serve(addr, speaks_http):
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(addr)
    s.listen(16)
    while True:
        conn, _ = s.accept()
        try:
            if speaks_http:
                reply(conn)
            else:
                conn.recv(4096)  # read the request, then hang up without answering
        except Exception:
            pass
        conn.close()


threading.Thread(target=serve, args=(("10.20.0.30", 80), False), daemon=True).start()
serve((sys.argv[1], 80), True)
