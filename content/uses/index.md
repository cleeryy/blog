+++
date = '2026-10-19T00:00:00Z'
draft = false
title = 'uses'
description = 'hardware, software and services i use daily: homelab, dev setup and everyday tools.'
+++

## hardware

- **homelab**: proxmox cluster (2 nodes), managed switch + VLANs, OPNsense firewall, a couple of mini-PCs and a NAS for bulk storage.
- **daily driver**: laptop + external monitor, mechanical keyboard. nothing exotic, reliability first.
- **network**: segmented LAN (trusted, prod, mgmt, guest), WireGuard/NetBird for remote access.

## software I run

- **blog**: hugo + docker, deployed via dokploy with CI (build, trivy scan, GHCR).
- **git**: forgejo at home (primary), mirrored to github.
- **reverse proxy**: caddy with DNS-challenge wildcard certs.
- **backups**: proxmox backup server + encrypted offsite copy. a backup you never tested is not a backup.
- **media**: jellyfin + the *arr stack.
- **dev**: vscode + terminal, docker for everything shippable.

## services

- DNS filtering at home, SSO via authentik where it matters, uptime monitoring with uptime kuma.

this page evolves with the lab — see [/homelab](/homelab) for the full tour.
