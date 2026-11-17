+++
title = "an address is a decision, a lease is an outcome"
date = "2026-11-17T06:57:53Z"
author = "cleeryy"
authorTwitter = ""
cover = ""
tags = ["homelab", "networking", "dhcp", "dnsmasq", "kea", "opnsense", "ipam", "self-hosting"]
keywords = ["dhcp", "dhcp lease", "static lease", "dhcp reservation", "dora", "dhcp discover offer request ack", "dnsmasq dhcp", "kea dhcp", "isc dhcp end of life", "opnsense dhcp", "dhcp range", "dhcp pool", "lease time t1 t2", "dhcp authoritative", "mac address randomization", "private wi-fi address", "ip address management", "homelab networking", "bootstrap protocol"]
description = "Two documents in my own homelab wiki put the same VM on two different VLANs; the hypervisor settles it in one line, because the address was never written anywhere I control. What DHCP actually decides, how ISC DHCP died and dnsmasq inherited its job in my firewall, and why the pool boundary is the only part of the design that must be written before the first device boots."
showFullContent = false
readingTime = true
hideComments = false
+++

*One virtual machine of mine appears on two different VLANs in two documents of my own homelab wiki. The machine is not confused: it holds one tag, takes one address from one pool, and has never disagreed with either. The paperwork disagreed — because the address was never something I decided, it was something that happened.*

## the vm that lives on two vlans in my notes

Two inventory lines, both mine, written at different times:

```text
| mint (VLAN 10 ADMIN, DHCP, IP à vérifier) | VM 10001 | pve3 | 10.1.10.x | — |
```

```text
VLAN 60 HOME : .1 OPNsense, .60 nettest (CT660…), .179 mint (VM10001, DHCP, tag 60)
```

The hypervisor settles it in a single line. From the VM's config, MAC masked:

```text
net0: virtio=BC:24:11:XX:XX:XX,bridge=vmbr1,tag=60
```

Tag 60 is HOME, and `10.1.60.179` sits inside HOME's pool. So the second line is right and the first is wrong — but wrong in an interesting way. The VM carries a Proxmox tag `admin`. Somewhere between reading that label and typing a table row, a word became a VLAN number.

I keep this example because nothing broke. The VM is stopped right now, `onboot 0`, and it spent however long in a table attributed to the wrong network. No alarm could have fired, because **no file I control contained its address**. Not the VM config, which says "tag 60" and leaves the rest to the pool. Not the firewall, whose lease table is a runtime artifact. Only a document, written by hand, after the fact.

Compare that with the machines that never surprise me. Every container and VM I care about has its address in its own configuration: `10.1.20.41/24` in a container's network file, an `ip=` argument in a Proxmox container config, a cloud-init snippet. Those addresses cannot drift, because writing one down *is* how they get one. They cost me a decision per machine, and they buy the property I want: the address exists in a file before the machine exists.

DHCP is the other arrangement, and it is the only part of my lab where a machine chooses its own identity. So the useful question is not which DHCP server to run. It is: **which addresses am I willing to let a machine choose?** (IPv6 splits the same problem differently — router advertisements and SLAAC let the host build its own address from a prefix, which is arguably an even stronger form of the same trade — but everything below is DHCPv4.)

## four messages and a timer

The protocol is small enough to hold in your head, which is why it outlived almost everything else in the stack.

