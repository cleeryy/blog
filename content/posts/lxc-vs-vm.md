+++
title = "containers share the kernel. that decides everything."
date = "2026-10-20T08:00:00Z"
author = "cleeryy"
authorTwitter = ""
cover = ""
tags = ["homelab", "proxmox", "virtualization", "lxc", "kvm"]
keywords = ["proxmox", "LXC", "KVM", "containers vs VMs", "unprivileged containers", "docker in LXC"]
description = "On Proxmox, containers and VMs aren't two flavors of the same thing: one shares the host kernel, the other brings its own. That single fact explains the security, compatibility, and migration trade-offs — and settles where Docker belongs."
showFullContent = false
readingTime = true
hideComments = false
+++

*Every Linux service in your lab fits in either a container or a virtual machine, and the wrong pick costs you in weird ways months later. The whole decision comes down to one fact: a container shares the host's kernel, a VM doesn't.*

## Two kinds of "separate machine"

Proxmox VE ships two virtualization technologies side by side — KVM for full virtual machines, LXC for system containers — managed through the same interface. The [project's feature page](https://www.proxmox.com/en/products/proxmox-virtual-environment/features) presents them as complementary, and they are, but "complementary" hides the asymmetry. A KVM guest boots its own kernel on virtualized hardware: virtual disk, virtual NIC, virtual everything. An LXC container boots no kernel at all. It runs as a set of isolated processes on the *host's* kernel, fenced in by Linux namespaces and cgroups.

That is the entire mental model, and everything practical falls out of it. Fast startup, near-zero memory overhead, hundreds of guests per host — all of that is just what "no second kernel" buys you. And every limitation of containers is the same fact viewed from the other side: there is only one kernel in the building, and it belongs to the host.

Containers earned that model over a long apprenticeship. In Proxmox's early years the container side was OpenVZ, a patched kernel doing isolation out-of-tree; when the necessary primitives — namespaces, cgroups — matured in mainline Linux, LXC replaced OpenVZ from Proxmox VE 4.0 onward, [as the project's own history records](https://www.proxmox.com/en/about/company-details/press-releases/proxmox-ve-turns-10). That lineage matters because it explains the design: LXC containers aren't a lightweight VM format, they're fenced-in host processes, and every behavior below follows from which side of that fence you're standing on.

This blog's stated position, from the [homelab overview](/posts/what-is-a-homelab/), is VMs "for the heavy and the risky" and containers "for the rest." What follows is the reasoning that makes that split more than a vibe.

## What kernel sharing costs you in isolation

Containers on Proxmox are unprivileged by default, and the mechanism is worth understanding because people routinely over- or under-trust it. In an unprivileged container, UID 0 — root inside the container — is mapped to an unprivileged user on the host. A process that escapes the container's filesystem view still lands as some random unprivileged UID, not as host root. On top of that, Proxmox confines containers with AppArmor profiles and seccomp filters that block the dangerous syscalls. The [pct manual](https://pve.proxmox.com/pve-docs/pct-plain.html) documents all of this plainly, and then adds the sentence that matters most: containers use the kernel of the host system, so the kernel is shared attack surface, and "in general, full virtual machines provide better isolation."

Read that twice. The UID mapping protects you against a large class of escapes, but every guest and the host run the same kernel code paths. A kernel vulnerability is a vulnerability in everyone's floor at once. A VM adds a hardware-virtualization boundary in between: an attacker who owns the guest kernel still has to cross the hypervisor to reach the host. That boundary is exactly what you're paying for with the extra memory and slower boot — not performance theater, but blast-radius control.

So the isolation question answers itself once phrased honestly: how bad is it if this guest turns hostile? A private DNS resolver used by three devices and a publicly reachable app running other people's code do not deserve the same boundary. Put the risky one behind the hardware line.

## Three things containers simply can't do

The kernel boundary also draws hard compatibility lines. A container cannot run Windows, BSD, or anything non-Linux — there is no second kernel to boot a foreign OS on. It cannot load its own kernel modules or run a different kernel version than the host. If your workload needs any of that — a Windows VM for the one proprietary tool, a test rig for a kernel module, an old appliance pinned to an ancient kernel — the decision is made before it starts. VMs only.

The second line is Docker, and it's the one that causes the most confusion because it *almost* works. Proxmox's own [FAQ](https://pve.proxmox.com/pve-docs/chapter-pve-faq.html) is explicit: LXC targets system virtualization (a whole OS in a container), Docker targets application containers (one app per container), and "it is not recommended to run docker directly on your Proxmox VE host. If you want to run application containers, for example, Docker images, it is best to run them inside a Proxmox QEMU VM." Running Docker *inside* an LXC container is possible but means punching the exact holes the defaults closed: `nesting=1` so the container can create its own namespaces, `keyctl=1` so the container runtime's keyring calls work — both documented as weakened confinement in the same manual. And the ground shifts under you: community reports describe Docker breaking inside unprivileged containers when newer runc versions started requiring syscalls the container's namespace setup can't grant, the kind of failure that reads as a permission error and traces back to an abstraction-layer mismatch. That fragility is structural, not a bug to wait out. Docker assumes it owns its namespaces; inside LXC, it rents them from a landlord with rules.

The third line is movement. The Proxmox container documentation notes that VMs carry "the ability to live-migrate, which otherwise isn't possible with containers" — a VM's state is self-contained enough to move between nodes while running; a container entangled with the host kernel is not. On a single node this never bites. On a cluster, the day you want to empty a node for maintenance, your VMs glide over and your containers get rebooted. Worth knowing before you place the service that must never go down.

## The decision, as three questions

Forget feature matrices. For each workload, ask in order:

**1. Does it need its own kernel?** Non-Linux OS, custom modules, Docker or Kubernetes inside — that's a VM. This question is binary and comes first because no preference overrides it.

**2. What happens if it's compromised?** Trusted internal Linux services — DNS, monitoring, a reverse proxy config you wrote yourself — sit comfortably in unprivileged containers. Anything internet-facing running complex code, anything executing untrusted input, anything whose breach would ruin your month — give it the hardware boundary. When in doubt between the two, the VM is the conservative answer, and conservative is a compliment in infrastructure.

**3. Does it need to move?** If you're on a cluster and the service must survive node maintenance without a reboot, that pushes toward a VM too.

Consider two hypothetical cases to see the questions work. A home DNS resolver, Linux-only, trusted code, queried only by your own LAN: container — shares nothing it needs to own, sips memory, snapshots like everything else. A demo web app you deployed so a friend can test it, running a framework with weekly CVEs, reachable from the internet: VM — foreign code, exposed surface, hardware boundary. Neither answer required benchmarking anything. The shape of the workload dictated the shape of the boundary.

Two hygiene rules cover the rest. Keep containers unprivileged and leave nesting off unless a specific workload demands it — defaults are the secure posture, and every flag you flip is isolation you're spending, so spend it deliberately. And keep one workload per guest either way: the density containers offer tempts people into stuffing five services into one, which recreates exactly the tangled-pet-server problem virtualization was supposed to kill.

## Density is a bonus, not a reason

Containers will fit an order of magnitude more guests per host. That's real — no second kernel, no virtualized hardware, just processes with fences. But density is the reward for workloads that already fit the container model, not an argument for squeezing in ones that don't. The homelab failure mode here is running fifteen containers to feel efficient while three of them run Docker-in-LXC behind privileged flags, saving 200 MB of RAM in exchange for the weakest isolation on the node.

The split that holds up, and the one this blog will keep using: containers for trusted Linux services where the shared kernel is irrelevant, VMs for everything carrying its own kernel needs, its own risk, or its own uptime requirements. One shared kernel, hardware boundaries where they count, and Docker in a VM like the documentation says. Boring, legible, and easy to reason about at 2 AM — which is when infrastructure decisions get graded.
