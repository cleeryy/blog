+++
title = "docker in ten minutes: a process, and three boundaries"
date = "2026-10-30T06:54:43Z"
author = "cleeryy"
authorTwitter = ""
cover = ""
tags = ["homelab", "docker", "containers", "self-hosting"]
keywords = ["docker", "oci image spec", "containerd", "runc", "docker compose", "named volumes", "bind mounts", "restart policy", "rootless docker", "podman", "overlayfs", "image layers"]
description = "The ten-minute docker tutorial is accurate, and it stops one step too early. A measured look at what 'docker run' actually gives you, and the three boundaries — image/container, container/host, container/network — that decide whether the service is still there next week."
showFullContent = false
readingTime = true
hideComments = false
+++

*I ran the thing tutorials promise, on a box that already had the image, and timed it: four hundred milliseconds from nothing to a process that has started and exited. That is the honest size of "docker in ten minutes" — a process, walled off from the rest of the machine, in less time than it takes to read this paragraph. Everything after that line in the tutorial is labelled "done", and it is actually the start of the only question worth asking: which of the things you just created will still be there tomorrow?*

## what the ten minutes actually contain

On this host — Debian 13 on Proxmox, Docker Engine 29.9.2, Compose v5.6.1, the containerd snapshotter behind overlayfs — creating, starting and exiting a container from an image already on disk:

```text
docker run (create+start+exit): 433 ms
docker start 1:  368 ms
docker start 2:  551 ms
docker start 3:  342 ms
```

One run per line, so read those as magnitudes, not benchmarks. The number matters because of what it is being compared to: a VM boot is seconds to tens of seconds, because a VM brings up a kernel, an init, virtual hardware, a whole machine. A container brings up none of that. `docker run alpine:3.22 uname -r` prints `7.0.14-19-pve` — the host's kernel, because there is no other kernel to print.

So a container, precisely, is: one or more ordinary processes, in their own namespaces (pid, mount, network, uts, ipc, cgroup), with a root filesystem assembled from read-only layers plus one writable layer on top, and resource limits applied through cgroups. All of it enforced by the kernel you already run. That's the whole trick, and it's a good one: it is why the image is portable and the start is instant.

It's also why the ten minutes are spent on the easiest axis. Making a process run is nearly free. The three boundaries that decide whether it *keeps* running each have a default, and each default is tuned for a laptop where someone is watching. Here's what they are, and where I watched them fail on purpose.

## a side project that outgrew its company

Worth knowing what you're adopting, because "docker" now names a format, a company and a set of tools that have been diverging for a decade.

The company started in 2008 in Paris as dotCloud, a platform-as-a-service founded by Solomon Hykes, running customer applications in containers under the hood. Customers kept asking for that low-level piece directly, so it was open-sourced — and demoed as Docker in a lightning talk at PyCon in Santa Clara in March 2013, titled "the future of Linux containers". By Hykes's own account in a later interview, the company pivoted to Docker about two weeks after that talk, which nobody had planned as a launch.

Docker originally drove LXC, the older Linux container tool, from the outside. With 0.9 on 10 March 2014 it replaced that with libcontainer, a Go library talking to namespaces, cgroups, capabilities and AppArmor directly, and made it the default — the release notes are blunt about why: LXC differed across distributions, and abstracting it away "drastically reduces the number of moving parts". Docker 1.0 followed in June 2014.

Then the part that makes the ecosystem worth trusting. To avoid a format war with CoreOS's rkt, Docker and others founded the Open Container Initiative in June 2015 and donated the runtime core as runc. The OCI published the image-format and runtime specifications at 1.0 on 19 July 2017 ([announcement](https://opencontainers.org/posts/announcements/2017-07-17-open-container-initiative-oci-releases-v1-0-of-container-standards/)). containerd, the lifecycle daemon underneath, was donated to the CNCF on 29 March 2017 and [graduated on 28 February 2019](https://www.cncf.io/projects/containerd/).

