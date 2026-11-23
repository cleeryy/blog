+++
title = "one peer at a time: what wireguard leaves to you"
date = "2026-11-23T03:14:10Z"
author = "cleeryy"
authorTwitter = ""
cover = ""
tags = ["homelab", "networking", "vpn", "wireguard", "opnsense", "remote-access", "cryptography"]
keywords = ["wireguard", "wireguard protocol", "cryptokey routing", "allowedips", "noise protocol", "noise ik", "curve25519", "chacha20-poly1305", "wireguard handshake", "persistent keepalive", "wireguard mtu", "opnsense wireguard", "frebsd if_wg", "road warrior vpn", "kill switch", "always-on vpn", "android lockdown", "openvpn comparison", "tailscale", "netbird", "jason donenfeld", "wireguard history", "wireguard linux 5.6", "wireguard weaknesses"]
description = "My firewall had three tunnels up at four in the morning, built on the same primitive, doing three different jobs. WireGuard is small because it decides almost nothing: it authenticates peers and moves packets, and leaves addressing, routing policy, key distribution, revocation and the kill switch to whoever deploys it. Here is what the cryptokey routing table actually does, where the protocol came from, how a peer gets added one at a time, and what a kill switch does and does not protect."
showFullContent = false
readingTime = true
hideComments = false
+++

*At 04:20 on a Monday, one firewall of mine was running three tunnels and none of them carried a person. One is a road-warrior WireGuard instance with three peers, all offline. One is a commercial WireGuard client, one peer online, quietly moving tens of megabytes. One is a mesh overlay with twenty peers configured and five online, none of them saying much. The same primitive underneath in all three cases, three completely different jobs — and the protocol, in all three, decides far less than people assume it does.*

## three interfaces on one firewall

`wg0`, `wg1`, `wt0`. The first is mine: a tunnel address on a subnet I chose, three peers named after the devices that connect to it. The second is rented: a commercial endpoint, a UDP port on somebody else's server, and one outbound NAT rule telling a slice of my traffic to leave through it. The third is a mesh I did not configure by hand — it exists because a control plane on the internet hands out addresses and keys for me.

WireGuard's reputation is built on one number: less than four thousand lines of code for the original Linux implementation, against two protocols that had grown into frameworks. The number is in the paper, and it is worth understanding, but it is also easy to misread. Small does not mean it does more with less. It means a great deal was deliberately pushed out of the protocol's scope, and something has to hold that work instead: a person, a script, or a product.

So the useful question about WireGuard is not "is it faster than OpenVPN" — it usually is, and that is the least interesting part. The question is: **which decisions did it keep, and which ones did it hand back to me?** Answer that and the deployment stops being a config file and becomes a design.

## what the tunnel actually decides

A WireGuard interface is a network interface. You add it like any other, give it an address, and the operating system routes to it. What is specific to WireGuard sits in one table per interface:

```text
interface wg0
  private key        (32 bytes, never leaves this host)
  listen port        udp 51820

peer <public key A>
  allowed ips        10.1.90.2/32

peer <public key B>
  allowed ips        10.1.90.3/32
  endpoint            203.0.113.7:51820   (optional)
```

Donenfeld calls this the *cryptokey routing table*, and the name is exact. A peer is identified by a public key and nothing else — no username, no certificate subject, no IP. The allowed-IPs list attached to that key does two jobs at once:

- **when sending**, it behaves as a routing table: a packet whose destination falls inside a peer's list is encrypted with that peer's key and sent to that peer's endpoint;
- **when receiving**, it behaves as an access control list: a packet that decrypts correctly under a peer's key is only accepted if its inner source address is one that peer is allowed to use.

The second rule is what makes the design pleasant. Because the same list answers both questions, a packet arriving from peer B claiming to be `10.1.90.2` cannot be accepted: `10.1.90.2` routes to peer A, not B. The mapping is one-to-one by construction, so a firewall rule that matches on "source address, interface" is not a guess about who is speaking — the address has already been proven to belong to that key. That is a stronger statement than most VPNs let you make, and it is why the interface can be firewalled with ordinary rules instead of protocol-specific extensions.

