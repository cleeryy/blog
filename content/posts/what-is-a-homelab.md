+++
title = "what is a homelab (and why you should build one before you're ready)"
date = "2026-10-19T14:45:00Z"
author = "cleeryy"
authorTwitter = ""
cover = ""
tags = ["homelab", "beginners", "proxmox", "self-hosting", "guide"]
keywords = ["homelab", "home server", "proxmox", "self-hosting", "beginner guide", "mini pc", "raspberry pi"]
description = "a homelab is a personal playground where you learn infrastructure by breaking it safely. here's what it is, what it costs, and the exact setup i'd buy today."
showFullContent = false
readingTime = true
hideComments = false
+++

## the one-sentence version

a homelab is a server (or three) in your home where you learn how real infrastructure works by running it yourself — and breaking it, safely, at 2am, with nobody watching.

if you've ever thought "i'd love to understand docker/networking/linux properly but i don't want to break anything important" — that's exactly the problem a homelab solves. it's a sandbox with real consequences (your plex goes down, your family complains) but zero career risk.

## why bother? four honest reasons

**1. you learn 10x faster by touching things.** reading about VLANs for a week < configuring one wrong once and losing access to your own NAS for an evening. the scar tissue is the lesson. this matches what every homelabber will tell you: the community wisdom on r/homelab boils down to "build it, break it, snapshot first next time".

**2. privacy and independence.** your photos, your DNS queries, your notes — on your disks, under your rules. not because "big tech is evil", but because it's *your* data and depending on nine subscriptions to access your own files is absurd.

**3. career fuel.** there's a reason hiring managers light up at "i run a homelab": it proves you can do the whole loop — install, network, secure, monitor, back up, document. one DevOps guide puts it well: homelabs are where you practice "technologies too risky for production systems" ([usmanmasoodashraf.com](http://usmanmasoodashraf.com/posts/my-first-homelab-setup/)).

**4. it's genuinely fun.** SSHing into your own rack from a train hits different.

## the three paths: buy, build, or rent?

the eternal question, well covered by [readthemanual's buy/build/rent guide](https://readthemanual.co.uk/getting-started-homelab-buy-build-rent/). here's my honest take on each:

**buy refurbished (my recommendation for 90% of people).** an ex-corporate mini PC — Lenovo ThinkCentre Tiny, Dell OptiPlex Micro — costs €100-150, sips 10-35W, and runs proxmox with a handful of VMs without breaking a sweat. 16GB RAM minimum, 32GB if you can. RAM is always the first bottleneck, everything else can wait.

**buy new mini PC.** the intel N100 class is the current sweet spot: ~6-8W idle at the wall, ~20W under load, silent, around €150-200. annualized that's roughly €10-25/year in electricity ([bigiron.cc measurements](https://www.bigiron.cc/guides/the-n100-n305-mini-pc-class-what-fits-and-what-does-not)). if silence and power bills matter (they will), this is the chip.

**build custom.** only makes sense for storage beasts (many drive bays) or specific needs (GPU passthrough). for a first lab, it's the slowest path to something running. get something working first, build later when you know what you actually need.

**rent a VPS.** great for learning cloud, hosting something public, or as a WireGuard gateway back home. terrible as your *only* lab: no hardware reality (thermals, disks dying, power cuts), monthly bill, and someone else's computer. i started with a VPS for this very blog — and look where that got me (see [welcome-back](/posts/welcome-back/)).

## what i'd buy today (3 budgets)

- **~€0 — the closet lab**: that old laptop in your drawer + proxmox or plain debian + docker. zero cost, real lessons. start here if you're unsure.
- **~€150 — the sweet spot**: refurbished mini PC, 16GB+ RAM, 512GB SSD + proxmox. runs 15-20 containers or 3-5 VMs: DNS filtering, reverse proxy, monitoring, media, the works.
- **~€300 — the comfortable lab**: N100 mini PC (silent, efficient) + a raspberry pi 5 for always-on lightweight services (DNS, wireguard endpoint) + a cheap VPS for public stuff.

## your first week: a project ladder

don't build the dream architecture on day one. do this instead:

1. **day 1-2**: install proxmox, spin up one debian VM, break it, restore the snapshot. learn snapshots *before* you need them.
2. **day 3-4**: deploy pihole or adguard in docker. 30 minutes, your whole network gets better, and you've learned docker + DNS in one shot.
3. **week 2**: add a reverse proxy (caddy or nginx-proxy-manager) and reach two services by name instead of `http://192.168.x.y:port`.
4. **week 3**: uptime kuma watching everything. you'll discover how often things silently die.
5. **week 4**: your first real backup with an actual restore test. (an untested backup is a rumor, not a backup — whole article coming on this.)

## my 5 rules (learned the hard way)

1. **name everything like you'll forget** — my containers are ID=VLAN+IP so i always know where something lives.
2. **snapshot before, not after** — the 10 seconds that save weekends.
3. **one front door** — every service behind the same reverse proxy with real TLS. no `:port` jungle.
4. **if it's not monitored, it's already down** — you just don't know it yet.
5. **document as you go** — future-you at 2am during an outage will thank present-you.

## what's next in this series

next up: installing proxmox and your first VM, step by step. then LXC vs VM, SSH done right, docker basics — and from there into the deep end: VLANs, OPNsense rules, backups that actually restore, and the gitops pipeline serving you this page.

the lab is waiting. go break something (after the snapshot).