The consequence arrived on 3 May 2022, when [Kubernetes 1.24 removed dockershim](https://kubernetes.io/blog/2022/05/03/kubernetes-1-24-release-announcement/): the orchestrator that made containers famous stopped needing Docker to run them. A Docker-built image is an OCI image, so it ran anyway, on containerd or CRI-O, untouched.

The company's arc was less happy, and it's the standard story of a standard winning while its author doesn't get to keep it. In November 2019 Docker [sold its enterprise business to Mirantis](https://www.infoworld.com/article/2269272/how-docker-broke-in-half.html) and recapitalised around developer tools; in August 2021 it [put Docker Desktop behind a paid subscription](https://www.infoworld.com/article/2268969/docker-desktop-is-no-longer-free-for-enterprise-users.html) for organisations above 250 employees or $10M revenue. The Engine stayed free and open. Which is the practical takeaway for a homelab: you can depend on the *format* and treat the *implementation* as replaceable — Docker, Podman, containerd with nerdctl, or LXC/Incus for system containers, all reading the same images. That is a rare, genuinely good outcome, and it's the reason the rest of this piece is about behaviour rather than brand.

## boundary one: the image is not the container

An image is an ordered collection of filesystem changes plus a configuration blob, content-addressed and immutable. `alpine:3.22` is one layer, 12.7 MB extracted (3.8 MB compressed). A three-line Dockerfile of mine produced three layers, the two `RUN` steps at 8.19 kB each.

The layer mechanics are worth one experiment, because they explain most of what follows. Two builds of that Dockerfile, differing only in the last line:

```text
#5 [2/3] RUN echo "layer two" > /second.txt
#5 CACHED
#6 [3/3] RUN echo "layer three, edited again" > /third.txt
#6 DONE 0.2s
```

The unchanged step is reused; only the changed one executes. And the two resulting images both report `12.8MB` disk usage and `3.8MB` content size — because they *share* the base layer and the cached step. Two images, one copy of alpine on disk. Which also means per-image disk numbers are a bad way to budget: nine images on this box occupy 2.1 GB together while their individual sizes don't add up to anything meaningful.

A container is that image plus a writable layer and runtime state. The writable layer is where the classic misunderstanding lives, and it has two halves that tutorials merge into one sentence ("containers are disposable").

First half: **a restart is not a reset.** I wrote a file into a running container, restarted it, and read the file back.

```text
docker run -d --name dt-live alpine:3.22 sleep 600
docker exec dt-live sh -c 'echo hello > /tmp/f'
docker restart dt-live
docker exec dt-live cat /tmp/f
hello
```

The writable layer survives restarts and stops. It is a disk, not a scratchpad.

Second half: **removal is a reset, and it is total.** Prune the stopped container and start a new one from the same image, and `/tmp/f` is simply not there. Nothing warns you, because from Docker's point of view both containers are correct: an image is a template, and a container is one instance of it that was deleted.

Put together, those two facts are the article's first real idea: the container is disposable, and your data's disposability is a *separate decision* — one you either make deliberately by choosing where the bytes go, or make by accident. A tutorial that says "and now you're done" never asks you to make it.

One more thing on this boundary: tags move, digests don't. `alpine:3.22` is a pointer that will be repointed; `alpine@sha256:2e0b81d6…` is the exact bytes I tested. In a homelab `latest` is how you get a surprise at two in the morning, delivered by a restart policy that faithfully restarts the new, broken version.

## boundary two: the container is not the host

The fix for the previous section is a mount, and there are two kinds with different personalities.

A **named volume** is a directory Docker manages under its own data root. My test: create the volume, write into it from a container, delete that container, start a fresh one with the same volume.

```text
docker volume create dtdata
docker run --name dtv1 -v dtdata:/data alpine:3.22 sh -c 'echo persisted > /data/note.txt'
docker container prune -f
docker run --name dtv2 -v dtdata:/data alpine:3.22 cat /data/note.txt
persisted
```

`docker volume inspect dtdata` puts it at `/var/lib/docker/volumes/dtdata/_data` — a plain directory on the host, owned by root, invisible to a container unless mounted. A **bind mount** skips the abstraction: `./site:/usr/share/nginx/html:ro` hands the container a path from your filesystem, read-only in this case, and the container serves whatever is there. My compose file below does exactly that, and `curl` returns `hello from a bind mount` — a file that never entered an image.

The rule I settled on: bind mounts for things a human edits (config, static content, compose files), named volumes for things a process writes (databases, uploads, application state). Bind mounts make backups obvious and permissions fiddly; volumes make permissions predictable and backups non-obvious, because your backup tool sees an opaque blob and `/var/lib/docker` is not a directory you should be rsyncing live.

Which brings the uncomfortable part of this boundary, the one the ten minutes never mentions. On this daemon:

```text
$ ls -l /var/run/docker.sock
srw-rw---- 1 root docker 0 /var/run/docker.sock
```

Group `docker` can talk to that socket, and anything that can talk to the socket can ask the daemon to run a container with the host's root filesystem mounted at `/`. Membership in `docker` is therefore root-equivalent, by design, and this is worth saying out loud because it's how "just add the user to the docker group" quietly becomes a privilege grant.

Second uncomfortable part: a container's root is the host's root, unless you change it. `docker info --format '{{json .SecurityOptions}}'` on this box returns:

```text
["name=seccomp,profile=builtin","name=cgroupns"]
```

No user namespace. So UID 0 inside a container is UID 0 outside it, restrained only by seccomp, capabilities and whatever the process can reach — not by an identity boundary. The OWASP Docker cheat sheet makes the point with a concrete historical case: Dirty COW, executed inside a well-isolated container, still produced root on a vulnerable host, because [containers share the host kernel](https://github.com/OWASP/CheatSheetSeries/blob/master/cheatsheets/Docker_Security_Cheat_Sheet.md). A container is an isolation mechanism, not a security boundary of the same class as a VM. For code you wrote and trust, that's fine. For someone else's image you just pulled, it's a decision to make knowingly.

The two mitigations are [userns-remap](https://docs.docker.com/engine/security/userns-remap/) (map container root to an unprivileged host UID range from `/etc/subuid` and `/etc/subgid`; the daemon itself stays root) and [rootless mode](https://docs.docker.com/engine/security/rootless/) (daemon and containers both inside a user namespace). Both need subordinate UID ranges configured. Neither is on by default, and both are cheaper to adopt on day one than after ten services depend on bind mounts whose ownership no longer lines up. That ordering is the whole argument for reading past the ten minutes: this is one of the few choices where the default is not wrong, exactly, but where changing it later costs real work.

An aside that surprised me, and that dates the documentation: on this daemon `docker inspect` no longer has a `GraphDriver` key at all — the storage stack is a containerd snapshotter, and the old graphdriver vocabulary in tutorials describes a layer of the system that has been replaced underneath it.

## boundary three: the container is not alone

The last boundary is the one that turns a process into a service, and it's where compose earns its place. This is the file I used:

```yaml
services:
  web:
    image: nginx:alpine
    container_name: dt-compose-web
    ports:
      - "8088:80"
    volumes:
      - ./site:/usr/share/nginx/html:ro
    environment:
      TZ: Europe/Paris
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1/health.txt"]
      interval: 10s
      timeout: 2s
      retries: 3
    restart: unless-stopped
```

Every line is a decision that the equivalent `docker run` would have made silently or not at all: which interface the port is published on, that the content mount is read-only, that the process has a timezone, what "alive" means, and what to do when the process exits. `docker compose up -d` gave me `Up 12 seconds (healthy)`, and the health path returned 200.

Then I did something careless and learned from it. I asked nginx to shut down gracefully from inside the container:

```text
docker exec dt-compose-web nginx -s quit
docker ps --format '{{.Names}} {{.Status}}'
dt-compose-web Up 2 seconds (health: starting)
```

It came *back*. `restart: unless-stopped` restarts on any exit it didn't cause itself — including exit code 0. That is correct behaviour and a genuinely useful property, but it draws a line that matters: a restart policy supervises a *process*, not a *service*. Docker knows nginx exited cleanly; it has no idea whether nginx was serving anything. The healthcheck is what knows the difference, and even then Docker only reports the verdict — it doesn't restart on unhealthy without something extra deciding to act on it.

The same section is where the tooling history shows up in your typing. Compose began as Fig, from a two-person startup called Orchard Labs, acquired by Docker in 2014 and renamed docker-compose — a Python program. Compose v2 was a Go rewrite shipped as a Docker CLI plugin, which is why the command lost its hyphen; v5, released in 2025, is [functionally identical to v2 with an official Go SDK](https://docs.docker.com/compose/intro/history/), and the Python-era v1 has since been retired. On this box you get `Docker Compose version v5.6.1` and `docker compose` with a space. If a tutorial says `docker-compose` with a hyphen, you're reading something written for a tool that no longer ships.

Networking, briefly, because it belongs to this boundary: compose puts services on a bridge network with its own subnet and embedded DNS, so `web` resolves `db` by name without any ports being published to the host. Publishing is a separate act — a DNAT rule on the host — and `"8088:80"` means *all* interfaces while `"127.0.0.1:8088:80"` means just the loopback. Two very different amounts of exposure, one character apart. On a machine with a reverse proxy in front, the loopback form is usually the one you want.

## the parts that deserve suspicion

Nothing above is an argument that Docker is wrong; it's an argument that its defaults are a starting point. The things I'd want a reader to hold sceptically:

**The daemon is a single privileged process.** One API, one attack surface, and an upgrade that restarts your containers unless `live-restore` is configured. Podman's answer is architectural: no daemon, a fork-exec model where each container is a child of the command that started it, rootless by default in practice, and systemd as the supervisor. It reached [v1.0 in January 2019](https://en.wikipedia.org/wiki/Podman) after a 2018 first release, and the CLI is close enough to Docker's that the migration is mostly muscle memory. The cost is that anything expecting a long-running API needs Podman's socket service, and rough edges appear exactly where a daemon was doing quiet work for you.

**The disk bill arrives later.** At the time of writing: 9 images, 3 active, 2.107 GB total with 1.141 GB reclaimable, plus 44 build-cache entries at 1.253 GB — accumulated over a handful of experiments and some ordinary image builds. Ten minutes of trying things leaves a gigabyte behind, and nothing prompts you to notice.

**"Container" covers two different products.** Docker and Podman run application containers: one process, an image, no init. LXC and Incus run system containers: a full userland, an init, a filesystem you can treat like a small machine. On Proxmox I use both, and choosing wrongly is the most common early mistake I see — a database with its own users, cron and package manager usually wants a system container or a VM, not an image. Docker earns its place for software that is *shipped* as an image and expects to be replaced rather than maintained.

Concretely, in this lab, Docker is not where state lives. It's where the *build* happens — this blog is a multi-stage Hugo image, compiled in a container and served by nginx — and where a couple of small stateless tools run because upstream only publishes images. The machines that hold data stay on Proxmox as VMs and LXC. That split isn't dogma; it's the boundary-two question ("where do the bytes live?") answered once, globally, instead of per service and by accident.

**Licensing, as an ecosystem signal.** Docker Desktop is paid for larger organisations. It doesn't affect a homelab running the Engine on Linux, but it explains the shape of the ecosystem: Podman exists partly because of it, and the OCI specifications exist so that the answer to "should I standardise on this company" is no.

## your first hour, done differently

Not a recipe — the decisions I'd front-load if I were starting over, because each is cheap now and awkward after the fact:

1. **Decide where state goes before the first write.** Named volume, or a host path you'll back up. Written in the compose file, not remembered.
2. **Pin the version.** A digest if the service matters, a minor tag otherwise. Reserve `latest` for things you actively enjoy debugging.
3. **Write `compose.yaml` on day one, even for one service.** It's the only artifact of the ten minutes that survives as documentation, because it encodes the flags.
4. **Choose restart policy and healthcheck deliberately, and know what each supervises.** Restart policy: whether the process exists. Healthcheck: whether it's useful. Docker reports the second and acts on the first.
5. **Check where you stand on namespaces.** `docker info --format '{{json .SecurityOptions}}'` — one line, and it tells you whether container root is host root.
6. **Back up what the container writes, and test the restore.** Filesystem snapshot of the host, or a `tar` through a throwaway container with the volume mounted. An untested restore is a hypothesis.

## the five-second version

The ten minutes are real: a process is running, a page is served, nothing needs to boot. What the ten minutes don't contain is the three answers that decide whether that is still true on Sunday morning — where the bytes live, who can reach the port, and what happens when the process exits at three in the morning and something faithfully brings it back.

Learn `docker run` in ten minutes. Then spend an hour on the boundaries, because the shortest-lived artifact in the entire stack is the `docker run` you typed, and the longest-lived one is the volume you forgot you'd need.

*Next in the foundations phase: one front door for all of it — how a reverse proxy routes by hostname and why TLS termination belongs there.*
