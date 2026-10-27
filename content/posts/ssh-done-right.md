+++
title = "ssh done right: what changes when nobody's at the keyboard"
date = "2026-10-27T06:53:24Z"
author = "cleeryy"
authorTwitter = ""
cover = ""
tags = ["homelab", "ssh", "security", "automation"]
keywords = ["openssh", "ed25519", "ssh config", "BatchMode", "IdentitiesOnly", "ProxyJump", "known_hosts", "PerSourcePenalties", "post-quantum ssh", "regreSSHion"]
description = "OpenSSH's defaults are good — for a person sitting at a keyboard. This is how one config file serves both the human path (passphrase, agent, aliases) and the robot path (BatchMode, dedicated keys, forced commands), and where each of them quietly fails."
showFullContent = false
readingTime = true
hideComments = false
+++

*Picture a backup job at 03:00 that calls `ssh`. The key has a passphrase. Nobody is there to type it, so `ssh` waits — and the job doesn't fail, it hangs, until the far end gives up. Nothing in that story is a cryptography problem. It's a design problem: ssh's defaults assume a human is watching, and most of what "doing ssh right" means is deciding, deliberately, which decisions you keep for yourself and which ones you hand to a machine.*

## the prompt is the design

You can read a client's assumptions straight out of it. `ssh -G <host>` prints the configuration ssh will actually use, after every `Host` and `Match` block has been matched and every `%` token expanded — not what you wrote, what it decided. On a stock Debian 13 client, three of those lines tell the whole story:

```text
batchmode no
stricthostkeychecking ask
connecttimeout none
```

Read them as sentences about a person. *May I ask you for a passphrase? Yes.* *Is that host key okay? I'll ask you.* *How long should I wait for the network? Forever, you're right there.* Every one of those prompts is the client delegating a decision to whoever is at the keyboard — and every delegation point is a place where automation either blocks, or gets "fixed" by someone in a hurry.

The hasty fix is well known because it's easy: `StrictHostKeyChecking=no`, a key with no passphrase, copied to every host, `PermitRootLogin yes`, done. That works, in the sense that the script goes green. It also converts authentication from "prove you hold this key" into "reach the port", because a client that accepts a changed host key will happily complete a handshake with whoever answered first. The failure isn't loud. It just removes a control you thought you had.

So the useful split isn't "secure" versus "convenient". It's two paths with different rules: the **human path**, where prompts are fine and strictness is free, and the **robot path**, where nothing may prompt and the safety has to be built somewhere other than a dialogue. The rest of this piece is how one `~/.ssh/config` serves both, and where each path breaks.

## a fork that became the standard

Worth knowing what we're configuring, because "ssh" barely means one thing anymore. The protocol was written in 1995 by Tatu Ylönen at Helsinki University of Technology, after a password-sniffing attack on the university network made plain-text `telnet` and `rlogin` untenable. He released it as free software in July 1995, and it spread quickly through universities and ISPs. Then the usual thing happened — a company formed around it, later versions tightened their licence, and the last release free enough to reuse was 1.2.12.

That dead end is where OpenSSH starts. Early in 1999, Björn Grönvall picked up 1.2.12 and started fixing bugs; his version, OSSH, spoke only SSH 1.3. The OpenBSD project learned about it less than two months before the 2.6 release, decided they wanted ssh in the base system, and forked it on 26 September 1999. OpenSSH 1.2.2 shipped with OpenBSD 2.6 on 1 December 1999. SSH-2 support, largely Markus Friedl's work, arrived in OpenSSH 2.0 with OpenBSD 2.7 in June 2000. That lineage is why `ssh -V` on a modern Linux box still prints a `p` — portable — after the version: you are running the OpenBSD code, adjusted to build everywhere.

The project is still maintained by the same small group of people — Damien Miller, Markus Friedl, Darren Tucker, Theo de Raadt — and it is now at 10.6, released 6 October 2026. It is also, in practice, *the* implementation: Dropbear covers embedded devices, PuTTY and plink still hold the Windows corner (and appear in a surprising number of CI images), libssh and Go's `x/crypto/ssh` carry it into applications, and Teleport, Tailscale SSH and Warpgate build session layers on top. Almost every server you have ever touched answered with OpenSSH.

Its strengths are unglamorous: a complete SSH-2 implementation, three decades of hostile attention, and defaults that repeatedly led the industry rather than following it — Curve25519 key exchange by default in 2014, a hybrid post-quantum key exchange by default in 2022, years before that became fashionable elsewhere. Its weaknesses are equally real. It's C. The configuration surface is enormous. And both config files are first-match-wins in ways people misremember: `sshd_config` takes the first value it sees for a keyword, while several client options *accumulate* instead of overriding — `IdentityFile` can appear five times. That's precisely how a laptop ends up offering six keys to a server that will only look at six attempts.

