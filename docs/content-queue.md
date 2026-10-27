# Content queue — homelab series (2 articles/week, Tuesday & Friday)

Rules for the writing cron:
- Pick the FIRST unchecked `[ ]` topic, in order. Phases go simple → technical.
- Write the article in English, same voice as existing posts (lowercase casual, precise).
- Every article MUST have: the concept explained simply, WHY it matters in my lab,
  and a hands-on tutorial part with real commands/configs.
- NEVER publish secrets: no passwords, tokens, API keys, private keys, public IPs,
  exact firewall rules with real addresses. RFC1918 examples and principles are fine.
- Save to `content/posts/<slug>.md` with full front matter (title, date, author cleeryy,
  tags, keywords, description, showFullContent false, readingTime true).
- After pushing, flip the topic to `[x] YYYY-MM-DD`.
- Rigor over volume: exact versions/flags, tested commands, no invented output.

## Phase 1 — foundations (start here)

- [x] 2026-10-19 `welcome-back` — blog relaunch (written manually)
- [x] 2026-10-19 `what-is-a-homelab` — what a homelab is/ isn't, goals, budget tiers, my rules (everything as code, tested backups)
- [x] 2026-10-19 `proxmox-first-vm` — installing proxmox VE, first Linux VM, virtio drivers, snapshots before breaking things
- [x] 2026-10-20 `lxc-vs-vm` — containers vs VMs on proxmox, when to use which, my split in practice
- [x] 2026-10-23 `naming-things` — my ID=VLAN+IP convention, tags, why naming is infrastructure
- [x] 2026-10-27 `ssh-done-right` — keys only, ed25519, ssh config aliases, BatchMode for scripts
- [ ] `docker-in-10-minutes` — images vs containers, volumes, compose basics, first self-hosted app
- [ ] `reverse-proxy-explained` — why one front door: SNI routing, TLS termination, caddy vs nginx-proxy-manager vs traefik

## Phase 2 — network & OPNsense

- [ ] `vlans-at-home` — what VLANs solve, trunk vs access ports, my 4-VLAN layout (trusted/prod/mgmt/guest)
- [ ] `opnsense-first-rules` — default deny mindset, LAN out, guest isolation, reading the firewall log
- [ ] `dns-at-home` — technitium vs pihole vs unbound, local zones, why DNS is the real front door
- [ ] `dhcp-done-clean` — static leases for infra, dynamic pools for clients, documenting every address
- [ ] `wireguard-remote-access` — road-warrior VPN into the lab, one peer at a time, kill-switch thinking
- [ ] `reverse-proxy-caddy` — caddyfile anatomy, wildcard certs via DNS challenge, validate+reload ritual
- [ ] `cloudflare-tunnels-vs-open-ports` — exposing services: port-forward, tunnel, or VPN-only? threat model each
- [ ] `observing-traffic` — ntopng/ntop basics, what normal looks like so anomalies stand out

## Phase 3 — data & backups

- [ ] `backup-strategy-321` — 3-2-1 rule applied to a homelab, what I back up and what I don't
- [ ] `proxmox-backup-server` — PBS setup, datastores, prune/verify/GC schedules that actually run
- [ ] `untested-backup-is-a-lie` — restore test walkthrough: isolated restore, boot check, lessons
- [ ] `offsite-encrypted-rclone` — rclone crypt to cloud storage, cron + flock, never two syncs at once
- [ ] `nas-layout` — datasets, NFS vs SMB, what lives on spinning rust vs SSD
- [ ] `immich-photo-pipeline` — self-hosted google photos: backup flow, ML thumbs, storage math

## Phase 4 — identity & services

- [ ] `sso-at-home-authentik` — why SSO even at home, OIDC vs forward-auth, protecting caddy vhosts
- [ ] `forgejo-at-home` — self-hosted git, runners, why forgejo-primary + github-mirror
- [ ] `nextcloud-private-cloud` — what I sync, what I don't, webdav backups feeding the lab
- [ ] `media-stack-jellyfin` — jellyfin + sonarr/radarr/prowlarr/qbit: the *arr request flow explained
- [ ] `uptime-kuma-monitoring` — monitors that page me, status pages, alert fatigue avoidance
- [ ] `beszel-prometheus-grafana` — resource monitoring: what metrics actually predict failure

## Phase 5 — gitops & dokploy

- [ ] `from-push-to-prod` — my pipeline anatomy: commit → CI → GHCR → dokploy → caddy
- [ ] `hugo-in-docker` — multi-stage hugo+nginx builds, why static sites are perfect containers
- [ ] `github-actions-ci` — lint, multi-arch (QEMU/buildx), trivy scans, advisory vs blocking
- [ ] `swarm-stop-first` — the update-order bug that silently skipped deploys, start-first vs stop-first
- [ ] `dokploy-app-anatomy` — ports, envs, domains vs caddy upstreams, when traefik vs caddy
- [ ] `secrets-in-gitops` — env files, dokploy secrets, what never enters git (with horror stories)

## Phase 6 — going deeper

- [ ] `warpgate-bastion` — single SSH entrypoint, SSO + short-lived certs, the banner-filter trick
- [ ] `netbird-mesh-vpn` — tailnet for servers, when mesh beats hub-and-spoke
- [ ] `pbs-deep-dive` — chunking, dedup, verify jobs, sizing a datastore
- [ ] `opnsense-ha-thinking` — what breaks when the firewall dies, backup/restore of the firewall itself
- [ ] `incident-diary-502` — real post-mortem template: the checkmk-out-of-docker-network outage
- [ ] `hardening-checklist` — fail2ban/crowdsec, unattended upgrades, ssh hardening, audit cadence
- [ ] `power-and-noise` — the physical lab: UPS sizing, watts per service, spouse-acceptance-factor
- [ ] `year-one-retrospective` — costs, kWh, what I'd do differently, next year's roadmap

## Phase 7 — guest ideas (only after phase 6)

- [ ] `zigbee-home-automation` — home assistant, zigbee mesh, automations that survive internet loss
- [ ] `mail-server-why-not` — stalwart experiment: receiving mail at home, SPF/DKIM/DMARC pain
- [ ] `k8s-at-home-worth-it` — k3s vs swarm for one person, honest cost/benefit
