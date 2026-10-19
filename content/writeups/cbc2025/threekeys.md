+++  
title = "threekeys"  
date = 2025-11-28  
draft = false  
tags = ["reverse", "crypto", "aes", "htb"]  
categories = ["writeups"]  
ctf = "hackthebox"  
points = 0  
solves = 0  
+++  

## tl;dr  

reverse a 64‑bit linux elf that does triple aes decryption with three hardcoded keys, realize the function names are lying to me, brute force the key order in python until the plaintext starts with `htb{...}`, question my life choices throughout.

## what we’re dealing with  

the challenge gives a single binary `threekeys`, no source, no hints beyond the very subtle and not at all ominous description: *you've gathered the three secret keys and you're ready to claim your prize. but in your rush, the keys have got mixed up - which one goes where?*

there’s also a lovely `htb` string in the binary (`"htb"` right next to the error message), so i know there’s a flag check somewhere and that i’m about to get bullied by crypto.

## initial recon (aka pretending i know what i’m doing)  

i started by asking the traditional oracle of all binaries, `file`:  

```bash  
file threekeys
```

output:  

```bash  
threekeys: ELF 64-bit LSB pie executable, x86-64, dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, not stripped
```

64‑bit, pie, dynamically linked, not stripped. so, in theory, “easy”. in practice, i will still manage to suffer.

then `checksec`, because i enjoy pain:  

```bash  
checksec --file=threekeys
```

standard htb setup: pie on, nx on, no obvious pwn, so this screams “rev/crypto” instead of “smash the stack”.  

`strings threekeys` is where it starts to get interesting:  

```bash  
strings threekeys | grep -i -E 'key|aes|htb|\[\*\]'
```

i see:  

- `aes_set_decrypt_key`  
- `aes_decrypt`  
- `key1`, `key2`, `key3`  
- `the_first_key`, `the_second_key`, `the_third_key`  
- `ct`  
- messages:  
  - `[*] insert the three keys to claim your prize!`  
  - `[*] just be careful to insert them in the right order...`  
  - `...something's wrong`  
  - `[*] your prize is: %s`  

so at this point, my big brain hypothesis is: “this is some kind of 3des‑style triple aes thing and i’ll just reimplement it in python.” narrator: i would not, in fact, *just* do that.

## understanding the binary (bold claim)  

i threw `threekeys` into ghidra and, as usual, stared at it blankly for a few minutes pretending to parse the decompiler while my brain rebooted.

the decompiled `main` looks (simplified) like this:  

```c
int main(void) {
    evp_pkey_ctx *ctx;
    char *out;
    unsigned char *k;
    size_t in_R8; // some length arg

    ctx = malloc(0x20);
    out = malloc(0x20);

    // ctx gets initialized from four qwords in .data
    *(uint64_t *)ctx       = CT;
    *(uint64_t *)(ctx + 8) = DAT_001040c8;
    *(uint64_t *)(ctx +16) = DAT_001040d0;
    *(uint64_t *)(ctx +24) = DAT_001040d8;

    puts("[*] insert the three keys to claim your prize!");
    puts("[*] just be careful to insert them in the right order...");

    k = (unsigned char *)the_third_key();
    decrypt(ctx, (unsigned char *)out, (size_t *)0x2, k, in_R8);
    memcpy(ctx, out, 0x20);

    k = (unsigned char *)the_second_key();
    decrypt(ctx, (unsigned char *)out, (size_t *)0x2, k, in_R8);
    memcpy(ctx, out, 0x20);

    k = (unsigned char *)the_first_key();
    decrypt(ctx, (unsigned char *)out, (size_t *)0x2, k, in_R8);
    memcpy(ctx, out, 0x20);

    if (memcmp(out, &DAT_00102071, 3) != 0) {
        out = "...something's wrong";
    }

    printf("[*] your prize is: %s\n", out);
    return 0;
}
```

