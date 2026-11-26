#1
text = input("Enter message: ").upper()
key = int(input("Enter key: "))

enc = ""
for ch in text:
    if ch.isalpha():
        enc += chr((ord(ch) - 65 + key) % 26 + 65)
    else:
        enc += ch

print("Encrypted:", enc)

dec = ""
for ch in enc:
    if ch.isalpha():
        dec += chr((ord(ch) - 65 - key) % 26 + 65)
    else:
        dec += ch

print("Decrypted:", dec)