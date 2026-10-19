+++
date = '2026-10-19T00:00:00Z'
draft = false
title = 'homelab'
description = 'tour of my homelab: proxmox cluster, OPNsense firewall, VLAN segmentation, Caddy, Dokploy and tested backups.'
+++

## the idea

my homelab is where i learn by breaking things (ethically, and with snapshots). everything here serves a purpose: host my own services, understand real networks, and practice the same discipline i'd apply in production — monitoring, backups, and infrastructure as code.

## compute

- **proxmox VE cluster** (2 nodes): LXC containers for light services, a few VMs for the heavy stuff (firewall, NAS-adjacent workloads).
- naming convention keeps things sane: container IDs map to their VLAN and IP, so i always know where something lives.

## network

- **OPNsense** as the firewall/router: one box, many VLANs — trusted LAN, production services, management, guests.
- each VLAN has a job and firewall rules to match. inter-VLAN traffic is explicit, not accidental.
- **technitium DNS** internally, **caddy** as the single front door with automatic wildcard certificates (DNS challenge).

## apps & gitops

- **dokploy** for app deployments straight from git: push to `master`, CI builds the image, the container updates itself.
- docker swarm under the hood, with `stop-first` update order so redeploys never fight over ports.
- **forgejo** at home as primary git, mirrored to github.

## data & backups

- NAS for bulk storage (media, ISOs, archives).
- **proxmox backup server** nightly, plus an encrypted offsite copy.
- rule: restores get tested. an untested backup is just wishful thinking.

## what i write about

twice a week i publish a homelab article here — starting simple (concepts, first VM) and going deeper (VLANs, firewall rules, gitops, monitoring). each one comes with a hands-on tutorial. browse [/posts](/posts) or follow the RSS feed.
