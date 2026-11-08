"""Sockets for the ss/netstat goldens: tcp 127.0.0.1:631, 0.0.0.0:22, 0.0.0.0:80,
udp 127.0.0.1:5353, 0.0.0.0:68, and one established connection to port 22."""
import socket
import threading
import time


def tcp(addr, port):
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((addr, port))
    s.listen(5)
    while True:
        c, _ = s.accept()
        threading.Thread(target=lambda c=c: (time.sleep(600), c.close()), daemon=True).start()


def udp(addr, port):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind((addr, port))
    time.sleep(600)


for addr, port in (("0.0.0.0", 22), ("127.0.0.1", 631), ("0.0.0.0", 80)):
    threading.Thread(target=tcp, args=(addr, port), daemon=True).start()
    time.sleep(0.05)
for addr, port in (("0.0.0.0", 68), ("127.0.0.1", 5353)):
    threading.Thread(target=udp, args=(addr, port), daemon=True).start()
time.sleep(1)
client = socket.create_connection(("127.0.0.1", 22))
time.sleep(600)
