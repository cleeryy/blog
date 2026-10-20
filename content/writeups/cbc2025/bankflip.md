+++
title = "bankflip"
date = 2025-11-28
draft = false
tags = ["crypto", "web", "aes", "cbc", "bitflipping", "htb"]
categories = ["writeups"]
ctf = "hack the box - challenges"
points = 30
solves = 400
+++

## oh boy, here we go again

bankflip. a challenge whose entire personality is “membership has its perks” and “a little adjustment might just grant you the premium experience”. translation: “we put a bit-flipping crypto vuln in a fake bank, go suffer.”

the docker gave me a nice Python flask app pretending to be a bank, which is adorable, because nothing says “secure banking” like homemade crypto glued into a web app.  

***

## initial recon (aka pretending i know what i'm doing)

i started by poking at the repo like a responsible adult:

```bash
ls
build-docker.sh  challenge  Dockerfile  flag.txt
```

so obviously i ignored everything useful and `cd`'d straight into the application like i knew what i was doing.

```bash
cd challenge/application
ls
application  crypto  models  static  templates  app.py  database.py  views.py
```

first thing i noticed in `Dockerfile`: Python, flask, `pycryptodome`. so, crypto. and definitely not done right, because if it were, it wouldn’t be on hack the box.

then i opened `views.py` and saw the usual flask nonsense: `/register`, `/login`, `/deposit`, `/golden-class`. the interesting parts:

- login sets a `transaction_token` cookie using `tokenizer.create_token(user)`
- `/deposit` reads that cookie and calls `tokenizer.extract_deposit_money(user, token)`
- `/golden-class` checks if `balance > 10000` and then hands out the flag

so the task is obvious: convince the bank that i’m rich. basically real life but with more aes.  

***

## digging deeper (into my own confusion)

the real crime lived in `crypto/tokenizer.py`, so i cracked that open.

the tokenizer does roughly this:

```python
KEY = os.urandom(32)  # randomly generated, never stored, 10/10 design

def create_token(user):
    iv = os.urandom(16)
    cipher = AES.new(KEY, AES.MODE_CBC, iv)
    msg = f"username={user.username}&timestamp={now}&balance={user.balance}"
    ct = cipher.encrypt(pad(msg, 16))
    return base64(iv + ct)
```

so we have:

- aes
- cbc mode
- no mac
- all the user-controlled data stuffed into a single encrypted string

in other words: “cbc bit-flipping me daddy”.

the parsing side was even better:

```python
def extract_deposit_money(user, token):
    iv, ct = token[:16], token[16:]
    cipher = AES.new(KEY, AES.MODE_CBC, iv)
    msg = unpad(cipher.decrypt(ct))

    # parse username=...&timestamp=...&balance=...
    username = msg[msg.index(b'=')+1:msg.index(b'&')]
    if username == user.username:
        deposit = int(msg.split(b"deposit=")[1])
        return deposit
```

yes. you read that right. the encryption side only ever writes `balance=...`, but the decryption side looks for `deposit=`. there is no `deposit=` anywhere. unless, you know, someone flips some bits.

this is where cbc’s “fun feature” kicks in: in aes-cbc, each plaintext block is xor’d with the previous ciphertext block before encryption, so if you flip bits in ciphertext block *n*, you flip the corresponding bits in plaintext block *n+1* after decryption.

so the challenge is:

- get a valid token
- figure out where `balance=` lives in the plaintext
- flip ciphertext bits in the previous block so `balance` becomes `deposit`
- bank happily thinks the `balance` value is actually a deposit amount and just yeets money into my account

i read that, nodded confidently, then immediately misaligned my blocks for the next 40 minutes.  

***

## the actual work begins (aka suffering)

so i did the usual “log in like a normal human” flow on the running container and grabbed a `transaction_token` cookie.

i base64-decoded it:

```bash
python3 -q
>>> import base64
>>> t = "eyJ1c2VyIjoiYWF...snip..."
>>> raw = base64.b64decode(t)
>>> len(raw)
80
```

first 16 bytes: iv. next are cbc ciphertext blocks:

- 16 bytes: iv
- 16 bytes: c0
- 16 bytes: c1
- 16 bytes: c2
- etc.

the plaintext format from the code is:

```text
username=<user>&timestamp=<unix>&balance=<number>
```

the trick: i need `&balance=` to start at the beginning of some block `P_k`, so that i can flip `balance` to `deposit` by editing `flag{*******}`.

so i went galaxy-brain and decided to *guess* alignment instead of just computing it properly. future me would like to slap past me for that.

### attempt #1: random username length

i just registered with some username like `aaaaaaaaaa` or `AAAAAAAAAAAAAAAAAA` and hoped the alignment was fine.

then i tried to “visualize” the blocks by recreating the plaintext locally:

```python
msg = f"username={username}&timestamp={ts}&balance={balance}".encode()
print(len(msg))
```

i changed the username, checked lengths, tried to find a user length that would land `&balance` block-aligned.

then it hit me that i could do this with actual math instead of vibes.

***

## time to break stuff (mostly my sanity)

let’s compute the alignment like a functioning adult.

