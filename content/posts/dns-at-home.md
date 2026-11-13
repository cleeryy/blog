+++
title = "dns is three jobs behind one port"
date = "2026-11-13T06:52:00Z"
author = "cleeryy"
authorTwitter = ""
cover = ""
tags = ["homelab", "dns", "technitium", "pihole", "unbound", "network", "self-hosting"]
keywords = ["dns at home", "technitium dns server", "pi-hole vs technitium", "unbound recursive resolver", "local dns zone", "conditional forwarding", "dns search domain", "ad bit dnssec", "extended dns errors", "zone transfer axfr", "split horizon dns", "dns cache ttl", "self-hosted dns", "dns sinkhole"]
description = "One name resolved and its neighbour did not, on the same box, one label apart. What a homelab DNS setup actually decides: recursion, authority and policy, the history of the three tools that cover them, and the two answers in my own chain that came from a hop I do not administer."
showFullContent = false
readingTime = true
hideComments = false
+++

*`getent hosts technitium` answered. `dig technitium.internal` returned NXDOMAIN. Same machine, same resolver, one label apart — and neither answer was about the server being up. Most DNS confusion at home lives in that gap, because port 53 is doing three different jobs and we usually pay for one.*

## the name that worked for the wrong reason

I asked for two names, seconds apart, from the same container on the production network.

```console
$ getent hosts technitium
10.1.50.53      technitium.internal.cleeryy.cloud

$ dig +noall +comments technitium.internal @10.1.20.1 | head -4
;; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, id: 43487
;; flags: qr rd ra; QUERY: 1, ANSWER: 0, AUTHORITY: 0, ADDITIONAL: 1
```

The first one is the interesting one, because of what it returns: not `technitium`, but `technitium.internal.cleeryy.cloud`. The library call appended my search domain before it ever spoke to a server. `/etc/resolv.conf` says `search internal.cleeryy.cloud`, so the name that resolved is not the name I typed — the client built a third name and asked for that.

Which is why the second query is not a contradiction. `technitium.internal` does not exist anywhere in my infrastructure: not in the Technitium zone, not in the firewall's dnsmasq, not in Unbound. The answer came back NXDOMAIN with no `aa` flag, meaning *nothing authoritative said no* — a resolver asked around and found nobody who owned the question.

So "the short name works" was never a property of my DNS server. It was a property of my laptop's resolver configuration. That is the first lesson and it is not a small one: the thing you are debugging is a path, and the path starts on the client.

## three jobs behind port 53

Once you separate what you are asking for, the tool debate mostly dissolves, because there are three distinct jobs and almost every argument about "the best DNS server" is two people describing different ones.

**Resolve the internet.** A resolver either walks the tree itself — root, TLD, authoritative, one query per level, caching along the way — or forwards to someone who does. The first is recursion, the second is forwarding, and the difference is whose IP address appears in somebody else's logs.

**Answer for your own names.** Authoritative service means answering from a zone you hold, with a `SOA`, `NS` records, per-record TTLs and the `aa` flag set. This is the job that makes `pbs.internal.cleeryy.cloud` mean something, and it is the one most home setups accidentally skip by putting entries in a hosts file.

**Decide what gets refused.** Blocklists, regex rules, rewrites, a sinkhole answer of `0.0.0.0`. This is policy, and it is what most people install first — which is why the tool they chose often cannot do the other two.

A single box can do all three, and none of the three popular ones does them in the same proportions. Worth knowing where each came from before trusting any of them with the front door.

## where these tools come from