## what an ed25519 key actually is

The key type everyone recommends has a paper behind it, and the paper is unusually blunt about why. In 2011, Daniel J. Bernstein, Niels Duif, Tanja Lange, Peter Schwabe and Bo-Yin Yang published *High-speed high-security signatures*: 32-byte public keys, 64-byte signatures, a 128-bit security level, and — on a $390 quad-core from the era — 108,000 signatures per second. The properties that matter for ssh are less about speed than about hygiene: signing is deterministic (the nonce is derived from the key and the message, so a weak random generator at signing time can't leak the key), and there is no data flow from secret values into array indices or branch conditions, which removes a whole family of side-channel worries.

OpenSSH picked it up in 6.5 on 30 January 2014, alongside a new private-key format protected by bcrypt — the two arrived together, and that pairing is still what you get by default. As of 9.5 (October 2023), `ssh-keygen` generates Ed25519 keys with no `-t` at all.

The size is the underrated part. On this machine, an Ed25519 keypair is an 87-byte public line (68 characters of base64) and a 444-byte private file. That is small enough to paste into an Ansible variable, to grep across a hundred `authorized_keys` files, and to compare at a glance when something changed. Compare that to the RSA key still sitting on one of my machines: thousands of bytes, generated years ago, indistinguishable from any other line in the file, and no longer the right answer to any question.

Two honest limits, because "use ed25519" is repeated so often it has stopped being an argument:

**Verification is not perfectly standardized.** A 2020 paper, *Taming the many EdDSAs* (Chalkias, Garillot, Nikolaenko), tested popular libraries against edge-case vectors and found that most did not comply with the latest standardization recommendations — signature verification equations, binding and malleability guarantees differ between implementations. Inside an all-OpenSSH fleet this is academic. The moment the same key has to verify through a Go library, libssh or an old PuTTY, it becomes the sort of thing that works for years and then doesn't.

**It is not post-quantum — but the session is.** This distinction gets blurred constantly. Since 9.0 (April 2022) OpenSSH negotiates a hybrid post-quantum key *exchange* by default; since 10.0 (April 2025) the default is `mlkem768x25519-sha256`, and since 10.1 it warns when a connection falls back to a non-PQ exchange. That protects the channel against "record now, decrypt later". Your *signature* is still classical Ed25519 — 10.6 has just added a hybrid `ssh-mldsa44-ed25519` signature scheme, which tells you where that migration is. So: confidentiality has a quantum story today, identity doesn't quite. Fine for a homelab, worth knowing before repeating that ssh is post-quantum now.

And for the one key that unlocks everything, the interesting option isn't Ed25519 on disk at all. Since 8.2 (February 2020), OpenSSH supports FIDO tokens: `ed25519-sk` and `ecdsa-sk` keys where the private half never leaves the hardware and every use requires a touch. That is a *human-path* key by construction — it cannot be used by a cron job, which is exactly the point.

## the passphrase, measured

A passphrase-protected key is a file encrypted with a key derived from your passphrase, and `ssh-keygen -a` sets how much work that derivation does — bcrypt_pbkdf rounds. The 10.6 release notes say it plainly: this is a *linear* cost, unlike `bcrypt(3)` which is exponential. Which means the trade is exactly one-for-one: every extra round costs an attacker the same as it costs you.

I measured it on this machine — Debian 13 container, OpenSSH 10.0p2, one run per value, timings include process start and key generation, so treat them as magnitude rather than benchmark:

```text
rounds=16   ms=177
rounds=24   ms=269
rounds=32   ms=339
rounds=64   ms=674
rounds=100  ms=1051
```

Roughly linear, as advertised. The defaults have drifted upward to match: 16 rounds for years, +50% in 9.4 (August 2023) to 24, then 24 → 32 in 10.6 this month. The 10.0 client here still defaults to 24 — readable straight out of the key file, where the `kdfoptions` blob ends with the round count — and I left it there: a quarter of a second at login is not the bottleneck in my day, and a thousand rounds would buy an attacker a second of extra work, not a barrier. The number is a dial, not a virtue.

The important thing is what the passphrase protects against: a stolen file. Laptop taken, backup copied, `~/.ssh` in a synced folder. It does nothing for the key sitting on a server with no passphrase — and that is where automation keys live. You cannot ask a cron job to remember something. So for that path, move the control to the server side, where it doesn't depend on a secret at rest:

```text
from="10.1.50.0/24",command="/usr/local/bin/backup-pull",no-port-forwarding,no-agent-forwarding,no-pty ssh-ed25519 AAAA... backup@pbs-pull
```

That line says: only from that subnet, only that command, no forwarding, no terminal. An empty passphrase on such a key is not negligence, it's an accurate statement that the key's power is not in the key. The same empty passphrase on a key that also gives root shell everywhere is a much bigger claim, usually made by accident.

## the config file is the inventory

The client config earns its place by being the only file where "how do I reach this machine and as whom" is written down once. A block per destination, aliases that scripts can use instead of addresses:

```text
Host pve3
  HostName pve3.example.internal
  User root
  IdentityFile ~/.ssh/id_ed25519_infra
  IdentitiesOnly yes
  ServerAliveInterval 30
  ServerAliveCountMax 3
```

Each line does a job worth naming. `Host` is the alias — the contract. `HostName` is the address, the one place it lives. `IdentityFile` picks the key. `IdentitiesOnly yes` is the line that prevents the classic `Too many authentication failures`: every identity in your agent gets offered in turn, each rejected offer consumes part of the server's `MaxAuthTries` (6 by default — confirmed by `sshd -T` on this lab's node), and the connection dies before the right key is ever tried. `ServerAliveInterval` counteracts the fact that the default is 0: nothing keeps the connection alive, so any middlebox that drops idle TCP after a hundred seconds or so will do exactly that.

