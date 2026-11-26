import math

def is_prime(n):
    if n < 2:
        return False
    for i in range(2, int(n**0.5) + 1):
        if n % i == 0:
            return False
    return True

p = int(input("Enter prime number p: "))
q = int(input("Enter prime number q: "))

if not is_prime(p) or not is_prime(q) or p == q:
    print("Enter two distinct prime numbers!")
else:
    n = p * q
    phi = (p - 1) * (q - 1)

    e = 2
    while e < phi:
        if math.gcd(e, phi) == 1:
            break
        e += 1

    d = pow(e, -1, phi)

    print("Public Key:", e, n)
    print("Private Key:", d, n)

    msg = int(input("Enter message (number): "))

    if 0 <= msg < n:
        enc = pow(msg, e, n)
        print("Encrypted:", enc)

        dec = pow(enc, d, n)
        print("Decrypted:", dec)
    else:
        print("Message must be between 0 and", n - 1)