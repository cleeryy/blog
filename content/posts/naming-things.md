+++
title = "read the ID, know the address. naming as infrastructure."
date = "2026-10-23T08:00:00Z"
author = "cleeryy"
authorTwitter = ""
cover = ""
tags = ["homelab", "proxmox", "naming", "documentation"]
keywords = ["proxmox", "naming convention", "VMID", "proxmox tags", "homelab documentation", "RFC 1178", "pets vs cattle"]
description = "Every alert, log line, and firewall rule in a homelab arrives as a name. This lab encodes VLAN and IP directly into each guest's Proxmox ID, mirrors the address in tags, and keeps hostnames functional — so the name itself answers where a machine lives and how to reach it."
showFullContent = false
readingTime = true
hideComments = false
+++

*Fifty guests in, a homelab stops being something you remember and becomes something you read. Every alert, every log line, every firewall entry arrives as a name — and at 2 AM, the difference between a name you can decode and a name you have to look up is the difference between a five-minute fix and a forty-minute treasure hunt. This is the naming scheme this lab runs on, and why it earns its keep.*

## Every alert arrives as a name

Think about what actually reaches you when something breaks. Not a topology diagram — a string. A backup job reports `lxc/578 failed`. The firewall log shows a blocked packet from `10.1.20.41`. Uptime Kuma pages you about `caddy`. Each of those strings is a lookup task handed to a tired human: which machine is that, where does it live, how do I reach it?

Naming is the cheapest monitoring you have because it shortens every one of those lookups to zero. A name that encodes location and address turns the alert itself into the answer. A name that doesn't is decoration — pleasant in the dashboard, useless in the incident.