`Include` (OpenSSH 7.3, 2016) makes this composable — `Include ~/.ssh/config.d/*` and keep work and lab separate. `Match` makes it contextual: `Match exec`, `Match localnetwork` and `Match tag` (the last two since 9.4) let the same alias route differently at home and away, which is the difference between a config that survives travel and a config with a commented-out jump host.

And when it lies — because a config accumulated over three years always lies somewhere — `ssh -G alias` prints the resolved result. Not what the file says, what ssh will do. It's the cheapest debugging tool in the toolkit and I reach for it before anything involving `-vvv`.

There is an editorial argument hiding here, and it's the same one as the naming convention: an alias is a name, and names should be the interface. Scripts should say `ssh pbs`, never `ssh root@10.1.50.78`. Then the address lives in one file, changes once, and the day the backup server moves nobody has to remember which twelve scripts had it hardcoded.

## the robot path: BatchMode or nothing

For anything unattended, one option is not negotiable:

```text
Host pbs
  BatchMode yes
  ConnectTimeout 10
  StrictHostKeyChecking accept-new
```

`BatchMode yes` disables passphrase prompts *and* host-key confirmation requests. Its purpose is not to make auth succeed — it's to make failure fast and loud instead of silent and slow. Without it, a missing passphrase doesn't produce an error, it produces a hang, and a hang looks identical to "the network is slow" at 03:00.

`ConnectTimeout` is narrower than people assume. The manual is explicit: it applies to establishing the TCP connection and to the initial protocol handshake and key exchange — not to user authentication. So it will not save you from a passphrase prompt. Only `BatchMode` does that.

`StrictHostKeyChecking accept-new` (7.6, 2017) is the sane middle: trust the first contact, refuse a *changed* key. `no` accepts changed keys silently, which is the option that turns a man-in-the-middle into a Tuesday. The real control, though, is provisioning: put the host key in `known_hosts` when you build the machine, and let `accept-new` cover only the genuine first meeting. Note that `known_hosts` is hashed by default (`hashknownhosts yes`), which is good for privacy and means `grep` won't find anything — use `ssh-keygen -F host`.

One thing that has changed recently and that script writers should internalize: sshd now has memory. Since 9.8 (July 2024) `PerSourcePenalties` is on by default: an address that keeps failing authentication, keeps connecting without authenticating, or crashes a server process accrues penalties, and once above a minimum threshold every connection from that address — and its CIDR block — is refused until they expire. This lab's node reports `authfail:5 min:15 max:600`, i.e. a retry loop that just keeps hammering can lock its own source out for up to ten minutes, including the connection that would have worked. If you run a bastion or a monitoring scanner, `PerSourcePenaltyExemptList` exists for exactly that. And 10.6 refined the accounting so that *probing* a key the server doesn't accept no longer burns the same budget as a real failed attempt — helpful if your agent is loaded, not a substitute for `IdentitiesOnly`.

Two small traps for scripts, both older than any of this. `ssh -n` redirects stdin from `/dev/null`, without which `ssh` inside a `while read` loop eats the loop's input and the loop mysteriously runs once. And `ssh -T` skips tty allocation, which is what you want when the output is going into a parser rather than a terminal.

## when a bastion sits in front

