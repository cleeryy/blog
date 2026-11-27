+++
title = "nine open ports, two tunnels: how a service actually meets the internet"
date = "2026-11-27T06:48:00Z"
author = "cleeryy"
authorTwitter = ""
cover = ""
tags = ["homelab", "networking", "security", "cloudflare", "tunnels", "nat", "tls", "opnsense"]
keywords = ["cloudflare tunnel", "cloudflared", "argo tunnel history", "named tunnels", "port forwarding", "dnat", "opnsense nat", "cgnat", "carrier-grade nat", "tls termination", "reverse proxy", "zero trust access", "tailscale funnel", "wireguard vpn", "exposing homelab services", "shodan", "internet scanning", "zmap", "upload limit 100mb", "cloudflare terms cdn", "cloudflared apache 2.0", "cf-connecting-ip", "origin pulls", "unreachability"]
description = "My firewall holds nine destination-NAT rules on the WAN interface and two outbound tunnels at the same time, and that is not indecision. A tunnel's real security property is not encryption but unreachability — and it is billed in client IPs, TLS termination, protocol limits, 100 MB request bodies and a dependency you cannot fail over. A threat model of each door, with the numbers I measured and the ones I checked instead of remembering."
showFullContent = false
readingTime = true
hideComments = false
+++

*As I write this, one firewall of mine holds nine destination-NAT rules on its WAN interface and two outbound tunnel connectors, one per Proxmox node, both up. Nine ports the internet can knock on, and a service mesh besides. Both approaches, simultaneously, by choice — because the question is not which one is more secure. It is what each one promises, and what it bills you for afterwards.*

## the table is a decision record

I read the NAT table rather than my memory of it, and this is what it says: two rules for web traffic on 80 and 443, both landing on the same reverse proxy. One for SSH on port 22, forwarded to a bastion listening on 2222. Three for mail — 25, 465, 993 — all pointing at one mail server. Three more UDP ports, 8766, 27015 and 27016, that all belong to a single game server.

Nine ports, four services, one public address. Two internal redirects also exist, on other interfaces, but they never touch the internet and are not part of this story.

Alongside that, two `cloudflared` connectors run on two different nodes and publish a different set of hostnames through Cloudflare, plus an overlay mesh that carries my actual remote access. Both connectors are up as I write this — though not on the same version: one runs 2026.11.0, the other 2026.10.4. Cloudflare's repository README supports only releases within one year of the latest, which is a generous window, but the drift is a small reminder that a connector is software you own and have to update.

The immediate reading of that table is inconsistency. The accurate reading is that a firewall table is a record of decisions, and mine says something specific about each service: who has to reach it, in what protocol, and who is willing to be responsible for the traffic.

That sentence hides three questions, and each one eliminates options before security enters the conversation.

**Who must reach it?** An anonymous visitor with a browser and no instructions, an authenticated colleague, or only the person holding a key. That single answer narrows the field before any security control is discussed.

**What protocol does the client speak?** A browser speaks HTTP. A mail client speaks SMTP and IMAPS. A game client speaks UDP and does not care about your certificate. A tunnel built for HTTP cannot carry the latter two, and no amount of configuration changes that.

**Who terminates TLS and absorbs the attack traffic?** Either your box does, with your certificate and your uplink, or somebody else's edge does, with their certificate and their capacity — and their logs.

Nothing about "expose it safely" is decidable before those three are answered. Which is why the nine ports and the two tunnels coexist: they are answers to different questions, not competing answers to the same one.

## three doors, three promises

A **port forward** is a promise of reachability. You publish an address, and a rule maps (address, port) to (internal host, port). From the internet's point of view the service now exists at a routable location; from yours, the edge of the network is your router, your certificate, your line. This is the oldest option and the only one that works for arbitrary protocols without a client-side agent.

