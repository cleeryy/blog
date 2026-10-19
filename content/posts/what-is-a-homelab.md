+++
title = "what a homelab actually is"
date = "2026-10-19T14:45:00Z"
author = "cleeryy"
authorTwitter = ""
cover = ""
tags = ["homelab", "self-hosting", "essay", "own-your-data"]
keywords = ["homelab", "home server", "self-hosting", "proxmox", "opnsense"]
description = "A homelab is infrastructure you own, where consequences teach what manuals can't. From a dead VPS to a two-node Proxmox cluster: what ownership changes, and how to reason about starting."
showFullContent = false
readingTime = true
hideComments = false
+++

*Two years of renting servers taught me to be a customer. Owning them taught me how they work. A homelab is the difference — and it is smaller, cheaper, and more instructive than it looks.*

## The short answer

A homelab is a personal infrastructure run at home: servers, network, storage, and services you operate yourself, outside of production, to learn how real systems behave. The definition matters less than the property that makes it work: you own the computers, so you own the consequences. When something breaks at 2am, there is no support ticket — there is you, documentation, and a lesson you will not forget.

That last point is doing most of the explanatory work in this article, so let's make it precise: renting infrastructure teaches you interfaces, owning it teaches you systems. Everything below is an elaboration of that distinction, grounded in one real setup — mine.

## Renting teaches the interface

For two years, this blog lived on a rented virtual server running a plain Apache setup. It worked. I paid monthly, never thought about hardware, and learned almost nothing about hosting. When I cancelled that VPS, the blog died with it; all that remained was a backup tarball in my Nextcloud. The resurrection — from that tarball to the git pipeline serving this page — is recounted [here](/posts/welcome-back/).

The episode is instructive beyond anecdote. A VPS draws a hard line at the hypervisor: everything below your virtual machine — hardware, network, storage, failure — is someone else's problem by design. That is the product, and it is a fine product. But learning stops exactly at that line, which is where the interesting failures live: the disk that degrades, the network path that changes, the 3am latency nobody can explain. Renting is the right tool for reach and elasticity. It is a poor tool for understanding, because understanding lives one layer below the contract.

## Owning teaches the stack

My current setup, all documented and running as I write this: a two-node Proxmox cluster, an OPNsense firewall segmenting the home network into dedicated VLANs (trusted, production, management, guests, and more), a Caddy reverse proxy as the single front door with automatic TLS certificates, a Proxmox Backup Server with an encrypted offsite copy, and application deployments driven straight from git through Dokploy. Each layer exists to answer one question — where does this run, how does traffic reach it, what happens when it dies — and each answer was earned, not read.

Consider the firewall, because it best shows how ownership changes thinking. On a VPS, "firewall" means a cloud console checkbox. At home, with OPNsense holding seven VLANs, a firewall rule is a statement about trust: this network may reach that service, on this port, for this reason — everything else is denied by default. Writing those rules forced me to map, for the first time, what every device in my house actually talks to. No tutorial assigns that homework; consequences do.

Or backups. My Proxmox hosts back up nightly, and the one fact I am proudest of in this whole lab is dated: a full restore was tested and booted. That single verified restore is worth more than years of scheduled jobs, because it converted a belief ("we have backups") into knowledge ("restores work"). The standing rule here — an untested backup is a rumor, not a backup — was not adopted from a book. It was adopted the day the reasoning clicked: a backup you have never restored is a hypothesis about the future, and hypotheses need testing.

## What consequences teach that manuals don't

Three lessons keep recurring, each traceable to something concrete above.

First, failure arrives with a return address. Last week my deployment pipeline silently stopped updating a container; the cause was a single orchestration setting — services must stop before replacements start, or the old container keeps holding the port. A cloud customer files a ticket and learns nothing. I found the setting, fixed it, and now understand rollout ordering. The scar is the documentation.

Second, privacy follows competence, not the reverse. People rarely start self-hosting from ideology; they start because a thirty-minute DNS filter makes the whole home network quieter, and suddenly routing your own queries feels normal. Ownership first, opinions later — and the opinions, when they come, are earned rather than performed.

Third, discipline compounds. Snapshots before changes, one front door for all services, monitoring on everything because silent failure is the default state of computers, restores tested on schedule. None of this is homelab folklore; it is production hygiene, learned where mistakes cost an evening instead of a job. As one practitioner [puts it](http://usmanmasoodashraf.com/posts/my-first-homelab-setup/), these labs exist to practice "technologies too risky for production systems." The risk is load-bearing.

## How to reason about starting

If the above makes the case, the practical question is where to begin — and here the evidence favors boring answers. The most repeated serious advice for beginners is a refurbished office mini PC: roughly €100–150, 16GB of RAM minimum, enough for a dozen services. Eric Lonsdale's [buy/build/rent comparison](https://readthemanual.co.uk/getting-started-homelab-buy-build-rent/) lays out the three paths with unusual honesty, and its conclusion matches the community consensus: RAM runs out first, buy what you need now, expand when you hit a limit.

If silence and power bills matter — they will, once the box lives near people — the current efficiency reference is Intel's N100 class: around 6 watts idle at the wall, [measured repeatedly rather than marketed](https://www.bigiron.cc/guides/the-n100-n305-mini-pc-class-what-fits-and-what-does-not/), working out to roughly €10–25 a year in electricity. Against that, weigh the real budget: not hardware, but evenings.

Three diagnostic questions beat any shopping list. What do you want to understand — virtualization, networking, data durability? Buy the cheapest thing that lets you touch *that*. What breaks if the power goes out — and do you care? That answer sizes your UPS and your ambitions. And what is your restore story for the first thing you will host? If the answer is "I'll figure it out later," start there instead: break something unimportant on purpose in week one, and restore it. Ten minutes means you have a lab; a weekend means you have your first lesson. Either way, you win.

## Owning the question

So: a homelab is infrastructure you own, operated where the consequences reach you, for the purpose of understanding systems from the inside. Renting rents you reach; owning teaches you the stack. The distinction sounds philosophical until the first outage makes it concrete — then it becomes the most practical thing you know.

This series starts from that premise and stays close to one documented lab: next, installing Proxmox and meeting your hardware properly. Bring a spare evening. Snapshot first.
