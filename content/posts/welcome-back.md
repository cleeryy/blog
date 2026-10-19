+++
title = "welcome back: the blog rises again, this time with gitops"
date = "2026-10-19T12:00:00Z"
author = "cleeryy"
authorTwitter = ""
cover = ""
tags = ["meta", "homelab", "hugo", "dokploy", "gitops"]
keywords = ["blog relaunch", "hugo", "dokploy", "gitops", "self-hosting"]
description = "my blog died with a VPS. it came back as a git repo with CI, container scans and automatic deploys — here's the story and what's next."
showFullContent = false
readingTime = true
hideComments = false
+++

## so... it's been a while

my old blog lived on a VPS as a plain apache server serving hugo output. it worked, until the day i killed the VPS. luckily, a backup survived in my nextcloud (`droplet-containers.tar.gz`, never underestimate a hoarder), and here we are: same content, brand new pipeline.

## what changed

- **before**: apache on a VPS, manual deploys, theme terminal, `cleeryy.com`.
- **after**: hugo in docker, **forgejo as primary git mirrored to github**, CI on every push (lint, multi-arch build, trivy scan, GHCR), and **dokploy** auto-deploying to my homelab behind caddy at `blog.cleeryy.cloud`.
- the theme is still terminal, but warmed up: the green accent is now the orange from my favicon (`#f08d49`), and the article list finally looks like a list instead of a wall of text.

## the road there (abridged)

restoring the backup was the easy part. the fun was everything around it: a CI pipeline with a trivy version that didn't exist, a missing release-drafter config, multi-arch builds needing QEMU+buildx, and a dokploy swarm service that refused to update until its update order was set to `stop-first`. classic homelab: nothing works the first time, everything teaches you something.

## what's next

this blog becomes my homelab journal. **twice a week**: one article about my infrastructure — what it is, why it's built that way, and a tutorial so you can build it too. we start gentle (what even is a homelab?) and go deep (VLANs, firewall rules, gitops, monitoring). no secrets spilled, just real setups and real configs.

new pages: [/homelab](/homelab) for the lab tour, [/uses](/uses) for the gear list.

welcome (back) aboard. 🔶
