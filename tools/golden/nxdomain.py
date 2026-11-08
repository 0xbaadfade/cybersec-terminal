"""A DNS server on 127.0.0.1:53 that answers NXDOMAIN to everything."""
import socket
import struct

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("127.0.0.1", 53))
while True:
    data, addr = s.recvfrom(512)
    if len(data) >= 12:
        flags = 0x8183  # response, recursion desired and available, NXDOMAIN
        s.sendto(data[:2] + struct.pack(">HHHHH", flags, 1, 0, 0, 0) + data[12:], addr)
