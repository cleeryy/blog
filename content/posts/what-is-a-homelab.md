+++
title = "what a homelab actually is"
date = "2026-10-19T14:45:00Z"
author = "cleeryy"
authorTwitter = ""
cover = ""
tags = ["homelab", "self-hosting", "essay", "own-your-data"]
keywords = ["homelab", "home server", "self-hosting", "proxmox", "opnsense"]
description = "A homelab is infrastructure you own, where the consequences reach you. From one dead VPS to a small cluster at home: what ownership changes, and how to think about starting."
showFullContent = false
readingTime = true
hideComments = false
+++

*For two years I rented servers and learned to be a customer. Then I started owning them, and learned how they work. This is about that difference — and how to get it for roughly the price of a used office PC.*

## A personal infrastructure with your name on the failures

Ask five homelabbers what a homelab is and you'll get five answers involving racks, LEDs, and strong opinions about filesystems. Here's a simpler one that has held up for me: a homelab is infrastructure you run at home, outside of production, where the consequences of everything reach you personally.

That last clause is the whole definition. A lab at work has a team, a budget, and a blameless post-mortem culture. A homelab has you, your evenings, and the specific silence of a house where the media server just died during movie night. It is a place to learn systems from the inside — virtualization, networking, storage, security — with real stakes and zero career risk. If that sounds like a strange hobby, it is. It is also, in my experience, the fastest way to actually understand the field I'm studying.

A word on what it isn't, because three neighbors cause constant confusion. It isn't a NAS: network storage is one component, not the project. It isn't home automation: smart bulbs are remote controls, not infrastructure you operate. And it isn't a miniature public cloud: nothing here serves strangers for money. A homelab serves one household's curiosity — small audience, full responsibility.

## The line where renting stops teaching

This blog used to live on a rented virtual server: plain Apache, monthly bill, no thought about hardware. It worked fine until I cancelled the VPS, at which point the blog simply ceased to exist. What survived was a backup tarball in my Nextcloud — and the resurrection, from that tarball to the pipeline serving this page, is told [here](/posts/welcome-back/).

I'm fond of that story, but the useful part isn't the recovery. It's what the setup never taught me. A VPS draws a hard line at the hypervisor: below your virtual machine — the hardware, the network paths, the disks aging quietly — everything is someone else's problem by design. Good product, honestly. But learning stops exactly at that line, and the interesting failures live below it. Renting teaches you interfaces; the machinery underneath stays abstract forever. You can be a perfectly competent VPS customer for years and never once think about what happens when a drive starts clicking.

Ownership moves the line. When the machine is yours, there is no below-the-contract. There is just the stack, all the way down, and you, meeting it layer by layer.

## What mine is made of (and why each part exists)

My setup, as documented today: a two-node Proxmox cluster for compute, an OPNsense firewall dividing the home network into dedicated VLANs, a Caddy reverse proxy as the single front door with automatic certificates, a Proxmox Backup Server keeping nightly copies plus an encrypted offsite, and app deployments flowing straight from git. Nothing here was bought to impress; each piece answers one persistent question.

Proxmox answers *where does this run*. Virtual machines for the heavy and the risky, lightweight containers for the rest, and snapshots — one click capturing a machine's entire state before you touch anything. The first time you destroy something and bring it back in under a minute, caution stops being fear and starts being a habit. That habit, more than any feature, is what virtualization is for at home.

OPNsense answers *who may talk to whom*. With the home network split into VLANs — trusted devices, services, management, guests — every firewall rule is a small statement about trust: this network reaches that service, on this port, for this reason, and the default answer is no. Writing those rules was the first time I ever mapped what everything in my house actually talks to. No course assigned that; the firewall demanded it.

Caddy answers *how the outside reaches in*. One front door, real encryption everywhere, services addressed by name instead of a jungle of ports. As I write this, sixty-five virtual hosts pass through that single door. It sounds cosmetic until you realize it changed how I think about exposing anything: if a service can't earn its place behind the front door, it probably shouldn't be exposed at all.

Three more services answer questions you don't know you have until something breaks. Technitium, the internal DNS, answers *how anything finds anything*: every container registers its name automatically, so the whole lab talks in names, never in numbers you have to remember. Authentik answers *who may enter*: one identity, one login, guarding the services that matter instead of a dozen scattered passwords. And Warpgate answers *how I get in*: a single SSH doorway with proper authentication, so remote access means one hardened path instead of ports forwarded hopefully. None of these serve a single app. They serve all of them, invisibly, which is exactly why they're critical — you only notice infrastructure like this the day it stops.

Then there's the part the family actually sees: the files, the photos, the movies. Nextcloud holds the documents, Immich keeps the photo library off someone else's cloud, and a small media stack serves the living room. These are the services that justify everything above to non-technical humans. A firewall rule impresses nobody at dinner; photos that load instantly, from your own server, do.

The backup server answers *what survives*. Nightly copies, an encrypted copy far away — and one dated fact I'm genuinely glad to have: a full restore was tested and booted. That test converted a belief into knowledge. Around here the rule is simple: a backup you've never restored is a rumor, not a backup.

And the git pipeline answers *how this page reaches you*: source on git, image built and scanned automatically, deployed to my own machines on every push. The blog you're reading is both the subject and the demonstration.

## Your own stack, end to end

There is a second reason people build labs, and honestly it might be the stronger one: at some point you look at the list of subscriptions draining your account every month — storage here, photos there, notes somewhere else, a VPN on top — and you do the math. One recent survey put the average at $273 a month across a dozen subscriptions, with nearly four in ten subscribers planning to cancel at least one. Even halving those numbers for a European student budget, the shape of the problem is familiar: a dozen small rents on your own digital life, each too cheap to question, adding up to something you absolutely feel.

