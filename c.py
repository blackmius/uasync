import socket

from aioquic.quic.connection import QuicConnection
from aioquic.quic.configuration import QuicConfiguration

config = QuicConfiguration()
conn = QuicConnection(configuration=config)

conn.connect(('127.0.0.1', 4567), 0)
print()

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, 0)

for data, addr in conn.datagrams_to_send(0):
    s.sendto(data, addr)
