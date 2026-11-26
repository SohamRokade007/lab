#pip install pycryptodome(Do this first in terminal)
from Crypto.Cipher import DES
from Crypto.Util.Padding import pad, unpad

key = input("Enter 8-character key: ").encode()

if len(key) != 8:
    print("Key must be exactly 8 bytes!")
else:
    msg = input("Enter message: ").encode()

    # Encryption
    cipher = DES.new(key, DES.MODE_ECB)
    enc = cipher.encrypt(pad(msg, 8))
    print("Encrypted:", enc.hex())

    # Decryption
    cipher = DES.new(key, DES.MODE_ECB)
    dec = unpad(cipher.decrypt(enc), 8)
    print("Decrypted:", dec.decode())