It also has a hard consequence. WireGuard is strictly layer 3. There is no broadcast, no multicast, no ARP on that interface. A magic packet for wake-on-LAN cannot cross it, because the whole point of layer 2 is gone. I found that out the ordinary way a few years ago, wanting to wake a sleeping desktop remotely and ending up with a small HTTP service on the LAN side to send the packet for me. Not a bug in my configuration: the tunnel being honest about what it is.

And the endpoint column is not configuration so much as a cache. On the server side you normally leave it empty: when a correctly authenticated packet arrives from some address and port, WireGuard records that as the peer's current endpoint and replies there. Move from Wi-Fi to mobile data and the tunnel follows, without a reconnect, because the identity is the key and the address is just where the key was last seen. A man in the middle can corrupt that address and cause a denial of service; it cannot read or alter the payload, and a peer that cannot be reached is quickly forgotten.

## where it came from

WireGuard did not begin as a product. Donenfeld has said, in a [2017 FOSDEM interview](https://archive.fosdem.org/2017/interviews/jason-a-donenfeld/), that the requirements grew out of a kernel rootkit he had written — stealth, small code, no unnecessary state — and that in parallel he had been stewing over how absurdly complicated VPN setups were. The design was worked out as a series of puzzles about keeping an interface both simple and secure, and the core idea that survived was exactly the table above: reduce the VPN to the association between a public key and the addresses it may use.

The protocol was published as an academic paper at [NDSS 2017](https://www.wireguard.com/papers/wireguard.pdf), and that paper is unusually readable for the genre: it explains why IPsec's layering is academically correct and operationally painful, why OpenVPN's user-space TLS stack is the right place for a TLS stack, and why it decided to violate both. The claim in it — implementation in "less than 4,000 lines of code, making it easily audited and verified" — dates from a draft revision in 2020, and referred to the Linux module, not to the tooling, the platform clients, or the ports.

Then came the part that is genuinely rare. WireGuard was not funded by a router vendor or a VPN company. Donenfeld has said the project runs on [donations](https://www.wireguard.com/donations/) and that he was living off them, deliberately, to keep the project from being steered by whoever would otherwise pay for it; [a 2021 profile](https://www.businessinsider.com/wireguard-jason-a-donenfeld-profile-secure-vpn-linux-mac-windows-2021-1) records that he had turned down job offers to keep working on it that way. The donations page lists companies and foundations in tiers, and the project's own description of the arrangement is that it is "in no way influenced or directed by any external agendas", which is the sort of sentence you can only write if the money is small and plural.

The kernel merge was not quick either. Patches went to the networking tree in December 2019; Linus Torvalds pulled them in January 2020, and Linux 5.6 shipped the module on 29 March 2020. Torvalds had already made his opinion public on the mailing list in 2018 — "compared to the horrors that are OpenVPN and IPsec, it's a work of art" — a sentence quoted in every article about WireGuard since, including this one. Less quoted is the technical cost: Donenfeld had written his own crypto library for the module, and the kernel's crypto maintainers wanted the existing API used instead. The module landed on the existing API, with pieces of the new code merged separately, which is why "small" was never just an aesthetic choice — it was also a negotiation.

Portability is where the simplicity argument gets tested, and the FreeBSD story is the honest version of that test. Netgate, the company behind pfSense, paid a FreeBSD developer to write a kernel port in 2019; the work was upstreamed in November 2020 and scheduled for FreeBSD 13.0. Days before that release, Donenfeld and two FreeBSD developers reviewed it and found what he described as grave issues. The module was [pulled from 13.0](https://www.theregister.com/software/2021/03/23/freebsd-130-to-ship-without-wireguard-support-as-dev-steps-in-to-fix-grave-issues-with-initial-implementation/1294357), the three of them rebuilt it in about a week — [his announcement](https://lists.zx2c4.com/pipermail/wireguard/2021-March/006494.html) is worth reading for the tone alone, somewhere between relief and exhaustion — and the driver only [reappeared in FreeBSD 13.2, in April 2023](https://www.freebsd.org/releases/13.2R/relnotes/), sponsored by Netgate and the FreeBSD Foundation. The manual page still says it: "The wg device driver first appeared in FreeBSD 13.2."

That matters to me directly, because my firewall is OPNsense, which is FreeBSD, which means the WireGuard running on it is that driver — `if_wg`, not the Linux module the paper describes. Same protocol, same configuration language, different implementation with a shorter and rougher history. On OPNsense the plugin's code has since moved into the core, which is why the firmware's own conflict list now names `os-wireguard` among packages that cannot be installed: there is nothing left to install.

## the handshake, and what "latest handshake" tells you

Under the table there is a key exchange, and it is short enough to describe in one paragraph. WireGuard uses Noise IK: a single round trip in which both sides prove knowledge of their static keys, mixed with ephemeral keys so that the session key is fresh. Curve25519 for the Diffie-Hellman, ChaCha20-Poly1305 for the packets, BLAKE2s for hashing, HKDF to expand, SipHash for hash-table keys. There is no cipher negotiation, no algorithm list, no fallback — the paper calls the protocol "cryptographically opinionated" and accepts the consequence: if a primitive falls, everyone upgrades at once. Given the last decade of TLS downgrade and parser bugs, that trade looks better every year.

Two details are worth carrying around. First, the protocol allocates nothing for packets it cannot authenticate: an unauthenticated handshake initiation gets no state, and under load the responder answers with a small cookie reply that proves the sender's address without committing memory. That is the DoS story, and it is the reason a public listener is less alarming than it sounds.

Second, the timers are the diagnostic interface. A session is replaced after 120 seconds (`Rekey-After-Time`), or after 2^60 messages; the old key is refused after 180 seconds; a handshake that gets no answer is retried after five seconds plus up to 333 ms of jitter; a peer that has sent nothing for ten seconds gets an empty keepalive if it has received something. Which means that on a tunnel actually carrying traffic, the last handshake is always younger than about two minutes — every rekey starts a new one. An idle tunnel is the exception: with no packets to send, nothing triggers a handshake, so a peer can sit for hours with a stale timestamp and still work on the next packet. I read the number the way I read a heartbeat, and it is the single most useful thing `wg show` prints:

```console
$ wg show wg0
interface: wg0
  public key: <redacted>
  listening port: 51820

peer: <redacted>
  endpoint: 203.0.113.7:51820
  allowed ips: 10.1.90.2/32
  latest handshake: 1 minute, 6 seconds ago
  transfer: 31.20 MiB received, 16.21 MiB sent
```

Sixty-six seconds is normal. Four minutes means the peer is gone, or its NAT mapping died, or something in the path started dropping UDP. There is no connection state to inspect beyond this, because there is no connection: the interface is up whether or not anyone is speaking, which is exactly what I saw at four in the morning — listener up, three peers, `latest handshake` empty for all three.

The cryptography has been looked at independently, which is worth knowing given how much folklore surrounds VPN protocols. [Dowling and Paterson's 2018 analysis](https://eprint.iacr.org/2018/080) is the reference: they found that the first data packet effectively serves as key confirmation, so the key exchange is 1.5 round trips rather than 1, and that this detail is what blocks a clean modular proof of key indistinguishability — they had to add a message to the protocol to get the proof through, which is a statement about provability, not a break. If you want the honest summary: no practical attack was found, the design is unusually well specified for something that started as a side project, and the protocol has been stable enough since 2020 that implementations mostly agree with each other.

## what it refuses to do

Here is the list I would put in front of anyone deploying this, because each item is a job that now belongs to you.

**It does not assign addresses.** There is no pool, no lease, no DHCP equivalent. A peer's tunnel address is a decision you make and then write in two places: on the peer's own interface, and in the server's allowed-IPs for that peer. Get those two out of sync and the tunnel comes up, encrypts, and drops every packet — inbound silently, per [OPNsense's own warning](https://docs.opnsense.org/manual/vpnet.html), and outbound visibly in a capture but never actually sent. That asymmetry is the single most common hour lost to WireGuard.

**It does not push anything.** No routes, no DNS servers, no split-tunnel policy. OpenVPN, which [James Yonan released in 2001](https://www.opentech.fund/news/bottlenecked-no-more/), does exactly this: the server hands the client a route list and a resolver and the client obeys. WireGuard's official position is that key distribution and pushed configuration are "out of scope", better left to other layers, "lest we end up with the bloat of IKE or OpenVPN". Which is fine as a principle and immediately becomes a support problem in practice: your phone will happily resolve names through whatever DNS it had before the tunnel came up, and if that resolver is on the local café network, your DNS is outside the tunnel while your packets are inside it.

**It has no users.** Identity is a public key. There is no username, no password, no second factor, no directory. Adding a device means generating a keypair and pasting a public key; removing a device means deleting the peer. That is a clean, auditable model, and it also means "who was that peer" is answered by a comment field you wrote yourself, and "revoke access for the intern" is a manual edit on every instance the peer touched. Anything resembling SSO has to be bolted on top — which is precisely what the mesh products do.

**It has no fallback transport.** UDP only, one port. On a network that blocks UDP or shapes it by fingerprint, the tunnel does not come up, and there is no TLS-on-443 mode to hide behind. OpenVPN's willingness to run over TCP/443 is inelegant and it is why it still works in hotels.

**It does no NAT traversal signalling.** Roaming handles the address changing; it does not handle two peers that are both behind NAT and neither of which has a reachable endpoint. Something has to be reachable, or something has to coordinate. Again: the gap that a control plane fills.

**It has no multicast, no broadcast, no layer 2.** No wake-on-LAN, no mDNS discovery, no "just browse the network". If you need those, you need a bridge somewhere else, or a different tool.

None of this is a criticism of the protocol; it is the bill for the four thousand lines. But it reframes the comparison people usually make. OpenVPN gives you a heavier protocol with a control channel that pushes configuration and authenticates users. A mesh product like Tailscale or NetBird keeps WireGuard as the data path and adds exactly the missing pieces above it: a control plane that distributes keys, a coordination service that finds paths through NAT, SSO in front of the key, and an admin UI where "remove the laptop" is one click. When someone says a mesh is "WireGuard with a brain", that is what they mean — and the brain is a server you do not run.

## three tunnels on my firewall

Which brings me back to 04:20. The state was this, from the firewall's own status output, with keys and addresses masked:

- `wg0`, my road-warrior instance: interface address `10.1.90.1/24`, MTU 1420, listener up, three peers — phone, laptop, desktop — each with a `/32` and its own name, all three offline with an empty handshake.
- `wg1`, a commercial endpoint: MTU 1320, one peer, online, handshake 66 seconds old, keepalive every 15 seconds, tens of megabytes exchanged.
- `wt0`, the mesh: MTU 1280, twenty peers configured, five of them online with handshakes between 60 and 113 seconds old.

Three MTUs, three reasons. 1420 is 1500 minus 80 bytes of encapsulation — 20 to 40 for the outer IP header, 8 for UDP, 32 for WireGuard's own header and authentication tag — and it is also the margin the Windows client computes by subtracting 80 from whatever interface carries the default route, because the tunnel is a packet inside a packet and the outer one still has to fit the path MTU. 1320 is what the commercial provider chose for its own reasons, likely because its own tunnel already reduces the path underneath. 1280 is the IPv6 minimum, the value a mesh picks when it would rather be safe than fast. None of these is a WireGuard setting. All three are somebody's decision about the network underneath.

The honest part of that snapshot is the road-warrior instance. It is configured, it listens, and the firewall has **no destination-NAT rule for its port** — I checked the NAT table rather than trusting my memory of setting it up. So the reachability of that peer path does not come from the firewall today; if it works from outside at all, it is because of a forward on the router in front of it, and I can only half-verify that from inside my own network. The tunnel that actually carries my remote access right now is the mesh, which needs no inbound port at all because its peers find each other through a coordination server.

I am keeping that in the article because it is the point. A listening WireGuard interface is not a reachable service. "Expose one UDP port" is a separate sentence, in a separate place, with its own failure mode — and on a firewall behind another NAT, it is two sentences, and one of them is written on a box you might not control.

## adding one peer

What follows is the version I would do again, on OPNsense 26.1, with addresses from the documentation range replaced by my own tunnel subnet. It is not a click-by-click tour; it is the decision order and the verification, because those are the parts that survive a version upgrade.

**1. Decide the address before the key.** Pick a tunnel subnet that does not collide with anything a client might already be on. `10.1.90.0/24` is mine, deliberately outside the RFC1918 ranges most home routers hand out, because the classic WireGuard failure is not cryptographic: it is a phone that joins a café network using `192.168.1.0/24` and now has the same prefix on both sides of the tunnel. Every peer gets one `/32`. Write it down; the firewall will not do it for you, though the peer generator will propose the next free one.

**2. Generate the keypair where the key will live.** On the client, not on the firewall:

```console
$ umask 077
$ wg genkey > wg0.key
$ wg pubkey < wg0.key > wg0.pub
```

The private key never needs to leave the device. OPNsense's peer generator can store it on the firewall to let you re-download a client configuration later — it says so plainly, and the storage is off by default. Leave it off unless you actually need that convenience, because a private key on a firewall is a second copy of the thing that authenticates the device, sitting on the box that terminates all the tunnels.

**3. Create the instance.** VPN → WireGuard → Instances. A keypair is generated on the firewall, a listening port is chosen, and the tunnel address goes on the `wgX` device: `10.1.90.1/24`. Leave "disable routes" off if you want the firewall to create routes for the networks listed in the peers' allowed IPs.

**4. Add the peer, with both halves of allowed-ips.** This is the step where the two roles of the list have to be spelled out. For a phone that should reach my production VLAN and nothing else:

```text
AllowedIPs = 10.1.90.2/32, 10.1.20.0/24
```

The `/32` is the address the peer will use inside the tunnel; the `/24` is what I am willing to route to it — and, in the other direction, what it is allowed to send from. An endpoint is left empty for a road warrior: the firewall learns it from the first authenticated packet. Keepalive stays off unless the peer must be reachable while it has nothing to say, which is the case for a device behind NAT that has to receive inbound connections; 25 seconds is the value the [quick start](https://www.wireguard.com/quickstart/) suggests for that.

**5. Write the firewall rule, because there isn't one.** The tunnel interface is a new interface, and the default policy on a new interface is not "friendly". One pass rule on the WireGuard interface, source `10.1.90.0/24`, destination the networks that peer should reach, and nothing else. This is also the closest thing to a server-side kill switch: the allowed-ips list says who may speak, the firewall rule says what they may reach, and both are explicit.

**6. Bring the client up and read the handshake.** A client config is short:

```ini
[Interface]
PrivateKey = <client private key>
Address = 10.1.90.2/32
DNS = 10.1.50.53

[Peer]
PublicKey = <firewall public key>
Endpoint = vpn.example.net:51820
AllowedIPs = 10.1.20.0/24, 10.1.50.0/24
PersistentKeepalive = 25
```

`wg-quick up wg0` on Linux, the official app elsewhere. Then, on both ends, look at the handshake age rather than at "connected": the client should show a handshake younger than two minutes, the firewall's status page should show the same peer with bytes moving. If the handshake is there and pings fail, the problem is allowed-ips or the firewall rule — and if packets are large and TLS handshakes hang while `ping` works, it is MTU, every time.

**7. Test the failure before you need it.** Pull the peer's allowed-ips down to a wrong `/32` and watch what happens: the interface stays up, the handshake keeps happening, and traffic disappears. That is what a misconfigured peer looks like from the inside, and knowing it in advance is worth more than any troubleshooting checklist.

## kill switch thinking

The phrase "kill switch" gets used as if WireGuard had one. It does not, and that is consistent with everything above: blocking traffic that is not in the tunnel is a firewall policy, and WireGuard is not a firewall.

What each platform actually gives you is worth knowing precisely, because the differences are large.

On **Android**, it is a system feature, not an app feature: always-on VPN, available since Android 7.0, plus a "Block connections without VPN" switch — lockdown — that makes the system refuse any traffic that does not use the tunnel. The [developer documentation](https://developer.android.com/develop/connectivity/vpn/) is explicit that this is user- or admin-controlled and that apps cannot enable it for themselves. It is the strongest kill switch of the mainstream platforms, and it is also the bluntest: with lockdown on and the tunnel down, the phone has no network at all.

On **Windows**, the official client does have a kill switch, but only under conditions: one peer, and an allowed-IPs list containing a `/0`. In that case it installs firewall rules that permit the tunnel transport, DNS to the configured servers only, loopback, DHCP and IPv6 neighbour discovery, and block the rest — [the client's own networking notes](https://git.zx2c4.com/wireguard-windows/tree/docs/netquirk.md) describe it precisely, including why DNS is special-cased: Windows would otherwise resolve through every configured server, including the ones outside the tunnel. The same notes give the escape hatch, which is the detail I find most instructive: use `0.0.0.0/1` and `128.0.0.0/1` instead of `0.0.0.0/0` and `::/0`. Two routes that together cover the entire address space, still sending everything through the tunnel, but without triggering the blocking rules. The client's editor toggles exactly that when you untick the checkbox.

I like that trick because it makes the mechanism visible. A default route is a routing decision; a kill switch is a firewall decision. `0.0.0.0/0` happens to be the pattern both layers key on, so splitting it in half keeps one and drops the other. If you have ever wondered why some configurations insist on `/1` routes, that is why.

On **iOS and macOS**, as far as the official client's options go, you get on-demand rules that bring the tunnel back up — reconnect logic. That is not the same guarantee as blocking untunneled traffic, and treating "it reconnects" as "it never leaks" is the mistake to avoid. On **Linux**, `wg-quick` sets up an interface and routes and stops there; the blocking rules are yours to write, in `PostUp` hooks or in a proper nftables table.

Then there is the question the phrase usually hides: a kill switch protects **the client's traffic**, not the lab. It stops your laptop from quietly using the hotel's network when the tunnel drops. It does nothing about the fact that your firewall is listening on a UDP port, that a lost phone still holds a valid key, or that a peer you deleted six months ago is still sitting in a `wg1.conf` on a machine you forgot about. Those are server-side questions, and their answers are: one port, one rule set, one key per device, and a list you actually prune.

And there is a cost that rarely gets written down. Lockdown on a phone means that when my lab is down, the phone is offline — not degraded, offline. For a device that is mostly a client of the lab, that is the right trade. For a device that needs the internet more than it needs the lab, it is a self-inflicted outage with a very good security story. That is a decision about what the tunnel is for, and no protocol can make it for you.

## the question the protocol will not ask

WireGuard's selling point is that it does one thing completely: it authenticates two parties by key and moves packets between them with modern cryptography, without negotiation, without state you have to manage, and without a configuration language that outgrew its purpose.

The bill for those four thousand lines is that everything else has to exist somewhere — the address of each peer, the networks each may reach, who holds which private key, what happens to a lost phone, whether the client blocks traffic when the tunnel drops, whether a port is exposed at all. That "somewhere" is either a person with a wiki line, a script, or a product with a control plane and a monthly invoice. Three options, and a deployment that has not chosen one of them is a deployment waiting for its first surprise.

So the three tunnels on that firewall at four in the morning are three answers to one question: what is this tunnel for? WireGuard will not ask it, and it will keep authenticating whoever holds a key long after the device holding it was sold. Which is why the part of my setup I trust most is not the interface that is up. It is the address written down before the peer existed, the single rule on the tunnel interface instead of the generous one, and the handshake age I read before believing a green icon.
