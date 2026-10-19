+++
title = "what is a homelab (and why you should build one before you're ready)"
date = "2026-10-19T14:45:00Z"
author = "cleeryy"
authorTwitter = ""
cover = ""
tags = ["homelab", "beginners", "proxmox", "self-hosting", "essay"]
keywords = ["homelab", "home server", "proxmox", "self-hosting", "why homelab"]
description = "two years ago my blog lived on a rented VPS. then i killed the VPS — and discovered the difference between renting computers and owning them. this is that story, and why you should start your own lab."
showFullContent = false
readingTime = true
hideComments = false
+++

it was a tuesday night, almost 2am, and i had just locked myself out of my own network.

not metaphorically. i had been playing with VLANs on my firewall — one wrong rule, one click too confident — and suddenly my laptop couldn't reach anything, including the firewall itself. the girlfriend asleep in the next room, my phone's flashlight between my teeth, a cable plugged straight into the box to undo what i'd done. twenty minutes of pure, sweaty panic. and when the dashboard came back, i laughed out loud, alone in the dark.

that night taught me more about networking than a semester of lectures. and that, right there, is a homelab.

## renting computers vs owning them

for two years, my blog lived on a VPS — a virtual server rented from someone else's datacenter, running a plain apache server. it worked fine. i paid every month, i never thought about the hardware, and i learned almost nothing. when i finally killed that VPS, the blog died with it, and all i had left was a backup tarball gathering dust in my nextcloud. ([here's how the resurrection went](/posts/welcome-back/).)

renting taught me how to be a customer. owning taught me how things work.

a homelab is the opposite of a VPS: a server — or three — sitting in *your* home, running *your* services, breaking in *your* face at 2am. it's the difference between reading about swimming and getting thrown in the pool. the pool is cold, you swallow water, and you learn to swim fast.

## the night the ads died

my first real victory wasn't impressive on paper. i installed an ad blocker — pihole — as my home DNS server, in a docker container, in about thirty minutes. then i opened a news website and the page just... loaded. clean. silent. no popups, no autoplay video screaming about insurance.

i called my girlfriend over to show her. she stared at the screen, then at me, and said "cool" in the exact tone of someone tolerating a technical monologue. but i didn't care. every device in the house was suddenly faster, and *i* had done that, with a thirty-minute container on a machine in my closet. that feeling never really leaves you. it just scales up: first it's the ads, then it's your photos leaving google, then it's your entire digital life running on hardware you own.

## what it actually costs (less than your streaming subscriptions)

people imagine server racks and four-figure bills. forget that. the homelab community's best-kept open secret is that the ideal starter machine is a refurbished office mini PC — the kind companies throw out by the pallet. a Lenovo Tiny or Dell Micro costs around €100-150, draws less power than a light bulb at idle, and happily runs a dozen services. eric over at readthemanual, who's been doing this for twenty years, gives exactly this advice to every beginner, and [his breakdown of the three paths — buy, build, or rent](https://readthemanual.co.uk/getting-started-homelab-buy-build-rent/) is the most honest guide i've found.

if silence matters to you (it will, once the machine lives near your bedroom), the current darling is intel's N100: roughly 6 watts idle, whisper-quiet, about €150 new. people have measured it six ways to sunday — [it sips power like a raspberry pi and works like a real computer](https://www.bigiron.cc/guides/the-n100-n305-mini-pc-class-what-fits-and-what-does-not/). my whole starter setup costs less per year in electricity than two months of the streaming services i cancelled to pay for it. the math isn't even close.

so no, you don't need a rack. you need a small box, an evening, and permission to break things.

## the religion of the snapshot

here's the thing nobody tells you on day one: the homelab doesn't teach you technology. it teaches you *discipline disguised as technology*.

it starts with snapshots. proxmox — the free virtualization platform nearly everyone starts on — lets you photograph a machine's entire state in one click before you touch anything. the first time you nuke a VM and restore it in forty seconds, something clicks in your brain: fear leaves the room. and without fear, you experiment ten times more. that one habit, snapshot-before-not-after, is worth more than any tutorial.

then comes naming. then monitoring, because you discover things die silently all the time and you'd never know. then backups — real ones, restore-tested ones, because one day a disk *will* click its last click and you'll learn the difference between a backup and a rumor. each scar becomes a rule. my containers are named by VLAN and IP so i always know where anything lives. every service sits behind one reverse proxy with real encryption. nothing important runs unmonitored. none of this came from a book. all of it came from tuesday nights.

## why i'm writing this twice a week

i'm a computer science student in toulouse. i could learn this stuff in class, in theory, on slides. instead i run a two-node proxmox cluster, a firewall with four VLANs, my own git server, and a deployment pipeline that ships this very page from a git push. not because i need to — because every outage at 2am rewires my brain a little, and i want to keep the receipts.

so here's the deal with this series: twice a week, one article, each one about something real in my lab. we'll start where i started — one machine, one VM, trembling hands — and walk all the way down: containers, networks, firewalls, backups that actually restore, and the pipeline serving these words. every piece comes with the hands-on part, because reading about swimming, remember?

the pool is cold. the water's fine. snapshot first — and jump in.