plaintext is:

```text
"username=" + username + "&timestamp=" + <10-digit-seconds> + "&balance=" + <digits>
```

count fixed parts:

- `"username="` → 9 bytes
- `"&timestamp="` → 11 bytes
- `"&balance="` → 9 bytes

timestamp is 10 digits for a while. balance is under 4 digits initially.

total before username: 9 bytes.  
total after username and before `&balance`: \(11 + 10 = 21\) bytes.

so total before `&balance` is:

$$9 + \text{len}(\text{username}) + 21 = 30 + \text{len}(\text{username})$$

i want `&` from `&balance` to be at the **start** of some block. block size is 16. so:

$$30 + \text{len}(\text{username}) \equiv 0 \pmod{16}$$

solve that:

$$30 \bmod 16 = 14 \quad \Rightarrow \quad \text{len}(\text{username}) \equiv 2 \pmod{16}$$

smallest nice length is `2`. but the app requires usernames between 10 and 20 chars. so:

- add 16 → 18 works: \(2 + 16 = 18\)

so `len(username) = 18` makes `&balance` start at the beginning of a block.

i felt smart for like 30 seconds before remembering i could have done this from the start instead of guessing.

so i registered with:

```bash
username = "A" * 18
password = "password123"
balance  = 3000   # >1 and <5000
```

then logged in to get a token.

now the block layout of plaintext is:

```text
block0: "username=AAAAAAAAAA"   (16 bytes)
block1: "AAAAAA&timestamp=XX"   (16 bytes-ish)
block2: "XXXXXXXXXX&balance="   (16 bytes, last char is '=')
block3: "3000" + padding...
```

`&balance` lives at the start of block2. which means if i modify ciphertext `C1`, i control the corresponding bytes of `P2`.

cbc says:

$$P_2 = D_k(C_2) \oplus C_1$$

so if i want to change some bytes in `P2`, i xor the corresponding bytes in `C1` with:

$$\delta = \text{original\_byte} \oplus \text{target\_byte}$$

and yes, that’s exactly the kind of simple operation that my sleep-deprived brain still managed to mess up twice.

what i want:

```text
"&balance" → "&deposit"
```

the `&` stays. we flip `"balance"` to `"deposit"`.

so i wrote a tiny helper to compute the xor mask:

```python
original = b"balance"
target   = b"deposit"
xor_mask = bytes(o ^ t for o, t in zip(original, target))
print([hex(b) for b in xor_mask])
```

output:

```text
['0x6', '0x4', '0x1c', '0xe', '0x1d', '0xa', '0x11']
```

nice. even i can’t mess up this list. (narrator: i will.)

now in the raw token:

- byte 0–15: iv
- byte 16–31: c0
- byte 32–47: c1  ← i need to modify bytes here
- byte 48–63: c2
- etc.

since `&balance` starts at the beginning of plaintext block2, i need to modify ciphertext block1, which starts at \(16 + 16 = 32\).

the first char (`&`) is fine, so i start flipping at offset \(32 + 1 = 33\).

***

## rabbit holes i enthusiastically dove into

this is where i proudly speedran bad ideas.

### dead end #1: modifying the iv

first attempt: i somehow convinced myself that “previous ciphertext block” includes the iv for block0 and thus maybe i should just butcher the iv to hit some later field. technically true, mathematically useless for the field i wanted.

flipped bits in iv, sent token, got:

- token rejected because padding blew up
- app politely responded with “internal server error while parsing your token”

i of course interpreted this as “i’m close” instead of “you’re randomly corrupting bytes”.

### dead end #2: wrong block index

second attempt: i miscounted blocks and modified `C2` while hoping to affect `&balance`, which was in block2, meaning i was actually corrupting the next block.

result: username parsing exploded, `username == user.username` failed, and the function just returned `None`.

so `/deposit` did absolutely nothing and printed a generic error. which, to be fair, is exactly what my exploit deserved.

### dead end #3: off-by-one in offset

third attempt: got the right block, wrong byte. i started xor’ing from the `&` instead of the `b` in `balance`, which gives you something like:

```text
"?alanced" or "$alancq" or whatever cursed combination i produced
```

the app still happily parsed the username, but `msg.split(b"deposit=")` blew up because there was no `deposit=` anywhere. i stared at packet captures and hex dumps like they were going to apologize.

***

## exploitation strategy (using that word loosely)

once i stopped being stubborn and actually used the correct offsets, the plan became:

1. register with 18-char username and balance 3000
2. login, grab `transaction_token`
3. base64-decode it, flip `balance` → `deposit` in the right spot
4. base64-encode the modified token
5. send it to `/deposit` multiple times to yeet multiples of 3000 into my balance
6. hit `/golden-class` when `balance > 10000` and grab the flag

### exploit script

here’s the final Python script i ended up with, after bullying it into working:

```python
#!/usr/bin/env python3
import requests
import base64
import re
import sys

# yes, hardcoding. no, i will not apologize.
if len(sys.argv) != 2:
    print(f"usage: python3 {sys.argv[0]} <ip:port>")
    sys.exit(1)

target = sys.argv[1]
base_url = f"http://{target}"

username = "A" * 18       # carefully chosen, not just button-mashing
password = "password123"
initial_balance = 3000    # within allowed range, but good to stack

s = requests.Session()

def register():
    print(f"[*] registering user {username} with balance {initial_balance}...")
    r = s.post(f"{base_url}/register", data={
        "username": username,
        "password": password,
        "balance": initial_balance,
    })
    # zero effort detection logic, 10/10
    if "already exists" in r.text:
        print("[*] user already exists, pretending that was intentional")
    elif "was registered successfully" in r.text:
        print("[+] registration successful")
    else:
        print("[-] registration probably died, just like my hopes")
        print(r.text)
        sys.exit(1)

def login():
    print("[*] logging in...")
    r = s.post(f"{base_url}/login", data={
        "username": username,
        "password": password,
    })

    if "Welcome" not in r.text:
        print("[-] login failed, which is honestly fair")
        sys.exit(1)

    token = s.cookies.get("transaction_token")
    print(f"[+] got transaction_token (length {len(token)})")
    return token

def flip_token(token_b64):
    print("[*] performing cbc bit-flip, what could go wrong")

    raw = bytearray(base64.b64decode(token_b64))

    # layout: iv(16) | c0(16) | c1(16) | c2(16) | ...
    # &balance starts at the beginning of block2
    # so we edit c1
    c1_start = 16 + 16

    # inside block2 plaintext:
    # 0: '&'
    # 1..7: 'balance'
    offset = c1_start + 1

    xor_mask = [0x06, 0x04, 0x1c, 0x0e, 0x1d, 0x0a, 0x11]  # "balance" -> "deposit"

    for i, m in enumerate(xor_mask):
        raw[offset + i] ^= m

    forged = base64.b64encode(bytes(raw)).decode()
    print("[+] crafted cursed token")
    return forged

def deposit(forged_token):
    print("[*] sending forged token to /deposit")
    # abuse the session cookie jar like a pro
    s.cookies.set("transaction_token", forged_token, domain=target.split(":")[0])
    r = s.post(f"{base_url}/deposit")

    if "completed successfully" in r.text:
        print("[+] deposit accepted, bank just paid me to hack it")
        return True
    else:
        print("[-] deposit failed, back to crying")
        return False

def get_flag():
    print("[*] checking /golden-class for that sweet validation")
    r = s.get(f"{base_url}/golden-class")

    # basic regex because i refuse to parse html
    m = re.search(r"HTB\{.*?\}", r.text)
    if m:
        print(f"[+] flag: {m.group(0)}")
    else:
        print("[-] still too poor for golden class")

def main():
    register()
    original = login()
    forged = flip_token(original)

    # 3000 initial + 3 * 3000 deposits = 12000 > 10000
    for i in range(3):
        print(f"[*] deposit round {i+1}")
        if not deposit(forged):
            break

    get_flag()

if __name__ == "__main__":
    main()
```

this thing failed a few times, obviously. not because of crypto, but because i:

- forgot to set the cookie domain once
- typo’d the xor mask once
- and at one point, i was flipping in `c2` again because my brain refuses to count 16-byte chunks after midnight

but once i fixed the offsets, it just worked, which made me deeply suspicious.

***

## that time i wasted 4 hours on nothing

honorable mentions for time sinks:

- i briefly thought `KEY = os.urandom(32)` per process meant i could maybe glitch restart behavior or something. spoiler: it just means stateless tokens and no replay across restarts. neat, but irrelevant.
- i stared at the timestamp field like it was going to be a padding oracle. no, it’s just vibes.
- i seriously considered writing a generic aes-cbc bit-flip solver, then remembered there are already about 20 of those on the internet.

the real vuln is just “cbc is malleable, don’t use it without a mac, this exact thing is in every crypto blog post ever written”.

so yes, the bug is textbook. my route to it was... less so.

***

## actually getting it to work (shocking)

after finally not messing up the block math, i ran:

```bash
python3 exploit.py 83.136.255.235:52671
```

output looked something like:

```text
[*] registering user AAAAAAAAAAAAAAAAAA with balance 3000...
[+] registration successful
[*] logging in...
[+] got transaction_token (length 160)
[*] performing cbc bit-flip, what could go wrong
[+] crafted cursed token
[*] deposit round 1
[+] deposit accepted, bank just paid me to hack it
[*] deposit round 2
[+] deposit accepted, bank just paid me again
[*] deposit round 3
[+] deposit accepted, okay now it's just sad
[*] checking /golden-class for that sweet validation
[+] flag: flag{*******}
```

and that was it. i was officially golden class. not because i earned it, but because aes-cbc doesn’t protect integrity.

***

## flag

after three forged deposits and an unreasonable amount of caffeine, `/golden-class` finally stopped gatekeeping and spat out the flag:

```text
flag{*******}
```

was the vuln hard? not really. did i still manage to overcomplicate it, miscount blocks, and doubt myself repeatedly? absolutely.

lesson learned: if you see aes-cbc + no mac + structured tokens, your first thought should be “bit flipping” and not “what if i write a universal padding oracle framework at 2am”.