It begins with BOOTP, [RFC 951](https://www.rfc-editor.org/rfc/rfc951), written in September 1985 by Bill Croft and John Gilmore so that diskless workstations could find a server and a boot image. BOOTP had a table: MAC address on one side, address on the other, maintained by a human. [RFC 2131](https://www.rfc-editor.org/rfc/rfc2131) — Ralph Droms, Bucknell University, March 1997 — kept BOOTP's packet format and added the one thing that turns a table into a service: *automatic allocation of reusable network addresses*. That is the whole innovation. Not a better way to store the table, a way to not have one.

The exchange, DORA, is four messages:

```text
client 0.0.0.0:68  ->  255.255.255.255:67   DHCPDISCOVER   (who is out there?)
server             ->  client               DHCPOFFER      (you could have this)
client             ->  server               DHCPREQUEST    (I'll take that one)
server             ->  client               DHCPACK        (yours until <time>)
```

The first one has to be a broadcast, and that is not laziness: the client has no address, so nothing could address a reply to it. Broadcast means every host on the segment sees the question, and the first offer that arrives tends to get the client's attention. Nothing in those four messages authenticates the server. No key, no signature, no notion of "this is my network's DHCP". A device that plugs into a port and receives an offer cannot tell whether it came from the firewall or from a router someone reset to factory defaults and left on the wrong side of a bridge. "The DHCP server" is a convention, enforced — when it is enforced at all — by switch port configuration and by not putting a second one there.

What is leased deserves a precise name, because it explains most of the surprises. The server does not hand over an address the way a registrar hands over a domain. It grants a claim on it, for a duration, recorded in a lease file. The client renews at T1, halfway through, and rebinds at T2, seven eighths of the way — both fractions come from [the RFC](https://www.rfc-editor.org/rfc/rfc2131), not from the server's imagination. If renewal fails and the lease expires, the client does not politely keep the address: it falls back to a link-local address in 169.254/16 per [RFC 3927](https://www.rfc-editor.org/rfc/rfc3927) and starts asking again. RFC 3927 even records the client behaviour of its era — Mac OS sent nine DHCPDISCOVERs two seconds apart and autoconfigured after eighteen seconds. Modern clients differ in timing, not in shape, and the shape gives you a diagnostic signature better than any guess: a client holding a 169.254 address is not "off the network", it is a client whose DHCP conversation went unanswered.

The RFC also asks servers to check that an address is free before offering it, "e.g., the server may probe the offered address with an ICMP Echo Request", and asks that administrators be able to disable the probe. Hold on to that detail: it is why a static address sitting inside a dynamic pool is a slower accident rather than an immediate one.

## three implementations, three cultures

DHCP's reference implementation was ISC DHCP, written by Ted Lemon at Vixie Enterprises for the Internet Software Consortium. ISC's [own history](https://www.isc.org/dhcphistory/) puts 1.0 in June 1998, 2.0 a year later, 3.0 in 2001 and 4.0 in 2007. For two decades it was what you installed when you said "a DHCP server", and it accumulated a configuration language, OMAPI for runtime control, failover pairs and a great deal of operational folklore.

Then it stopped. [The last maintenance releases, 4.4.3-P1 and 4.1-ESV-R16-P2, were published on 5 October 2022](https://www.isc.org/blogs/isc-dhcp-eol/), with end of life at the end of that year; the client and the relay had already gone in January 2022. ISC's replacement, Kea, was not a rewrite written after the funeral — it grew out of BIND 10's DHCP components, started in 2011, survived BIND 10's cancellation in April 2014 as a standalone project, and reached [1.0 in December 2015](https://ftp.ripe.net/mirrors/sites/ftp.isc.org/isc/kea/1.6.3/doc/html/man/kea-dhcp-ddns.8.html). It was written by Tomek Mrugalski and Marcin Siodelski and designed for what ISC DHCP did badly: reconfiguration without restarts, host reservations in a real database, high availability, and the request rates of a datacentre or a public Wi-Fi.

The third implementation took the opposite road. dnsmasq is Simon Kelley's, [copyright dated 2000](https://thekelleys.org.uk/dnsmasq/doc.html), and it was not a DHCP server at first. It was a small DNS forwarder for home networks, and it handled DHCP by *reading ISC dhcpd's lease file* so that leased machines would appear in its DNS. Its changelog records what happened next, in the 2.0 release candidates of January 2004: "BIG CHANGE: added an integrated DHCP server and removed the code to read ISC dhcp.leases." A DNS cache that used to parse someone else's state grew its own, because reading a file is not the same as owning it.

That culture shows in the defaults: one process for DNS, DHCP and TFTP; a configuration file measured in dozens of lines rather than a grammar; a default IPv4 lease of one hour; and a hard ceiling of 1000 leases so a hostile client cannot eat the process's memory. OPNsense's manual calls it "the perfect DNS & DHCP server for small and medium sized setups (less than 1000 unique clients)". There is no failover pair, and no runtime control channel comparable to OMAPI or Kea's. It is a single process doing several jobs, and it does them without asking for much.

Which is why the route ISC's end of life took through my firewall is worth a paragraph. Kea was there first, and it was the obvious successor. But OPNsense's [25.1.2 announcement, in February 2025](https://docs.opnsense.org/releases/CE_25.1.html), put it plainly — "since Kea remains a bit of an odd choice we will be offering DHCP support via Dnsmasq as a new standard feature which also offers seamless DHCP lease registration some people keep looking for" — and 25.1.6 followed in May with "full DHCP and router advertisement support in Dnsmasq" alongside Kea DHCPv6. 25.7 made dnsmasq the default for new installations, and [26.1, in January 2026](https://github.com/opnsense/changelog/blob/master/community/26.1/26.1), moved ISC DHCP out of core into the `os-isc-dhcp` plugin and made dnsmasq the default for DHCPv4, DHCPv6 and router advertisements. The forwarder that was already running on the box won the job by being there. My firewall runs 26.1.11, its dnsmasq service is up on port 53053, and its Kea control agent is stopped — not a configuration I chose, a default I accepted.

## what my pools actually say

Here is the entire DHCP configuration of my lab, in dnsmasq's vocabulary. OPNsense writes the file; these are the values it writes.

```text
dhcp-range=10.1.10.100,10.1.10.199,255.255.255.0   # ADMIN
dhcp-range=10.1.60.10,10.1.60.199,255.255.255.0    # HOME
dhcp-range=10.1.40.10,10.1.40.199,255.255.255.0    # GUEST
dhcp-option=option:router,10.1.10.1                # one router option per VLAN
dhcp-option=option:router,10.1.60.1
dhcp-option=option:router,10.1.40.1
dhcp-option=option:dns-server,10.1.50.53           # one address, not a list
# and no dhcp-host lines at all
```

Four decisions live in those lines, and each is one I would have to make again from scratch.

The ADMIN pool starts at `.100`. Below it, `.1` to `.99`, is where infrastructure lives, and every address there follows the convention I wrote about in [naming things](/posts/naming-things/): first digit the VLAN, the rest the host, so `10.1.10.24` is a machine documented as `10.24`. The pool boundary is that convention made operational — a dynamic client cannot take a number belonging to the static band, because the server never offers one. HOME starts at `.10`, because nothing on HOME is infrastructure: phones, laptops, a test VM. GUEST starts at `.10` for the same reason with more conviction.

PRODUCTION, PREPRODUCTION and MANAGEMENT have no range at all. Not a small range: none. Every machine there is configured statically, which is why the addresses referenced from reverse-proxy upstreams, backup jobs and firewall aliases never come from a pool. The separation is the design; the ranges are its syntax.

And IOT is a half-finished sentence. The interface is in dnsmasq's list, so the service will answer there, but no range was ever defined and no reservation exists, which means it currently serves nothing. I noticed that while writing this, reading my own configuration as a document rather than as a settings page. It is exactly the kind of gap a lab accumulates: the intent was recorded on one screen and the consequence was never checked on another.

The zero `dhcp-host` lines are the part that will look wrong to anyone who has read the usual advice, which is to give infrastructure static *leases*. I don't. Infrastructure here takes its address from its own configuration, for two reasons I can defend and one cost I have to accept. The reason: a reservation is a promise that depends on the promiser. If the firewall VM is down, or restored from a backup whose lease database is older than reality, a device waiting for a reserved address has nothing, while a device with a static address still answers on the wire — and the machines that matter here are the ones I would use to repair the firewall. The cost: my map lives in one config per guest instead of one table, and a typo in one of them can land inside a pool. dnsmasq's ICMP probe protects the pool's side of that collision. Nothing protects the other side.

Two more values are worth stating, because they are visible in the configuration and easy to leave unexamined.

`authoritative` is off, which means dnsmasq keeps strict RFC behaviour: a client asking for an address the server does not know about gets silence, not a NAK. The manual reserves that flag for a server that "is definitely the only DHCP server on a network", and says turning it on stops unknown-lease requests from being ignored and lets the server rebuild its lease database without every client reacquiring. Off is the right default where a second server might appear; it is also why a lost lease file produces a slow, quiet recovery instead of a fast correction.

And the DNS option carries exactly one address: `10.1.50.53`. One resolver for every client on three VLANs. If that container is down, every device keeps its address and loses its names, which looks like a network outage and is not one. I write that down as a weakness rather than a design, because a second value in that option would cost nothing.

## reachable and nameless

The inventory problem fits in three commands. On the production VLAN, one address answered me:

```console
$ nc -z -w2 10.1.20.63 22; echo $?
0
$ nc -z -w2 10.1.20.63 80; echo $?
1
$ nc -z -w2 10.1.20.63 443; echo $?
1
```

Exit 0 means the TCP handshake completed. Exit 1 means the connection was refused — the host answered and nothing is listening on that port. A hang would have meant silence, which is a third finding, not the same one. So there is a machine at `10.1.20.63` with SSH open.

Now ask DNS about it:

```console
$ dig +noall +comments -x 10.1.20.63 @10.1.50.53
;; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, id: 82
;; flags: qr aa rd ra; QUERY: 1, ANSWER: 0, AUTHORITY: 1, ADDITIONAL: 1
```

`NXDOMAIN` with `aa` set: authoritative no-such-name. My DNS does not merely fail to know this address, it asserts that it does not exist. And the names I did document resolve fine — `pbs.internal.cleeryy.cloud` returns `10.1.50.78`, `technitium` returns `10.1.50.53` — while one I never added, my own container's, returns nothing at all.

That is the problem in one screen: the network has a machine, DNS denies it, and the only bridge between them is a document written by hand. DNS cannot fill the gap by itself because of a setting: dnsmasq knows how to publish lease names into DNS, and my `regdhcp` is off. The zone is static, maintained by me, and therefore exactly as good as my last edit — which is a little ironic, given that "seamless DHCP lease registration" was part of OPNsense's argument for putting dnsmasq in charge.

There is a trap in that transcript too, and it costs people afternoons. Before those `nc` calls I tried `ping`, from an unprivileged container:

```console
$ ping -c1 10.1.20.63
ping: socket: Operation not permitted
```

That is not a blocked host. That is a missing `CAP_NET_RAW` on the machine doing the probing, and it reads exactly like a firewall drop to anyone who does not already know the difference. A probe whose failure modes are distinguishable is worth more than a probe that is familiar.

So how do you audit a lab without buying a product? Two sweeps, in opposite directions, both cheap.

From the documented side: for each address in the table, ask something that must answer. `nc -z` on a known port gives open, refused, or silence, and those are three different facts. For an address that should be free, `arping -D` performs duplicate-address detection properly — it asks the question a host asks itself before claiming an address — and it is the most direct way to learn that a number is unclaimed.

From the wire side: read the leases. dnsmasq's lease file is line-oriented text, one lease per line (`<expiry> <mac> <ip> <hostname> <client-id>`), so a machine without a line is either static, or new, or lying. Diff that list against the table and you get two sets: addresses documented and silent, addresses alive and undocumented. The second set is the one that matters.

And before changing any of it, validate before reloading. `dnsmasq --test` parses the configuration and exits non-zero if it does not understand it; a reload that quietly falls back to defaults is how a pool ends up in the wrong subnet.

## reservation or static

Three ways to get an address, and they are not interchangeable.

Static means a file you control states the address. It survives everything except a collision, it is invisible to any central view, and it needs a device you can configure.

A reservation means you decide the address and DHCP delivers it. One table, one place to look, and — if you let it — the same table feeds DNS. It depends on the server being up when the client boots, and on the client presenting the identity you reserved.

A pool means the server decides. Zero work, zero paperwork, and every reference to that address from elsewhere is a latent failure with a timer on it.

The test I actually use fits in one sentence: **if another file contains this address, it cannot be an outcome.** A reverse-proxy upstream, a firewall alias, a backup job's target, a monitoring check, a line in a wiki someone will read at 2 a.m. — each is a reference that breaks silently when the lease moves. Everything referenced is static or reserved, without exception. Everything else can be a pool.

The reservation's weak point is identity. It is keyed on a MAC address, and MAC addresses stopped being stable the moment they became a privacy feature. Apple's private Wi-Fi address has been on by default since iOS 14, and [since iOS 18 there are three modes](https://support.apple.com/guide/security/wi-fi-privacy-with-apple-devices-sec31e483abf/web): off, fixed, and rotating. Fixed is the default on WPA2 and stronger; rotating changes the address every two weeks on weak or open networks. On a modern phone, a reservation is a reservation on a decision the phone can revoke, and a rotating address is a reservation that quietly stops applying. That is not a reason to avoid reservations. It is a reason to reserve for the things that hold still — the printer, the access point, the box with a web interface and no keyboard — and to expect nothing from a phone.

On a wired lab the question is simpler, because you control both ends. That is the honest reason my infrastructure is static and my wireless clients are pooled: not a principle about DHCP, a fact about who can be configured.

## what i would write down first

The order of decisions matters, and it is not the order the settings page presents.

First the boundary: which band of each subnet is decided, which is dispensed. Half a subnet of static addresses and half a pool is a fine ratio; a pool overlapping the static band is not a ratio, it is a countdown. Then the convention that makes a documented line redundant — if the hostname encodes the address, the table and the machine cannot disagree for long. Then the short list of everything referenced from somewhere else, each of which has to be a decision. Only then a DHCP server, and only for the addresses that were left.

Do that and the inventory stays small enough to be true, because leases never enter it. A lease is a fact about this moment, and a document that records facts about moments is wrong by the time it is published.

The line about `mint` is still wrong in one of my two tables. The fix is not a better table. The fix is that the VM is dormant, that its tag says HOME, and that if it ever comes back it will get a reserved address outside the pool — one a file I control states, so that the next person to read the inventory, including me in six months, is not reading a memory of a lease.
