+++
title = "proxmox is installed. now break something."
date = "2026-10-19T15:55:00Z"
author = "cleeryy"
authorTwitter = ""
cover = ""
tags = ["homelab", "proxmox", "virtualization", "beginners"]
keywords = ["proxmox", "first VM", "virtio", "snapshots", "vzdump", "homelab"]
description = "The Proxmox installer takes fifteen minutes. The real setup starts after: why your first VM should be sacrificial, and the three habits that make everything else safe."
showFullContent = false
readingTime = true
hideComments = false
+++

*Installing Proxmox takes fifteen minutes and a USB stick. Becoming someone who trusts their infrastructure takes one sacrificial virtual machine and three habits. This is about all four.*

## The installer lies (kindly)

The [official Proxmox VE 9 installation guide](https://pve.proxmox.com/pve-docs-9-beta/chapter-pve-installation.html) walks you through partitioning, timezone, network, and packages, and then you're done — a web interface on port 8006, a blinking dashboard, and the distinct feeling of having accomplished something. You have. But the installer only built the stage. It didn't check the lighting, the trapdoors, or whether the building has sprinklers.

So before creating anything precious, verify the platform itself. Look at what the installer actually gave you: which disks hold the system, where VM disks will live, whether the network bridge matches your LAN. My own cluster runs Proxmox 9.2 as I write this, across two nodes — and the single most useful thing I know about it isn't a feature, it's the layout: system here, VM storage there, backups somewhere else entirely. Draw that map for your one node before you need it. It takes ten minutes and pays off for years.

One honest footnote for the impatient: yes, the free version shows a subscription notice, and yes, half the internet will tell you to silence it on day one. Leave it. You have real work to do first, and cosmetic surgery on a fresh install is procrastination wearing a trench coat.

## Eighteen years of boring excellence

Proxmox is older than you probably think, and that age is the point. The company behind it, Proxmox Server Solutions, was founded in Vienna in 2005 by two brothers, Martin and Dietmar Maurer; the first public version of Proxmox VE arrived in April 2008, unifying KVM virtual machines and OpenVZ containers under one web interface — the first platform to do both at once, [by their own documented account](https://www.proxmox.com/en/about/company-details/press-releases/proxmox-ve-turns-10). Containers later moved from OpenVZ to LXC, the license stayed AGPL, the base stayed Debian, and the releases kept coming: eighteen years of them. My cluster runs version 9.2 today. That continuity matters more than any feature list, because infrastructure software is ultimately a bet on who will still be maintaining it in a decade.

What it is today, concretely: KVM for full machines, LXC for lightweight containers, ZFS and Ceph for storage, clustering with live migration, and a backup server that deduplicates — all behind one web UI, all free, with paid subscriptions existing only for enterprise support and faster update channels. No feature is held hostage; the free version is the whole version, plus a nag screen. That model explains its position in 2026: when Broadcom's VMware licensing pushed whole fleets to look elsewhere, Proxmox was standing there with fifteen years of releases and an import wizard, and became the default answer. Its serious open-source rival is XCP-ng — Xen-based, managed through the genuinely nice Xen Orchestra, arguably cleaner at fleet scale — while old ESXi free simply ceased to be viable. Different tools, different centers of gravity; for one person with one to three machines, the integrated-everything design wins on the shortest path to running.

Honest weaknesses, because choosing blind is how you end up migrating twice. GPU passthrough works but fights you — not a first-month project. The network UI occasionally disagrees with the underlying Linux state, and then you're reading config files anyway. Major upgrades can bite, so you time them instead of clicking through. Docker has no native seat: it lives inside a VM or an LXC, a guest in someone else's house. And the documentation, while comprehensive, assumes you're comfortable in a terminal; absolute beginners will feel the gap. None of this disqualifies it — [independent reviewers](https://topinsight.co/storage-homelab/proxmox-ve-review/) land in the same place — but knowing the sharp edges beforehand is what separates a choice from a gamble.

## Your first VM is a crash-test dummy

Here is the liberating reframe: your first virtual machine has exactly one job, and it isn't hosting anything. Its job is to prove the platform works — network, storage, console, backups — and then to die. Give it a silly name. induplicate it later without grief. Everything precious comes second.

The creation itself is a guided tour of the concepts that matter. Upload a Debian net installer ISO to your local storage, click Create VM, and read every tab of the wizard slowly, because each one teaches vocabulary you'll use forever. The OS tab asks what guest you're installing — the hypervisor tunes its emulation from your answer. The System tab offers machine types and firmware; the defaults are fine, and "fine, defaults for now" is a legitimate engineering decision when the machine is disposable. The Disks tab is where you meet your first consequential choice: VirtIO SCSI as the controller, a modest disk on your VM storage. The CPU and Memory tabs are sliders you'll revisit a hundred times. And the Network tab attaches a VirtIO network card to your bridge — VirtIO being the recurring theme: paravirtualized drivers that let guests talk to the hypervisor efficiently instead of pretending to own hardware from 2006.

(Windows guests complicate this with a second ISO of VirtIO drivers and a detour through driver loading mid-install — documented, doable, and absolutely not your day-one project. Start Linux. Your crash-test dummy has no opinions about operating systems.)

Boot it, finish the installer, log in. Congratulations: you have a computer inside your computer. Now the real lesson begins, and it has three parts.

## Three habits before anything precious

First, install the guest agent and take a snapshot — in that order. The QEMU guest agent lets the host coordinate cleanly with the guest (proper shutdowns, frozen filesystems during snapshots), and the snapshot itself is a photograph of the entire machine you can return to in seconds. This is the habit from the previous article made concrete: snapshot now, while everything is clean and boring, so "return to boring" is always one click away.

Second, back it up and restore it somewhere else. Proxmox ships `vzdump` for backups; run one, then restore it under a *different* VM ID and boot the copy. This single exercise verifies your storage, your backup target, your restore procedure, and your understanding, all at once — which is precisely why [experienced guides recommend it](https://vm.fyi/en/docs/guides/proxmox-ve-9-getting-started) before any production VM exists. If the restore fails, you have learned something invaluable on a machine nobody misses. That is the whole point of the dummy.

Third, internalize the sentence that governs everything after: snapshots are not backups. A snapshot lives on the same storage as the machine; it protects against your mistakes, not against dead disks. As the same guide stresses, snapshots cover short-term rollback — host failure or pool loss still requires off-host backups. Tattoo it wherever you keep important sentences. We'll build the real backup story later in this series; for now, knowing the difference puts you ahead of most beginners.

## What "done" looks like

You're finished with this stage when you can answer three questions with yes. Can you delete your first VM without flinching? Can you rebuild it from memory in ten minutes? And do you know, without checking, where its disk lived and where its backup went? Affirmative on all three means the platform is verified, the vocabulary is yours, and the fear is gone — which was the actual assignment all along.

A last note on naming, because future-you will thank present-you: decide on a VM ID scheme now, before you have eleven machines named `test`, `test2`, and `test-final-v2`. Mine encodes location — the ID tells me where the machine lives on the network — and six months later that decision still pays rent every single day. Any consistent scheme works. "Consistent" is doing all the work in that sentence.

Next in the series: containers versus virtual machines — what LXC actually is, when it beats a full VM, and how the two split the work in a real lab.

## Sources

- Proxmox VE, [Installing Proxmox VE](https://pve.proxmox.com/pve-docs-9-beta/chapter-pve-installation.html) — official PVE 9 installation chapter (ISO method, setup contents).
- [Proxmox VE 9 Getting Started](https://vm.fyi/en/docs/guides/proxmox-ve-9-getting-started) — first-VM-as-verification, immediate backup-and-restore-to-new-ID, snapshots-are-not-backups distinction.
- Proxmox Wiki, [Windows VirtIO Drivers](https://pve.proxmox.com/wiki/Windows_VirtIO_Drivers) — virtio-win ISO and guest tools installation.
- Vormox, [Install Windows Server 2025 on Proxmox VE](https://vormox.com/blog/how-to-install-windows-server-2025-on-proxmox-ve-step-by-step-guide-for-beginners) — VirtIO SCSI single, q35/OVMF choices, snapshot-after-drivers practice.
- Proxmox Server Solutions, [Proxmox VE turns 10](https://www.proxmox.com/en/about/company-details/press-releases/proxmox-ve-turns-10) — company history (2005 Vienna, VE 0.9 in April 2008, KVM+OpenVZ then LXC, AGPL).
- TopInsight, [Proxmox VE in 2025: the default homelab hypervisor, reviewed honestly](https://topinsight.co/storage-homelab/proxmox-ve-review/) — strengths and honest weaknesses (passthrough, network UI, upgrades, Docker, docs).
