#!/usr/bin/env python3
"""Independent suite-17 synthetic vectors. Standard-library HMAC + OpenSSL CLI.
No network, real identifiers, credentials, or capture files are used.
"""
import hashlib
import hmac
import json
import shutil
import struct
import subprocess

username = b"tester"
password = b"synthetic-password".ljust(20, b"\0")
console_id, bmc_id = 0x11223344, 0x55667788
console_random = bytes(range(16))
bmc_random = bytes(range(16, 32))
guid = bytes(range(32, 48))
role_name = bytes([2, len(username)]) + username
mac = lambda key, data: hmac.new(key, data, hashlib.sha256).digest()
u32 = lambda n: struct.pack("<I", n)

rakp2 = mac(password, u32(console_id) + u32(bmc_id) + console_random + bmc_random + guid + role_name)
sik = mac(password, console_random + bmc_random + role_name)
k1, k2 = mac(sik, b"\x01" * 20), mac(sik, b"\x02" * 20)[:16]
rakp3 = mac(password, bmc_random + u32(console_id) + role_name)
rakp4 = mac(sik, console_random + u32(bmc_id) + guid)[:16]
plain = bytes.fromhex("2018c88100017e")
pad = (-(len(plain) + 1)) % 16
padded = plain + bytes(range(1, pad + 1)) + bytes([pad])
iv = bytes(range(48, 64))
openssl = shutil.which("openssl")
cipher = subprocess.run([openssl, "enc", "-aes-128-cbc", "-K", k2.hex(), "-iv", iv.hex(), "-nopad"], input=padded, stdout=subprocess.PIPE, check=True).stdout
packet = bytes.fromhex("0600ff0706c0") + u32(bmc_id) + u32(1) + struct.pack("<H", len(iv + cipher)) + iv + cipher
pad = (-(len(packet) - 4 + 2)) % 4
packet += b"\xff" * pad + bytes([pad, 7])
packet += mac(k1, packet[4:])[:16]
print(json.dumps({name: data.hex() for name, data in dict(rakp2=rakp2, sik=sik, k1=k1, k2=k2, rakp3=rakp3, rakp4=rakp4, packet=packet).items()}, indent=2))
