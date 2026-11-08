"""Listeners for the nmap goldens (run inside tools/golden_capture.sh's namespace).

127.0.0.1: tcp 22, 23 (plain) and 80 (a simple HTTP server); 127.0.0.6: tcp 443.
"""
import functools
import http.server
import socket
import tempfile
import threading
import time


def plain(addr, port):
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((addr, port))
    s.listen(5)
    while True:
        c, _ = s.accept()
        c.close()


for addr, port in (("127.0.0.1", 22), ("127.0.0.1", 23), ("127.0.0.6", 443)):
    threading.Thread(target=plain, args=(addr, port), daemon=True).start()
# Serve an empty directory: nothing from the working directory may reach a capture.
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=tempfile.mkdtemp())
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 80), handler)
threading.Thread(target=srv.serve_forever, daemon=True).start()
time.sleep(3600)