The pattern that makes a homelab feel like an infrastructure: one entry point, everything else unreachable from outside. `ProxyJump` (7.3) is how you should use it rather than nesting `ssh bastion ssh target`. With `ProxyJump bastion`, the client authenticates to the bastion, asks it to relay a TCP stream (`-W`), and then authenticates *to the target* end-to-end. Your key never lands on the bastion, `scp` and `rsync` work normally, and the target's host key is still the target's — the trust chain doesn't collapse just because there's a hop.

Three things break in practice, and this lab has met each of them:

**Banners end up in your stdout.** If the bastion prints a login banner, every non-interactive command comes back with prose glued to the front of the output. In this lab the scripts prefix `echo __OUT__;` to the remote command and filter with `sed -n '/__OUT__/,$p'`. It works, it's ugly, and it's the correct shape of the fix: a sentinel line, because you cannot parse around an unknown preamble. The nicer fix is a bastion that stays quiet in non-interactive sessions.

**Idle connections die.** Proxies, CDNs and NAT devices drop TCP that has been silent for a while; the bastion in front of this lab sits behind something that gives up around a hundred seconds. `ServerAliveInterval 30` with a count of 3 is the cheap insurance, and its absence looks exactly like "the server is flaky".

**The bastion's host-key policy becomes yours.** If the bastion auto-accepts host keys for the targets behind it, then the verification that used to happen in your client now happens — or doesn't — at the hop. Inside one VLAN that's a reasonable trade. Across an untrusted network it isn't, and it's worth knowing which one you're doing rather than assuming the `known_hosts` guarantee still holds end to end.

## the other end, and the honest gap

Client discipline doesn't compensate for a server that says yes to everything. The server-side minimum is short and boring: `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `PermitRootLogin prohibit-password`, an `AllowUsers` or group restriction, and a `MaxAuthTries` you've actually thought about. Verify with `sshd -T`, not by reading the file — the effective config after all `Match` blocks and includes is frequently not what you think you wrote.

And then there's the part no key policy fixes. On 1 July 2024, Qualys disclosed CVE-2024-6387, "regreSSHion": a signal-handler race in `sshd` on glibc-based Linux that allowed unauthenticated remote code execution as root. It affected OpenSSH 8.5p1 up to — but not including — 9.8p1, and it was a *regression* of a bug patched in 2006, reintroduced by the accidental removal of a critical component. The lesson isn't "ssh is insecure"; it's that `sshd`'s pre-authentication code is the exposed surface, it runs with privilege, and your beautiful `authorized_keys` hygiene does nothing about it. The structural answer arrived in 10.0: the authentication phase was moved into a separate `sshd-auth` binary so that pre-auth code has a disjoint address space from the rest of the connection. Until you're on 10.x, patch cadence is the control.

Which brings me to the part that would be tempting to leave out. This lab is not uniform. A couple of older machines still carry RSA keys generated before any convention existed, and at least one still answers password authentication. They're behind the bastion, they're on a list, and the list is short — but "short" is not "empty", and an article that claims uniformity would be advertising rather than documentation.

## six questions for your own setup

Not a checklist to copy, a set of probes worth running before you trust your own setup:

1. **If I remove the human, what happens?** Run the exact command your cron runs, from the same user, with no agent loaded. If it prompts, it hangs in production.
2. **Which keys can reach this host?** `authorized_keys` plus every key that ever got copied and never removed. The count is usually higher than the number you'd name from memory.
3. **Does this key need a shell, or one command?** Most automation keys need one command. `command=` says so, and turns a stolen key from "the machine" into "the one script".
4. **Who can add to my `known_hosts`?** Trust-on-first-use is a decision, and it's only a good one if the *first* use is on a network you trust.
5. **If this key is stolen tonight, what does the thief get?** If the answer is "everything", that's the finding — not the key type.
6. **When was `sshd` last updated, and what does `sshd -T` say?** The file is a proposal; `-T` is the state.

## the five-second version

The cryptography is the easy part, and it's already done for you: Ed25519 is a good default, the key exchange has been hybrid post-quantum since 2022, and the private-key format has been bcrypt-protected since 2014. The work is elsewhere — in deciding which prompts belong to a person and which must be replaced by a rule the server enforces, in writing those decisions into one file that scripts can rely on, and in remembering that `sshd` itself is a networked program with a history of pre-auth bugs.

Do that and ssh stops being the thing you type and becomes the interface your infrastructure is described by: `ssh pbs` means the backup server, and it means it the same way at 14:00 and at 03:00, with or without you in the room.

*Next in the foundations phase: containers in ten minutes — images, volumes, and the first service that earns its uptime.*
