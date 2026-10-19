+++
title = "own your computers: what a homelab teaches that the cloud doesn't"
date = "2026-10-19T14:45:00Z"
author = "cleeryy"
authorTwitter = ""
cover = ""
tags = ["homelab", "self-hosting", "essay", "own-your-data"]
keywords = ["homelab", "home server", "self-hosting", "rent vs own infrastructure"]
description = "two years of renting a VPS taught me to be a customer. Six months of owning my servers taught me how they work. On the difference that matters."
showFullContent = false
readingTime = true
hideComments = false
+++

for two years, this blog lived on a rented virtual server: a plain apache setup, a monthly bill, zero thought about hardware. it worked, right up until the day i cancelled the VPS — and the blog died with it. everything i had left was a backup tarball in my nextcloud. the resurrection, from that tarball to the gitops pipeline serving you this page, is told [here](/posts/welcome-back/). but the interesting question isn't how the blog came back. it's what changed in my head between renting that VPS and owning the machines it runs on now.

because that is what a homelab is, stripped of the rack photos and the blinking LEDs: a place where you own the computers, and therefore own the consequences.

renting teaches you the interface. a VPS gives you root on a machine you will never see, on a network you will never touch, with disks that never click before dying. everything outside your virtual box is someone else's problem — which is precisely why you learn nothing about it. that's not a flaw in the product; it's the product. but it means the learning stops at the hypervisor's edge, exactly where the interesting failures live.

owning teaches you the stack. the first time you install proxmox on a real box and your first VM can't reach the network, there is no support ticket to open. there's you, a cable, and documentation. eric lonsdale, who has written [the most honest beginner guide i know](https://readthemanual.co.uk/getting-started-homelab-buy-build-rent/), recommends starting with a refurbished office mini PC — around €100-150, 16GB of RAM minimum — precisely because the stakes are real but survivable. his rule of thumb matches what the community repeats everywhere: RAM runs out first, everything else can wait.

the objection is always money and power. both are smaller than they look. the current efficiency darling, intel's N100, idles around 6 watts at the wall — [measured repeatedly, not marketed](https://www.bigiron.cc/guides/the-n100-n305-mini-pc-class-what-fits-and-what-does-not/) — which works out to roughly €10-25 a year in electricity. that is less than two months of the streaming subscriptions most people keep without thinking. the expensive part of a homelab was never the hardware. it's the evenings.

so what does ownership actually buy you, intellectually? three things, in order.

first, failure with a return address. when my deployment pipeline silently refused to update containers last week, there was no status page to check — the bug was a swarm update-order setting buried in my own deployer, and finding it taught me how orchestrators roll out containers. a cloud user would have filed a ticket and learned nothing. i have the scar and the explanation. one DevOps practitioner [puts it crisply](http://usmanmasoodashraf.com/posts/my-first-homelab-setup/): homelabs exist to practice "technologies too risky for production systems." the risk is the feature.

second, privacy as a side effect of competence. nobody starts self-hosting photos or DNS out of ideology; they start because a thirty-minute ad-blocking DNS container makes every page on the home network load clean, and suddenly depending on nine subscriptions to reach your own files feels absurd. ownership first, opinions later. the ideology, if it comes, is earned.

third, the discipline that only consequences teach. snapshots before changes, one reverse proxy as the single front door, monitoring on everything because silent failures are the default state of computers, backups that get restore-tested because an untested backup is a rumor. none of these are homelab-specific wisdom. they're production wisdom, learned at home where mistakes cost an evening instead of a job.

none of this argues against the cloud. plenty of workloads belong there, starting with anything that must survive your house losing power. the honest framing, borrowed from the guides above: rent for reach and elasticity, own for understanding. my blog now lives on both sides of that line — source on github, containers built in CI, running on machines i can touch — and each side taught me what the other hides.

if you're considering it, here is the decision procedure i wish someone had handed me. if your goal is learning infrastructure, buy the refurbished box; if your goal is silence and low bills, buy the N100 new; if your goal is a public service by friday, rent the VPS — then ask yourself what happens the day you stop paying. and whatever you choose, do one thing in the first week: break something unimportant on purpose, and restore it. if restoration takes ten minutes, you have a lab. if it takes a weekend, you have your first lesson. either way, you win.

that is the promise of the series starting here: not a catalog of tools, but the reasoning behind real choices, with the receipts. next, we install proxmox — and find out what your hardware is actually capable of.
