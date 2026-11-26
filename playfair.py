def playfair(text, key, mode):
    s = "".join(dict.fromkeys((key + "ABCDEFGHIJKLMNOPQRSTUVWXYZ").replace("J", "I")))
    pos = {c: (i // 5, i % 5) for i, c in enumerate(s)}

    text = text.upper().replace("J", "I")
    text = "".join(c for c in text if c.isalpha())

    pairs = []
    i = 0

    while i < len(text):
        a = text[i]
        b = text[i+1] if i+1 < len(text) else "X"

        if a == b:
            pairs.append((a, "X"))
            i += 1
        else:
            pairs.append((a, b))
            i += 2

    res = ""

    for a, b in pairs:
        r1, c1 = pos[a]
        r2, c2 = pos[b]

        if r1 == r2:
            res += s[r1*5+(c1+mode)%5] + s[r2*5+(c2+mode)%5]
        elif c1 == c2:
            res += s[((r1+mode)%5)*5+c1] + s[((r2+mode)%5)*5+c2]
        else:
            res += s[r1*5+c2] + s[r2*5+c1]

    return res


text = input("Enter plaintext: ")
key = input("Enter key: ").upper()

enc = playfair(text, key, 1)
dec = playfair(enc, key, -1)

print("ENCRYPTED:", enc)
print("DECRYPTED:", dec)