yes, that’s right. despite all the “insert the keys” talk, there is exactly zero user input. absolutely none. the binary gaslights you straight from the start.

then the key functions:  

```c
aes_key *the_first_key(void) {
    aes_key *key = malloc(0xf4);
    aes_set_decrypt_key(KEY3, 0x80, key);
    return key;
}

aes_key *the_second_key(void) {
    aes_key *key = malloc(0xf4);
    aes_set_decrypt_key(KEY2, 0x80, key);
    return key;
}

aes_key *the_third_key(void) {
    aes_key *key = malloc(0xf4);
    aes_set_decrypt_key(KEY1, 0x80, key);
    return key;
}
```

so:  

- `the_third_key()` → uses `key1`  
- `the_second_key()` → uses `key2`  
- `the_first_key()` → uses `key3`  

beautiful. the function names are lying, the description is lying, and i’m still here trusting anything.

`decrypt()` itself wraps `aes_decrypt` with that `aes_key`, and the third argument being `0x2` strongly suggests “two blocks”, i.e., 32 bytes of ciphertext.

so the high‑level flow is:  

1. copy 32 bytes of ciphertext into `ctx` from `.data` (four qwords).  
2. call `decrypt` 3 times with different keys.  
3. each time, write the decrypted 32 bytes back into `ctx`.  
4. at the end, if first three bytes of `out` are `"htb"`, print it as the flag. otherwise print sadness.

triple aes‑128 in ecb, essentially 3des but make it aes and annoying.  

## digging deeper (into my own confusion)  

next step: find where those keys and the ciphertext actually live. i did the extremely advanced thing of grepping my own hex dump like a script kiddie:  

```bash  
xxd threekeys > dump.txt
```

then i skimmed around `.data`. eventually i stopped roleplaying a byte editor and used `readelf` like a functioning adult:  

```bash  
readelf -s threekeys | grep -E 'KEY|CT|DAT_00104'
```

this gave me the money line:  

```text  
52: 0000000000004080    16 OBJECT  GLOBAL DEFAULT   24 KEY1
59: 00000000000040c0    32 OBJECT  GLOBAL DEFAULT   24 CT
63: 0000000000004090    16 OBJECT  GLOBAL DEFAULT   24 KEY2
71: 00000000000040a0    16 OBJECT  GLOBAL DEFAULT   24 KEY3
```

so in `.data` we have, starting at virtual `0x4060`:  

- `key1 @ 0x4080`  
- `key2 @ 0x4090`  
- `key3 @ 0x40a0`  
- `ct  @ 0x40c0`  

mapping that back to file offsets from the hex dump (pie base shenanigans mean it’s basically `.data vaddr - 0x1000` in this case):

```text  
0x3080: f2 e7 bf d7 53 c6 4b 26 97 f9 69 87 e6 84 28 e8  # looks key-ish
0x3090: dc f9 90 26 92 27 33 67 24 08 c6 45 51 c7 3a 33  # also spicy
0x30a0: ee 31 ce d8 10 70 40 a0 d9 53 cf 57 32 79 73 d5  # and this
0x30b0: 00 ... 00                                       # boring zeros
0x30c0: 8c eb c8 65 43 48 46 a6 98 05 e8 42 2f 3f 80 9f  # hi ct
0x30d0: a8 c9 b3 7d 28 1a d8 3e aa ba 1a 2b e9 8f b7 6c  # more ct
```

in my first act of genius, i decided the first 32 bytes were the ciphertext and the rest were keys. because why read the symbol table you just asked for. that mistake costs me a good chunk of time.  

after i, very belatedly, read my own `readelf` output again, the actual mapping is:  

- `key1 = 0x3080` → `f2e7bfd753c64b2697f96987e68428e8`  
- `key2 = 0x3090` → `dcf99026922733672408c64551c73a33`  
- `key3 = 0x30a0` → `ee31ced8107040a0d953cf57327973d5`  
- `ct  = 0x30c0 || 0x30d0` → `8cebc865434846a69805e8422f3f809f a8c9b37d281ad83eaaba1a2be98fb76c`  

