#2
msg = input("Message: ").replace(" ", "")
rails = int(input("Rails: "))

fence = [[] for _ in range(rails)]
row, step = 0, 1

for i in range(len(msg)):
  fence[row].append(i)
  if row == 0:
    step = 1
  elif row == rails - 1:
    step = -1
  row += step

order = sum(fence, [])
enc = "".join(msg[i] for i in order)

dec = [""] * len(msg)
for idx, pos in enumerate(order):
  dec[pos] = enc[idx]

print("Encrypted:", enc)
print("Decrypted:", "".join(dec))