A **tunnel** is a promise of a name without an address. The connector in your network dials out to a third party's edge and keeps that connection alive; requests for a public hostname arrive on that connection and are handed to a local service. Nothing listens for inbound connections on your side. [Cloudflare's own documentation](https://developers.cloudflare.com/tunnel/) states the model plainly: `cloudflared` "initiates an outbound connection through your firewall from the origin to the Cloudflare global network", after which traffic flows both ways over it, and you can "block all inbound traffic, effectively blocking access to your origin from anything other than Cloudflare".

A **VPN** is a promise of identity before reachability. Nothing is published; a peer authenticates with a key and only then gets an address inside a private network. The service never meets the internet at all. I wrote about the mechanics of that in [the WireGuard piece](/posts/wireguard-remote-access/), so here it only needs to exist as the third option, because it is the correct answer far more often than it gets chosen.

### the edge is orthogonal to the door

One clarification before the comparison hardens into a false dichotomy: a port forward does not necessarily mean *your* edge.

Put a DNS record behind Cloudflare's proxy and forward 443 to your own reverse proxy, and the visitor's TLS still ends in a Cloudflare data centre, with WAF, cache and DDoS absorption in front of the origin. That is exactly how this blog is served — the response headers say `server: cloudflare` and `via: 1.1 Caddy`, which means the request crossed the edge, then an open port, then my proxy. So "tunnel" is not the only way to borrow an edge. What the tunnel changes is **reachability**: whether a routable address exists at all.

And that difference is where the honesty sits. My web DNAT rules accept from any source. The edge therefore filters noise and absorbs volume, but it is not an access control: anyone who learns the address can bypass it and knock on the port directly. If the edge is supposed to be a control and not a convenience, the rule has to be narrowed to Cloudflare's published ranges, and that list has to be maintained. A proxied record with an unrestricted port forward is a common configuration and a quietly weaker one.

Those are three genuinely different products. What follows is where each one is good, and what each one charges.

## where the tunnel came from

The tunnel is not a Cloudflare invention in spirit — SSH has done `-R` for decades — but its current shape has a specific lineage, and the lineage explains the product's limits better than any feature list.

There is also a business logic to it that is easy to miss. A CDN company's entire position depends on being in the request path; an origin with no public address, or one behind CGNAT, was a customer it could not serve at all. A tunnel is the product that extends the path to those origins — and, not incidentally, makes the edge mandatory rather than optional.

The `cloudflared` repository was created in October 2017. On 5 April 2018 Cloudflare announced the product as **Argo Tunnel**: a daemon on your origin dialling out so that, in the launch framing, the server stays unroutable to the rest of the internet. It was sold alongside the paid Argo Smart Routing product, since visitor traffic still had to reach the data centre nearest the origin. Two years later, in [October 2020](https://blog.cloudflare.com/argo-tunnels-that-live-forever/), came **Named Tunnels**: a tunnel acquired a permanent name and UUID, DNS records stopped being tied to ephemeral connections, and the migration to Cloudflare's edge load balancer raised the average lifetime of a connection from minutes to days. Then, on [15 April 2021](https://blog.cloudflare.com/tunnel-for-everyone), the outbound-only connection became free for every organisation and the product was renamed **Cloudflare Tunnel**.

That April 2021 post is worth reading for what it admits. The predecessor architecture required both the control plane and the data plane to be online for a reconnect, and a restart was treated as a brand new tunnel — new DNS record, new everything. The free version arrived with the reliability work, not before it.

Where it stands now: the client is open source under Apache-2.0, the control plane is not, and the documentation describes four long-lived connections per connector to at least two distinct data centres, over port 7844, QUIC by default with an HTTP/2 fallback over TCP, post-quantum key agreement by default and fallback if it fails. Up to 25 replicas per tunnel, 100 connections. And in 2026 the product family has split: Tunnel for publishing HTTP applications on the public internet, [Cloudflare Mesh](https://developers.cloudflare.com/mesh/) as the recommended connector for private networks. The same daemon, two different jobs, which is a useful sign that the line between "publish" and "connect privately" was never as clean as the marketing suggested.

The honest ledger, since nobody needs another feature list. What it does well: it removes inbound reachability as a category, it puts DDoS absorption, WAF, caching and bot rules in front of the service without you owning any of that capacity, it automates certificates, it works from behind CGNAT, and the free tier is genuinely free. What it costs: a third party sits in the request path and can see the plaintext, the public hostname must live in a zone whose DNS is on Cloudflare, public ingress is HTTP-shaped, request bodies are capped at 100 MB on the free and Pro plans, the terms restrict large media through the CDN, and the client address your server sees is the edge's, not the visitor's. Each of those is a design consequence, not a bug, and each has a workaround with its own bill.

## what "no open port" actually buys

Here is the part that gets said badly on both sides of the argument. A tunnel does not make your traffic more encrypted than TLS already did. The security property it buys is **unreachability**: there is no listening socket on a routable address, so there is nothing for a scanner to find, and the only way in is through whatever policy sits at the edge.

That property is worth more than it sounds, because the background noise of the internet is not a metaphor. Sophos ran SSH honeypots in ten AWS regions in 2019 and the first login attempt arrived in **52 seconds** in São Paulo; the slowest site, Ireland, took one hour and forty-four minutes ([ZDNet's write-up](https://www.zdnet.com/article/this-server-was-online-for-under-a-minute-before-cyber-criminals-started-to-hack-it/)). Palo Alto's Unit 42 deployed 320 honeypots across three continents in 2021 and found that **80% were compromised within 24 hours**, all of them within a week, with the mean time to first compromise for SSH around three hours ([Unit 42](https://unit42.paloaltonetworks.com/exposed-services-public-clouds/)). And the scanning itself is cheap: the [ZMap paper](https://www.usenix.org/system/files/conference/usenixsecurity13/sec13-paper_durumeric.pdf)'s headline number was a full IPv4 sweep for a single port in under 45 minutes from one machine.

Two distinctions matter before anyone panics. The first: **being found is not being broken**. Unit 42's honeypots were deliberately weak — default credentials, vulnerable builds — which is why "compromised in three hours" describes an unpatched service with a guessable password, not your reverse proxy with a valid certificate and one route. The second: what an open port actually does is convert your patch cadence into a public commitment. Every port is a permanent obligation to keep one piece of software current, and the obligation does not pause when you are on holiday.

So the honest framing is: an open port is a subscription to every scanner on the planet, and the renewal price is your patch lag. That is a defensible price for a mail server. It is harder to defend for a dashboard you check twice a week.

## the bill for unaddressability

Now the other side, because a tunnel is not a free abstraction either.

**Your logs stop telling you who is calling.** Every request arrives from a Cloudflare address. In my own setup this is written down as a rule rather than a discovery: firewall-level bans do not touch the real client behind the edge, because the address the firewall sees belongs to Cloudflare. What works is the application layer — a reverse proxy configured to trust Cloudflare's ranges and to read `CF-Connecting-IP`, plus a ban engine that acts there rather than in `pf`. If your threat model depends on "block this IP at the firewall", putting the edge in front quietly removes that tool and expects you to notice.

**TLS ends at the edge, not in your rack.** The certificate a visitor sees is Cloudflare's, for your name, and the session terminates in the nearest data centre. Between the edge and your origin you then choose: HTTPS with a valid or origin-CA certificate (`Full (strict)`, plus Authenticated Origin Pulls if you want to prove the request really came from Cloudflare), or plain HTTP, which is the shape of the example configurations in the documentation — `app.example.com` to `http://localhost:8080`. That last form means the hop from the connector to your application is cleartext inside your own network. Usually fine, since it is a loopback or a LAN, but it is not "end-to-end encrypted to my server", and the difference matters when the service handles credentials.

**The protocol wall is real and it is not negotiable.** A published hostname is a layer-7 HTTP proxy. The documentation is explicit that TCP, SSH and RDP are supported by streaming them over a WebSocket — which means the *client* must run `cloudflared access` or the WARP client. A browser cannot. And UDP, for public ingress, is not available at all: Spectrum can carry it, but Spectrum public UDP is an enterprise add-on. This is exactly why three of my nine ports are UDP for one game server and three more are mail. SMTP and IMAPS are not HTTP, no HTTP tunnel will carry them, and a mail server that requires every correspondent to install a client is not a mail server.

**The limits are contractual as well as technical.** Free and Pro plans cap request bodies at [100 MB](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/4xx-client-error/error-413/), so a photo backup or a large upload fails with a `413` at the edge while the application logs nothing. And the CDN terms, in [the version updated 28 September 2026](https://www.cloudflare.com/service-specific-terms-application-services/), still read: "Cloudflare offers specific Paid Services (e.g., the Developer Platform, Images, and Stream) that you must use in order to serve video and other large files via the CDN", with the right to "disable or limit your access" if you use the CDN without them. A tunnel's public hostname is served through that same proxy. So streaming a media library through a free tunnel is not a performance question, it is a terms question — and the answer has been the same since Section 2.8 was retired in 2023 and its substance moved into the service-specific terms.

**And there is no failover you control.** The tunnel's DNS record is independent of the connector: if the connector stops, the record stays and visitors get error 1016. That is a clean failure, but it is a failure with exactly one path back, and the path runs through a company whose incident history is not yours to schedule. For a status page, that may be acceptable. For the thing that opens your front door, it is a decision worth making explicitly.

## what an open port actually costs

The other door has its own invoice, and it is shorter but sharper.

You publish an address. That address becomes a target, and it is also a fact about you: an IP maps to an ISP, often to a region, sometimes to a building. Volumetric attacks do not get absorbed by anyone — they arrive at your line and consume it, which means the ceiling of your defence is your uplink, not your firewall's rule set.

The compensating advantage is control. You terminate TLS with your own certificate, you choose the proxy, you see real client addresses, you can carry any protocol, and no third party can rate-limit your uploads or reinterpret a clause. In my case the two web ports exist precisely so that one reverse proxy owns every hostname: nine ports, but only four listening services, and exactly one thing is directly reachable per port.

The rule count is not the risk; the rule *width* is. A DNAT that forwards 443 to a proxy which then routes by name is a narrow promise. A DNAT that forwards a whole protocol to a host with several services on it is a much wider one, and the difference is invisible in a port scan.

One more constraint that people discover late: this option may not exist. Carrier-grade NAT is not an edge case. A 2016 measurement across more than 1,500 networks found CGNAT deployed in **17–18% of eyeball networks** and in **more than 90% of cellular ones** ([Richter et al., IMC 2016](https://www.prichter.com/imc176-richterA.pdf)), and the direction has only gone one way since. Behind CGNAT, a forward on your router opens a port on an address that has already been translated; nothing outside can reach it. "Port forward or tunnel" then stops being a preference and becomes a budget line: either you rent an address, or you rent somebody's edge.

## the third door, which is usually the right one

The option that gets skipped in these comparisons is the one where the service is never published at all.

For anything administrative — hypervisor consoles, backup appliances, dashboards, the git forge, the router itself — the correct threat model is not "expose it carefully", it is "do not expose it". A VPN reduces the public surface to a single authenticated entry point, and a mesh overlay reduces it further: nodes dial out to a coordination service, peers find each other, and there is no inbound port anywhere. That is what carries my remote access today, and it is the reason the road-warrior UDP listener on the firewall is configured but not forwarded.

The cost is honest and mostly human: every device needs a client or a key, onboarding is a task, revocation is a task, and a device that cannot install anything cannot get in. A hub-and-spoke VPN re-exposes exactly one port, so it is not zero surface — just a much smaller, much more defensible one. A mesh with outbound-only coordination is closer to zero, at the price of trusting a control plane with your peer list.

None of this is exotic. It is the option that requires saying no to a public URL, and that is usually the whole difficulty.

## how i decide now, and how i check

The order I actually apply, with the reasoning compressed:

1. **Is this only for me, or for people I can onboard?** Then stop — VPN or mesh, no public name.
2. **Does a stranger's unmodified client need it?** If no, stop — same answer.
3. **Which protocol?** UDP, raw TCP, SMTP, IMAPS: port forward (or a VPS relay). HTTP or HTTPS: either door is open.
4. **HTTP, and the zone's DNS is on Cloudflare?** A tunnel is the cheaper edge, unless the payload is large media or regularly above 100 MB.
5. **Does the service need real client addresses for its own security decisions?** If yes, either terminate at your own proxy or move the enforcement to the edge, but decide deliberately.
6. **What happens when the third party is down?** If the answer is unacceptable, do not put it behind a tunnel.

Then two checks, because both doors fail in ways that look like success. The first is a probe from a machine that is not the proxy — in my case the container writing this, so the packets leave through the same WAN they are testing. I aimed it at my own published hostname, and the results are more instructive than a pass/fail:

```console
$ for t in "blog.cleeryy.cloud 443" "blog.cleeryy.cloud 8080" "127.0.0.1 9" "192.0.2.1 443"; do
>   set -- $t; s=$(date +%s%N); nc -z -w2 $1 $2; rc=$?; e=$(date +%s%N)
>   echo "$1:$2 rc=$rc ms=$(( (e-s)/1000000 ))"
> done
blog.cleeryy.cloud:443   rc=0 ms=25
blog.cleeryy.cloud:8080  rc=0 ms=23
127.0.0.1:9              rc=1 ms=3
192.0.2.1:443            rc=1 ms=2004
```

Read it in two passes. The exit code separates "something answered" (`0`) from "nothing did" (`1`) — that part is reliable. The code does **not** separate "a machine said no" from "nobody answered": the closed local port returned `1` in 3 milliseconds with a reset, and the documentation-range address returned `1` after 2004 milliseconds, which is the `-w2` timeout expiring. Silence and refusal share an exit code and differ in duration, so a script that only checks `$?` cannot tell a firewall drop from a dead service.

Then the surprise, which is the useful one: **8080 answered too**. Nothing in my lab serves 8080 on that hostname. What answered was Cloudflare — 8080 is one of the ports its proxy accepts HTTP on, and the name resolves to the edge. That name happens to reach my rack through the two open web ports rather than through a tunnel, which makes the lesson sharper instead of weaker: a port check against a proxied name tests the edge and never the origin, whichever door is behind it. It will report "open" for a service that has been down for a week. Reachability is not availability, and a proxied name makes the two diverge by design.

The second check is a look at what the origin reveals. One `curl -I` on the same hostname returns `server: cloudflare`, `cf-cache-status: DYNAMIC`, and — this is the one worth noticing — `via: 1.1 Caddy`. The proxy in my rack is announcing itself through a header the edge passes along. Harmless here; a fingerprint worth removing on anything that is supposed to look like a black box.

## what the table is a map of

Nine ports and two tunnels is not a messy compromise. It is the shape of four published services and a fifth category that never needed a public address at all: a browser that must arrive uninvited, a mail client that speaks protocols HTTP never will, a game that speaks UDP, a bastion that should be the only SSH door, and the services that stay private.

The question worth carrying to your own firewall is not "tunnel or port forward". It is the three-part question underneath: who must reach this, in what protocol, and who do I want terminating TLS and absorbing the noise. Answer those and the choice usually makes itself — including, quite often, the answer that involves no public door at all.

Which leaves the part worth keeping. The property that makes a tunnel attractive is not encryption; TLS gave you that either way. It is that there is nothing to find. And the price of being unfindable is that you stop seeing who is looking — a trade worth making consciously, one service at a time, rather than by default.