so yes, i spent a depressing amount of time decrypting the keys *with themselves* and then wondering why the output looked like pure garbage.  

## the actual work begins (aka suffering)  

with the keys and ciphertext sorted (eventually), the algorithm is straightforward:  

- mode: `aes-128-ecb` (inferred from `aes_set_decrypt_key` / `aes_decrypt`, no iv, 16‑byte keys).
- data: 32‑byte ciphertext, treated as two blocks.  
- operation: `pt = dec_kx(dec_ky(dec_kz(ct)))` for some permutation of `key1`, `key2`, `key3`.  

the decompiled `main` calls:  

```c
the_third_key();  // uses KEY1
the_second_key(); // uses KEY2
the_first_key();  // uses KEY3
```

so the *baked in* order in the binary is `key1 -> key2 -> key3`. but the challenge description is “the keys got mixed up, which one goes where?”, meaning that order is likely **wrong** and the correct one is some other permutation.

solution space: 3! = 6 permutations. even my caffeine‑starved brain can brute force that.  

so i wrote a decryptor in python with pycryptodome. then i ran it. and got…  

```text  
\x08\x1e\xd0kn\xcf>\x8fz\n\x02:\xf33T\xb6$\xcfYj\xf6\x96LU\xc2 \x13%\xd1W\xf2"
```

no `htb`, no printable anything, just aes doing its job and me not doing mine. this was using the **wrong** keys/ct mapping, so of course it was nonsense.  

## throwing spaghetti at the wall  

this is the part where i try several “galaxy brain” ideas that are all bad.  

- “maybe it’s encrypt, not decrypt” → i swapped `aes_set_decrypt_key` for `aes_set_encrypt_key` in my mental model and tried to invert the order. shockingly, doing the opposite of what the code does didn’t help.
- “maybe each block uses a different key” → i tried decrypting block0 with one permutation and block1 with another, because why not increase the combinatorial explosion for no reason. spoiler: this also sucked.  
- “maybe i should just call `decrypt` from python via `ctypes`” → i briefly considered loading the elf as a shared library just to let its own `decrypt` function do the work. this idea died when i remembered how much i hate debugging `ctypes` segfaults at 3am.  
- “maybe the real magic is in `in_R8`” → i went down a mini rabbit hole in ghidra chasing the `in_R8` param of `decrypt`, thinking maybe some mode of operation weirdness was hiding there. turns out, no, it’s just a length/flag arg that matches the `0x2` blocks thing.  

this is also when i had the classic “did i screw up endianness?” panic. i re‑checked that the bytes i pulled from `.data` were in the same order as the symbol addresses. they were. the bug was, as usual, between chair and keyboard.  

## rabbit holes i enthusiastically dove into  

just to document how efficient i was at wasting time:  

- i wasted a solid half hour convinced the ciphertext was at `0x3080` because that was the first “random‑looking” 16‑byte chunk, and i didn’t cross‑reference with the symbol table properly. beautiful display of selective reading.
- in my infinite wisdom, i tried to “reverse” the aes by *encrypting* instead of decrypting three times, because triple des mental model. this gave me different but equally useless garbage.  
- i even briefly considered that maybe the “mixed up” part meant i had to bruteforce swapping the **function pointers** in the plt/got and re‑running the binary, instead of just trying key order permutations in python. future me would very much like to slap past me for that one.  
- there was also a glorious 10 minutes where i thought maybe the first three bytes were checked against something *other than* `"htb"`, even though the string `"htb"` is literally sitting right there in `.rodata` next to the error message. reading is hard.

## exploitation strategy (using that word loosely)  

after untangling my own mess, i settled on the only sane approach:  

- take the **actual** `key1`, `key2`, `key3` from `.data` using the symbol table offsets.
- take the **actual** `ct` (32 bytes at `ct` symbol).  
- reimplement exactly what `decrypt` does: `aes-128-ecb` over 2 blocks.  
- brute force all 6 permutations of the three keys:  