Self-hosting is what happens when you question them all at once. The idea is disarmingly simple: instead of renting software that runs on someone else's computers, you run free software on yours. Files, photos, passwords, media, notes — the same categories you currently pay for, living on hardware you own, reachable from anywhere through your own front door. The community keeps [a vast public index of such software](https://awesome-selfhosted.net/), thousands of projects deep, and browsing it feels less like shopping and more like discovering the size of the cage you were in. And to stay current once the initial wonder wears off, [selfh.st](https://selfh.st) collects self-hosted news, launches, and updates in one place — honestly, a good share of what I know about this world came through there.

The honest price tag is time, not money. When you self-host, you become the CTO, the sysadmin, and the support team all at once: you patch, you monitor, you fix what breaks on Sunday evening. Anyone telling you self-hosting is "free" is selling something. But that responsibility is exactly the appeal — every service you reclaim is something nobody can take away, reprice, or discontinue. There is a particular satisfaction in knowing your photos, your files, your notes sit on disks you own, readable by no one else, with no terms of service between you and them. Not paranoia: verifiability. A promise in a privacy policy is a story someone tells you. A server in your home is a fact you can check.

And yes, let's be honest about the shallow part too: having real hardware is fun. RAM sticks, blinking drives, a dashboard showing *your* services all green — there's a pride in it that no cloud console reproduces. It's your stack, end to end, and it hums in your home. That feeling, as much as any principle, is what turns a curious beginner into someone who stays.

And all of it rests on something worth saying out loud: open source. Every service above — the hypervisor, the firewall, the proxy, the backups, the pipeline — is free software built by people who simply decided the world should have it. No licenses to negotiate, no sales calls, no one asking for your job title before letting you build. That matters more than it sounds. It means someone with a student budget and a closet can run the same classes of systems as companies with entire departments — networks, monitoring, automation, the works. Nobody gets to tell you it's not for you, that you're not the right kind of person, that you're not capable. The gate is open and unguarded. There is a whole worldwide community of passionate weirdos running entire infrastructures from their homes and sharing everything they learn, and the price of admission is curiosity. I love that about this world. It might be my favorite part.

## What the consequences taught me

Three patterns keep showing up, and I offer them as observations from one lab, not laws of nature.

First, failures come with a return address. Recently my deployer silently stopped updating a container, and the cause turned out to be one orchestration setting about stopping old containers before starting new ones. Untangling that taught me how rollouts actually sequence — the kind of mechanism I'd previously only nodded along to in talks. When there's no vendor to ticket, confusion has nowhere to go except understanding. Slowly. At 2am, sometimes.

Second, privacy arrives as a side effect. I didn't start filtering my home DNS out of principle; I started because pages loaded clean and quiet, and then routing my own queries just felt normal. The opinions came later, and they're sturdier for it. A lot of self-hosting works this way: comfort first, convictions earned.

Third, discipline compounds quietly. Snapshot before changes. One front door. Monitoring on everything, because computers fail silently as a default state. Restores tested on a schedule. None of this is homelab folklore — it's ordinary production hygiene, learned someplace where mistakes cost an evening instead of a job. One practitioner [describes these labs](http://usmanmasoodashraf.com/posts/my-first-homelab-setup/) as rooms for "technologies too risky for production systems." I'd add: the risk is doing most of the teaching.

## Starting, without the shopping list

So how should *you* think about starting? The honest answers in this space are refreshingly boring. The most repeated serious advice is a refurbished office mini PC — around €100–150 with 16GB of RAM — and [the clearest comparison of the three paths](https://readthemanual.co.uk/getting-started-homelab-buy-build-rent/) (buy used, buy new, rent) concludes the same way the community does: memory runs out first, buy what you need now, expand when something actually limits you.

If the box will live near people, efficiency matters, and the current reference point is Intel's N100 class: about 6 watts idle at the wall, [measured over and over, not marketed](https://www.bigiron.cc/guides/the-n100-n305-mini-pc-class-what-fits-and-what-does-not/), on the order of €10–25 a year in electricity. The real budget was never hardware, though. It's evenings — and the willingness to spend a few of them confused.

Two questions beat any equipment list. What do you want to *understand* — virtualization, networks, data durability? Buy the cheapest thing that lets you touch exactly that. And what is your restore story for the first thing you host? If the answer is "later," start there: in week one, break something unimportant on purpose and bring it back. Ten minutes means you have a lab. A weekend means you have your first lesson. Both outcomes are the point.

That's the premise this series runs on: one documented lab, real choices, reasoning you can borrow. Next we install Proxmox and meet the hardware properly. Bring a spare evening — and snapshot first.

## Sources

- Eric Lonsdale, [Getting Started with a Homelab: Buy, Build or Rent?](https://readthemanual.co.uk/getting-started-homelab-buy-build-rent/) — readthemanual.co.uk (refurbished picks, RAM guidance, the three paths).
- [The N100/N305 mini-PC class: what fits and what doesn't](https://www.bigiron.cc/guides/the-n100-n305-mini-pc-class-what-fits-and-what-does-not/) — bigiron.cc (idle/load power measurements).
- Usman Masood Ashraf, [My First Homelab Setup](http://usmanmasoodashraf.com/posts/my-first-homelab-setup/) — DevOps practitioner's take on labs as safe ground for risky tech.
- [awesome-selfhosted](https://awesome-selfhosted.net/) — community index of self-hostable software.