This is an old observation wearing new clothes. Back in 1990, Don Libes wrote [RFC 1178, "Choosing a Name for Your Computer"](https://datatracker.ietf.org/doc/rfc1178/), a gently exasperated guide to not naming machines after things that confuse everyone in conversation — project names that get reused, cute misspellings nobody can spell back, words already overloaded in context. The technology changed; the failure mode didn't. And two decades later the industry landed on the [pets-vs-cattle distinction](https://www.compiler.today/devops/pets-vs-cattle-comprehensive-guide) — Bill Baker's phrase, popularized by Randy Bias around 2012 — arguing that infrastructure at scale should be numbered and replaceable, not hand-raised and unique.

A homelab sits awkwardly between those two ideas, and that's exactly why naming matters more here, not less. You don't have fleet automation numbering things for you, but you also can't afford to hand-tend fifty pets with whimsical names. The workable middle: give every guest a functional human name *and* a machine-decodable identity. Pets with cattle ear-tags. This lab's version of that is three layers that each answer a different question: the numeric ID says *where it lives*, the tags say *how to reach it*, the hostname says *what it does*.

## One ID, two facts

In Proxmox, every guest has a numeric ID — the VMID — and it has to be unique cluster-wide. Most labs treat it as an auto-incremented afterthought: 100, 101, 102, whatever the "next ID" button suggests. This lab treats it as an address encoding instead: **the first digit is the VLAN, the rest is the last octet of the IP**.

| First digit | VLAN | Subnet | Role |
|---|---|---|---|
| 1 | LAN | 192.168.1.x | legacy LAN, dual-homed guests |
| 2 | prod | 10.1.20.x | services |
| 5 | mgmt | 10.1.50.x | infrastructure |
| 6 | test | 10.1.60.x | experiments |

So container 578 *is* 10.1.50.78 (the Proxmox Backup Server, on the mgmt VLAN). Container 553 *is* 10.1.50.53 (the DNS server). Container 205 *is* 10.1.20.5. Container 125 *is* 10.1.20.41 — the agent host this very blog pipeline runs from, sitting exactly where its number says. Four-digit IDs work the same way with a leading zero: 2010 is 10.1.20.10, the reverse proxy.

Read that back in incident terms. The backup report says `lxc/578 failed` and you already know: mgmt VLAN, .78, that's the backup server, SSH is one alias away. No dashboard, no spreadsheet, no memory required. The ID is doing documentation work on every screen it appears on — backup job lists, replication status, storage views, alert strings — because Proxmox prints the VMID *everywhere*.

There is a second, quieter payoff: the scheme makes conflicts visible before they happen. If the next free IP on the mgmt VLAN is .79, the next container ID is 579, and two admins (or one admin six months apart) can't accidentally pick the same address through different paths. The numbering *is* the allocation ledger, as long as you respect it when creating guests.

## Tags: the address, machine-readable

IDs encode the primary address, but some guests have more than one. The reverse proxy lives on both LAN and prod. The bastion entrypoint straddles networks by design. One number can't say all of that, so the second layer carries it: **Proxmox tags repeat the IP in short form**, and multi-homed guests list every address.

Container 222, the SSH bastion, carries `1.206;20.22` — 192.168.1.206 *and* 10.1.20.22. Container 2010, the reverse proxy, carries `1.205;20.10`. Single-homed guests carry one: `50.78` on the backup server, `50.53` on DNS, `50.66` and `50.67` on the monitoring pair. The convention is last-two-octets shorthand, semicolon-separated, and it shows up right next to the name in the Proxmox tree — the cluster's own UI becomes an address list with no extra tooling.

Tags do two more jobs beyond readability. First, they're searchable and filterable in the Proxmox UI, so "show me everything on .20.x" is a filter string, not a spreadsheet exercise. Second, they act as the backstop for guests that predate the scheme. A handful of early containers were created before the convention existed and their IDs don't decode cleanly — for those, the tag is the source of truth, and the mismatch itself is a signal: *this one is legacy, treat its addressing as verified-by-tag, not derived-from-ID*. A scheme that marks its own exceptions is more trustworthy than one that pretends to have none.

## Hostnames are for humans

The third layer is the actual name — `pbs`, `caddy`, `authentik`, `technitium`, `grafana` — and the rule is boring on purpose: **short, lowercase, functional**. What it does, not what it is. Nobody at 2 AM benefits from knowing a container is called `zeus`; everybody benefits from `prometheus-pve-exporter`.

RFC 1178's thirty-five-year-old advice holds up remarkably well here: real words over random strings (you have to remember and retype these), no cute spellings, all lowercase, nothing that overloads a term already in use. The one piece worth updating for a homelab: theme names — planets, philosophers, cheeses — are fun for three machines and a liability at thirty, because they force every lookup through memory. Functional names scale because they compose with the other two layers: `caddy / 2010 / 20.10` tells you what, where, and how in under twenty characters.

## The provisioning ritual

Convention without a ritual is a wish. Here is the part you can steal directly — the checklist for every new guest, which takes about a minute and pays off forever:

**1. Pick the VLAN first, not the software.** Where does this workload belong — mgmt, prod, LAN, test? That decision is the first digit, and making it explicit forces the segmentation thinking this series keeps coming back to. (VLANs get their own article soon; for now: infrastructure on mgmt, services on prod.)

**2. Take the next free last-octet on that VLAN.** Check the existing IDs with that leading digit — `pct list` or one glance at the Proxmox tree sorted by ID shows the gaps. The ID and the IP are chosen in the same breath: container 582 *will be* 10.1.50.82.

**3. Create with all three layers at once.** Proxmox lets you set hostname and tags at creation, so there is never a "temporary" unnamed guest:

```bash
pct create 582 local:vztmpl/<debian-template>.tar.zst \
  --hostname grafana-test \
  --tags 50.82 \
  --net0 name=eth0,bridge=vmbr0,ip=10.1.50.82/24,gw=10.1.50.1
```

ID, hostname, tag, address — consistent from birth, in one command. For a VM the same idea applies with `qm create 582 --name grafana-test --tags 50.82`.

**4. Record the static lease the same day.** If the VLAN uses DHCP with static leases (prod does here; infrastructure is static), add the MAC-to-IP mapping now, not "later". Later is where mystery addresses come from, and the DHCP article in this series will show the full lease hygiene.

**5. Verify decodability, not just reachability.** After first boot, the smoke test is: ping it, SSH in — and then check that a stranger reading `582 / grafana-test / 50.82` could find it without asking you. If any layer disagrees with the others, fix it now, while renumbering costs nothing.

## Where the scheme bends

Honesty requires the failure modes. Four-digit IDs with leading zeros (2010 → .10) work but look odd next to three-digit neighbors, and some tooling sorts them unexpectedly — cosmetic, but real. Desktop and school VMs (the `esgi-*` range, the big `10001` desktop) live outside the scheme entirely because their addresses belong to someone else's network logic; tags cover them, and that's fine. Multi-homed guests need tag discipline since the ID only carries one address. And Proxmox IDs are effectively immutable — changing one means backup, destroy, restore under a new ID — so a misnumbered guest stays misnumbered until a maintenance window says otherwise. That's not an argument against the scheme; it's the reason the creation ritual matters more than the correction path.

The deeper limitation is philosophical and worth stating plainly: this is *my* lab's encoding, fitted to *my* four VLANs. The transferable part isn't "first digit equals VLAN" — it's the principle that **every identifier in the system should answer a question without a lookup**. Your lab might encode environment and role instead of network, or use DNS search domains as the human layer. Steal the property, not the digits.

## Names are infrastructure

Back to the 2 AM test. Something pages. The string says `lxc/553`. You know before touching a keyboard: mgmt VLAN, .53, that's DNS, and if DNS is down half the lab looks broken while being fine. That first correct hypothesis — formed in seconds, from the name alone — is what the whole scheme is for. Not aesthetics, not tidiness points. Faster correct hypotheses, fewer wrong ones, every single incident, for the price of one minute of discipline at creation time.

Naming doesn't replace monitoring, documentation, or diagrams. It makes all three faster to use, because every one of them is indexed by names. Treat the namespace as load-bearing and it starts carrying load.

*Next in the foundations phase: keys only — SSH done right, from ed25519 to the aliases and flags that make scripts non-interactive.*