**Unbound** is the oldest idea of the three and the least interested in being a product. Its design was laid down in January 2004 by Jakob Schlyter of Kirei and Roy Arends of Nominet, on a Java prototype funded by VeriSign; [NLnet Labs took over in 2006 and wrote the C implementation](https://www.nlnetlabs.nl/history/), released in May 2008. NLnet Labs had been writing DNS software for root servers since 2001 — NSD exists because RIPE NCC asked for an implementation that shared no code with BIND, which then ran all thirteen root servers. That lineage explains Unbound's personality: a validating, recursive, caching resolver under a BSD licence, configured by file, with no web interface and no interest in having one. It validates DNSSEC as a core purpose, not as a feature. The current release is [1.26.2, from 21 October 2026](https://www.nlnetlabs.nl/projects/unbound/download/) — still lean, still a text file, still the thing you measure instead of look at.

**Pi-hole** is a decade younger and started as a joke with a Raspberry Pi in it. [Jacob Salmela wrote it in 2014](https://en.wikipedia.org/wiki/Pi-hole) as an open-source answer to AdTrap, a small hardware box that filtered ads at the network level; the trademark was registered in 2017. Architecturally it has always been dnsmasq wearing a dashboard, and since v4.0 in 2018 the dnsmasq in question is a fork called FTLDNS. The v6 release of [February 2025](https://pi-hole.net/blog/2025/02/18/introducing-pi-hole-v6/) removed the last PHP and lighttpd dependencies and moved the web server and a REST API inside the `pihole-FTL` binary, with the configuration collapsed into one commented `pihole.toml`. It is a sinkhole that forwards: it does policy extremely well, it caches, and it does not claim authority. Its own documentation describes locally defined records as an [ordered list with four possible sources](https://docs.pi-hole.net/main/faq/) — host name, dnsmasq config, `/etc/hosts`, then `custom.list` — which is a fair summary of what it is: a very good place to write down a name, not a zone. As of October 2026 it is at FTL 6.8 / Core 6.5, mostly security advisories.

**Technitium DNS Server** is the newcomer that behaves like an old piece of infrastructure. Shreyas Zare [released it on 17 November 2017](https://blog.technitium.com/2017/11/technitium-dns-server-released.html) from Mumbai, as an alpha, with a sentence that has aged into a compliment: *"this DNS server is not suitable to be used for production or any critical application"*. It is GPLv3, written in C# on .NET — now .NET 10 — cross-platform, with a web console, and its scope was never the ad-blocking market: it is authoritative *and* recursive in one process, with primary, secondary, stub and conditional-forwarder zones, AXFR/IXFR, zone transfer over TLS ([RFC 9103](https://www.rfc-editor.org/rfc/rfc9103)) and over QUIC ([RFC 9250](https://www.rfc-editor.org/rfc/rfc9250)), ZONEMD validation for secondaries ([RFC 8976](https://www.rfc-editor.org/rfc/rfc8976)), DNSSEC validation including EdDSA, and DoH/DoT/DoQ both ways. Blocking arrives as [an app you install](https://github.com/TechnitiumSoftware/DnsServer), not as the headline. Clustering landed in v14 (November 2025) and SSO/OIDC in [v15, April 2026](https://blog.technitium.com/2026/04/technitium-dns-server-v15-released.html). The repository sits around 10.3k stars, run by one extremely active maintainer.

The honest weaknesses are the mirror image. A [practitioner writeup of a Pi-hole migration](https://senn-tech.com/en/blog/technitium-dns) puts it plainly: enormous community on Pi-hole's side, "small but very active" on Technitium's, single maintainer, more knobs because it really is a DNS server — forwarders versus recursion, what syncs in a cluster and what does not, certificates, DNSSEC. Independent comparisons say the same thing from the other direction: Pi-hole and AdGuard are blockers that speak DNS, [Technitium is a DNS server that can block](https://selfhosting.sh/best/dns-networking/). Neither framing is a verdict; they are two different jobs.

## what a zone has that a list doesn't

A list of `address name` pairs and a zone both answer `A` queries, so the difference looks cosmetic until you ask the zone something else. Then it answers.

```console
$ dig +noall +answer internal.cleeryy.cloud SOA @10.1.50.53
internal.cleeryy.cloud. 900 IN SOA technitium. hostadmin.internal.cleeryy.cloud. 4776 900 300 604800 900

$ dig +noall +answer internal.cleeryy.cloud NS @10.1.50.53
internal.cleeryy.cloud. 14400 IN NS technitium.

$ dig +noall +comments technitium.internal.cleeryy.cloud @10.1.50.53 | head -4
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 26516
;; flags: qr aa rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1
```

Three things there that a `custom.list` cannot give you. A serial (4776, so I know a change happened and when it was applied), a per-record TTL of 300 separate from the SOA's own 900 and the NS's 14400, and the `aa` bit — this box owns the answer instead of passing along somebody else's. Ask for a name that does not exist inside the zone and the NXDOMAIN is authoritative too, which is a real answer with a negative TTL attached, not a shrug that makes the next client ask again in two seconds.

Then there is the part that makes me smile every time I read my own zone: that `NS` record points at `technitium.`, and `dig technitium. A` returns NXDOMAIN. I typed a name without a trailing dot into a zone editor that treated it as absolute, and nothing ever complained, because nothing ever needed that record to resolve. Which is the actual lesson about zones in a homelab: **a zone you never delegate is a database with DNS syntax**. It buys you structure, per-record TTLs and authoritative negatives, and it does not buy you high availability, because a second server would have to transfer a copy and mine refuses:

```console
$ dig AXFR internal.cleeryy.cloud @10.1.50.53
; Transfer failed.
```

Refusing AXFR is the correct default for a resolver reachable from five VLANs — an open zone transfer is a free map of your network — but it also means the "just run two of them" instinct is not a checkbox. You mirror a zone by configuring a secondary that is *allowed* to ask, and then you have two boxes that can disagree.

## the chain, stage by stage

My lab resolves names in three hops, and each hop was written on a different day for a different reason.

1. Every VLAN gateway runs OPNsense's Unbound on port 53, so clients get a resolver from DHCP and never talk to anything else.
2. Unbound holds a domain override for `internal.cleeryy.cloud` pointing at Technitium, `10.1.50.53`.
3. Technitium hosts the zone, and for everything outside it forwards to a public resolver over plaintext port 53.

That is a textbook split-horizon setup, and it also means a failing name has three plausible owners. Reading the flags of the reply is how you tell them apart, and the reply I did not expect was this one.

```console
$ dig +dnssec +noall +comments cloudflare.com @10.1.50.53 | head -3
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 34837
;; flags: qr rd ra ad; QUERY: 1, ANSWER: 3, AUTHORITY: 0, ADDITIONAL: 1

$ dig +dnssec +noall +comments cloudflare.com @10.1.20.1 | head -3
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 4296
;; flags: qr rd ra; QUERY: 1, ANSWER: 3, AUTHORITY: 0, ADDITIONAL: 1
```

Same name, same second, same chain — and the answer my client actually receives has no `ad` flag, because the hop that hands it over does not validate DNSSEC and does not repeat a claim it cannot make. The `ad` bit means *"the resolver answering you checked this"*, not *"this name is signed"*. It is testimony about one hop, and if you read it as a property of the domain you will draw the wrong conclusion at exactly the wrong moment.

The same lesson, with a sharper edge, comes from a domain that is deliberately broken.

```console
$ dig +noall +comments dnssec-failed.org A @10.1.20.1 | head -3
;; ->>HEADER<<- opcode: QUERY, status: SERVFAIL, id: 8925
;; flags: qr rd ra; QUERY: 1, ANSWER: 0, AUTHORITY: 0, ADDITIONAL: 1

$ dig +cd +noall +answer dnssec-failed.org A @10.1.20.1
dnssec-failed.org.  171  IN  A  96.99.227.255
```

Ask the gateway and you get SERVFAIL, which reads like my resolver protecting me. Set the checking-disabled bit and the same gateway returns the address — the signature of a resolver that is not validating at all. Ask Technitium with CD set and it still refuses, and now it explains itself:

```text
; EDE: 6 (DNSSEC Bogus)
; EDE: 22 (No Reachable Authority): (https://dns.adguard-dns.com/dns-query (94.140.15.15)
          returned RCODE=ServerFailure for dnssec-failed.org. A IN)
```

[Extended DNS Errors](https://www.rfc-editor.org/rfc/rfc8914) are the most underrated feature in DNS. The box I administer told me, in the reply, that the refusal was decided by the public resolver it forwards to. Which is the truth of my setup: my internal chain does not validate anything for public names. Somebody else does, on a hop I do not own, over plaintext port 53, and my `ad`-less answer at the client is the honest report of that arrangement. It is on my backlog as a to-fix, not a design — and it is a good illustration that "DNSSEC is on" is a statement about a link, not about a domain.

Two smaller measurements, both of which shaped how I read logs. There is no PTR record for `10.1.50.53` in my zone, so every log line and every `ss` output shows an address where a name should be — resolve forwards, not backwards, unless you write the reverse zone too. And on `10.1.50.53` only ports 53 and the console's 5380 answer; 853 and 443 are closed, so the DoT and DoH listeners exist as features and not as facts. That is the shape I want on a management VLAN, but it means the encrypted path stops at the forwarder, and the forwarder is the hop I just showed you is deciding things.

## authority is a cron job

A zone is only as true as the process that writes it. Mine is a shell script on both hypervisors, every two minutes: for each container, `pct exec <id> -- hostname -I`, keep the first address matching `10.1.x.x`, else the first `192.168.1.x`, then POST it to the Technitium API on port 5380 with a token read from a root-only file. Records land at TTL 300. Virtual machines are still manual — same TTL, three exceptions at 3600 for the media hosts that never move.

Two properties of that design are worth stating out loud, because both are easy to get wrong when you copy the pattern.

**The record is the guest's own claim about itself.** `hostname -I` returns every address the guest has, in no guaranteed order. One of my containers reports four addresses, another reports three address families; the regex is the load-bearing part of the script, not the API call. Anything that changes what a guest believes about its own address — a new docker bridge, a netbird interface, an IPv6 lease — changes what goes into the zone, silently, within two minutes.

**The namespace is a composite and no single place shows it.** Static infrastructure has an FQDN in Technitium and nothing else: that is why `technitium.internal` was NXDOMAIN earlier. A DHCP client is supposed to get its short name from dnsmasq's lease table on the gateway — a database Technitium has never heard of. Two authorities, one apparent namespace, and the short form of a name is not a smaller version of the long one — it is a different database answering.

Adding a record by hand is where the composite becomes visible, so these are the four checks I run, in order. The write itself is one authenticated call to the zone API; the interesting part is what answers afterwards.

```console
# 1. what the zone holds — the write endpoint's read counterpart, token in the URL
curl -s "http://10.1.50.53:5380/api/zones/records/get?domain=pbs.internal.cleeryy.cloud&zone=internal.cleeryy.cloud&token=$TOKEN"

# 2. did it land on the authority? (aa = yes, and the TTL is the one you set)
dig +noall +answer pbs.internal.cleeryy.cloud @10.1.50.53

# 3. did it land on the resolver my clients actually use?
dig +noall +answer pbs.internal.cleeryy.cloud @10.1.20.1

# 4. is the negative answer authoritative too, so clients cache the "no"?
dig +noall +comments typo.internal.cleeryy.cloud @10.1.50.53 | head -3
```

Steps 2 to 4 are copied from runs I did while writing this; the API route in step 1 I confirmed only to the point of authentication — it answers `invalid-token` without a session, which is how you check a route exists on a panel you do not want to log into. The point of the sequence is that step 2 succeeding and step 3 failing is not a DNS bug; it is a missing domain override, and the fix lives on the gateway, not in the zone.

The failure modes follow directly. A record that was never created looks exactly like DNS being down, except that everything else resolves. A renamed guest keeps its old answer for up to five minutes after the fix, because TTL 300 outlives a two-minute cron. And a client that can reach a resolver of its own choosing — a phone with a hardcoded `1.1.1.1`, a guest VLAN allowed out on port 53 — bypasses every name-based policy you think you have, which is why my guest network permits DNS to one address and nothing else on that port.

## picking one, or three

I would not rank these tools. I would ask which of the three jobs is being neglected, because the tool that fixes it is not interchangeable with the others.

**If the missing job is policy**, Pi-hole is still the fastest path from nothing to a network that stops resolving ad domains, and its community is the reason every edge case already has a thread. Accept what it is not: a flat record list, no authoritative zone, no zone transfer. If you need two of them, the sync is a bolt-on, and [one documented case of a bolt-on "full sync" replacing a primary's blocking database with an empty one](https://senn-tech.com/en/blog/technitium-dns) is a better argument than any benchmark: a sync that can wipe your primary is not high availability.

**If the missing job is recursion you control**, Unbound is the right shape and will never meet you halfway. You get a config file, `unbound-control`, DNSSEC validation that actually happens, query-name minimisation, and no dashboard to screenshot. You will read `dig` output instead, and after a month you will prefer it.

**If the missing job is authority** — real zones, a second server that stays in sync, conditional forwarding for several domains, one console — Technitium is the only one of the three that was built for it. The price is a smaller community, one very active maintainer, and more surface to understand than a sinkhole with a dashboard. The price is worth it the first time you need `pbs.internal.example` to mean the same thing on two resolvers.

Running all three is legitimate, and it is what I do: Unbound at the edge for the cache and the per-VLAN exposure, Technitium for the zone, the public forwarder for the internet. It costs three places to look, which is why the diagnostic order matters more than the architecture:

1. Query the resolver your client actually uses, and read the flags. `aa` means authority answered; a missing `ad` means this hop did not validate; both are information, not failure.
2. Query each stage by IP. The first stage that returns something different from the one before it is the one that changed the answer.
3. Read the EDE. If a hop refuses and can say why, the why is in the reply and it names the next hop.
4. Only then look at configuration — and check the client's search domain before blaming the server for a name it was never asked about.

## what the front door turned out to be

The front door is not a server. It is a decision path with three decisions on it, plus a client that quietly rewrites the question before asking. Everything that confused me in this lab for a year fits in one sentence: I was debugging one box while three of them — and my own laptop — were taking turns answering.

What I know now that I did not know this morning: my `ad` bit disappears at the hop that does not validate, and the SERVFAIL for a broken domain is decided by a public resolver I forward to, not by anything I administer. Neither fact changes a single record in the zone. Both change what I would check first the next time a name fails, and one of them turned into a backlog item — turn validation on at the edge and stop sending plaintext queries to a stranger, so that the answer I read at the client is one my own chain can stand behind.

The zone itself is fine. It has a serial, per-record TTLs, authoritative negatives, and an `NS` record pointing at a name that does not exist — because nobody ever asked it to be transferred, delegated, or proved. A homelab zone is a private dictionary. The day you need it to be infrastructure, you will want the transfer allowed, the second server configured, and the pointer to be a name that resolves.