\[
pt = \text{dec}_{k_{\pi(1)}} \left( \text{dec}_{k_{\pi(2)}} \left( \text{dec}_{k_{\pi(3)}}(ct) \right) \right)
\]  

- for each candidate `pt`, check if it starts with `"htb"` and is mostly printable.  

no patching, no dynamic instrumentation, just bullying aes with a for‑loop.  

## actually getting it to work (shocking)  

here’s the final script i ended up with, after fixing approximately 47 stupid mistakes (wrong offsets, swapped keys, forgetting to join the two ciphertext blocks, you name it):  

```python
#!/usr/bin/env python3
# threekeys solver - brute forcing my way through crypto like a true professional

from Crypto.Cipher import AES
import itertools

# keys as extracted from .data using readelf/hex dump
# key1 @ 0x4080  (file offset 0x3080)
KEY1 = bytes.fromhex("f2e7bfd753c64b2697f96987e68428e8")
# key2 @ 0x4090  (file offset 0x3090)
KEY2 = bytes.fromhex("dcf99026922733672408c64551c73a33")
# key3 @ 0x40a0  (file offset 0x30a0)
KEY3 = bytes.fromhex("ee31ced8107040a0d953cf57327973d5")

# ct @ 0x40c0 (file offset 0x30c0 / 0x30d0), 32 bytes total
CT = bytes.fromhex(
    "8cebc865434846a69805e8422f3f809f"
    "a8c9b37d281ad83eaaba1a2be98fb76c"
)

def dec_block(data, key):
    """aes-128-ecb single-block decrypt, except we're doing 2 blocks because why not."""
    cipher = AES.new(key, AES.MODE_ECB)
    return cipher.decrypt(data)

def looks_like_flag(b):
    """basic sanity check: starts with 'htb' and mostly printable."""
    if not b.startswith(b"HTB") and not b.startswith(b"htb"):
        return False
    # allow some padding/nulls but mostly ascii
    printable = sum(32 <= c < 127 for c in b)
    return printable >= len(b) - 4

def main():
    keys = [
        ("KEY1", KEY1),
        ("KEY2", KEY2),
        ("KEY3", KEY3),
    ]

    print(f"[*] ciphertext ({len(CT)} bytes): {CT.hex()}")
    print("[*] trying all 6 permutations like a brute-force enjoyer\n")

    for perm in itertools.permutations(keys):
        names = " -> ".join(name for name, _ in perm)
        tmp = CT
        print(f"[+] testing order: {names}")

        for name, key in perm:
            # triple decryption, same as binary does
            tmp = dec_block(tmp, key)

        print(f"    candidate pt (hex): {tmp.hex()}")

        if looks_like_flag(tmp):
            try:
                s = tmp.decode("utf-8", errors="ignore").strip("\x00")
            except UnicodeDecodeError:
                s = repr(tmp)
            print("\n[!] looks good, we have a winner:")
            print(f"    order: {names}")
            print(f"    flag: {s}")
            return

    print("\n[-] none of the permutations produced something flaggy.")
    print("    which means i either messed up the offsets again or should go touch grass.")

if __name__ == "__main__":
    main()
```

yes, this is literally just: “try all permutations and pray”. yes, it works. no, i’m not proud.  

once i stopped feeding it the wrong bytes and using the wrong order, one of the permutations spat out something that started with `htb{` and my terminal finally showed mercy.  

## flag  

the flag popped out as a nice `htb{...}` string after way too many cycles of “let me just fix one more bug”. perfectly reasonable challenge, completely unreasonable amount of self‑inflicted suffering.  

i’m not pasting the full flag here because screenshots or it didn’t happen and also because you should earn your own trauma, but trust me: the moment `htb{` appeared on screen, i briefly ascended. then i remembered i’d just brute‑forced six permutations and felt slightly less smart again.
