+++
title = "one wire, seven networks: what a vlan actually isolates"
date = "2026-11-06T06:50:00Z"
author = "cleeryy"
authorTwitter = ""
cover = ""
tags = ["homelab", "networking", "vlan", "802.1q", "opnsense", "proxmox"]
keywords = ["vlan", "ieee 802.1q", "vlan tag", "trunk port", "access port", "pvid", "native vlan", "vlan hopping", "double tagging", "router on a stick", "proxmox vlan aware bridge", "opnsense vlan", "linux bridge vlan filtering", "network segmentation"]
description = "A VLAN is a four-byte label inserted between two ports that agreed to care about it — not a wall. Measured on my own trunk: the same ICMP echo request is 98 bytes untagged on the guest's port and 102 bytes tagged on the wire to the firewall, with the tag changing from 20 to 50 in between. What segmentation buys, what it costs, and the rules that decide whether it exists at all."
showFullContent = false
readingTime = true
hideComments = false
+++

*Seven VLANs run on one cable in my rack. Getting there took three days of re-addressing, one storage box that refused to move, and a firewall rule I only found while writing this — which is the most useful thing the exercise taught me about the four-byte tag everyone treats as a security feature.*

## a flat network is a promise you cannot keep

Plug everything into one switch and you get one broadcast domain. Every frame whose destination MAC the switch has not learned is flooded to every port in that network. Every ARP request goes to every host. One DHCP scope hands out one range, and every device can open a connection to every other device, because at layer two there is no "other".

For a first homelab that is not a problem, it is a feature: nothing to configure, nothing to break. It stops being fine the moment you want to write down a sentence like *the guest's phone must reach the internet and nothing else*, or *the machine I browse the web on must not reach the backup server*. Neither sentence is about bandwidth. Both are policy, and policy needs a boundary to attach to. A flat network has none — you would have to configure the refusal on each host, and then again on the next host, and then remember it after reinstalling one of them.

That was my trigger: not performance, not broadcast noise, just the realisation that I had no place to write "no". The VLAN was the place.

## the tag is four bytes, and it authenticates nothing

The idea is older than the standard. In the early 1990s vendors were already multiplexing several logical networks over one physical link, each with its own encapsulation: Cisco's Inter-Switch Link wrapped the entire original frame in a 26-byte header plus a 4-byte trailer and topped out around a thousand VLANs; 3Com had its own Virtual LAN Trunk. Both were proprietary, which is exactly the problem a standards body exists to solve — and the IEEE 802.1 working group solved it by choosing *internal* tagging instead of encapsulation, so that a tagged frame stays an Ethernet frame that ordinary hardware can carry.

[IEEE 802.1Q-1998](https://standards.ieee.org/ieee/802.1Q/1039/) was board-approved on 8 December 1998 and published on 8 March 1999; the 2005 revision replaced it, 802.1ad later added a second tag for provider networks — the "QinQ" stacking that lets an operator carry a customer's tags inside its own — and the current revision, 802.1Q-2022, is also published as ISO/IEC 8802-1Q. Twenty-eight years of amendments later, the four bytes at the heart of it have not moved.

The frame format is where most of the confusion dies. 802.1Q inserts 32 bits between the source MAC address and the EtherType field:

```text
16 bits        3 bits        1 bit        12 bits
TPID = 0x8100  PCP           DEI          VID
```

The TPID is the "this is a tagged frame" marker. The priority code point is three bits of 802.1p class-of-service, the drop-eligible indicator is one bit of congestion hinting, and the VLAN identifier is twelve bits. Twelve bits give 4096 values, of which 0 and 4095 are reserved, so **1 to 4094 are usable** — which is why switches quote "up to 4096 VLANs" and everyone repeats a number nobody can actually assign. The maximum frame size grows from 1518 to 1522 bytes, and the FCS is recomputed because the frame really did change.

Nothing in those four bytes is authenticated. Nothing is encrypted. There is no key, no handshake, no notion of who is allowed to claim which identifier. A port that accepts tagged frames accepts whatever label arrives on it. Everything people mean by "VLAN security" lives outside the tag: in which ports are trunks, which VLAN is native, and what the router does with a packet once the tag has been stripped.

Worth saying what came after, too, because the ceiling is real. At data-centre scale the answer to "4094 segments is not enough, and spanning tree does not like any of this" was not a better tag but an overlay — VXLAN puts the identifier in a UDP-encapsulated header with 24 bits of it, which buys sixteen million segments and a routed fabric underneath. None of that changes anything in a house. The tag survived because the problem it solves at layer two — one wire, several networks, no per-device configuration — has not changed since 1998.

## access and trunk are two promises, not two protocols

It is the same standard behaving differently at each end, and the difference is best read from the bridge's own table rather than from a diagram. On the Proxmox node (9.2.20, kernel 7.0.14), `bridge vlan show` prints this, abbreviated:

```text
port              vlan-id
eno3              1 PVID Egress Untagged
eno4              1 PVID Egress Untagged
                  2
                  ...
                  4094
veth125i0         20 PVID Egress Untagged
```

Three lines explain the whole model. `eno3` is the uplink to the box that provides internet: one port, one untagged network, no VLAN awareness needed. `eno4` is the trunk — to the second node and to the firewall VM — carrying 1 to 4094, with VLAN 1 untagged as the native one. `veth125i0` is a single container's virtual NIC, and it is an access port in VLAN 20: **PVID 20** means everything arriving untagged is treated as VLAN 20, **Egress Untagged** means everything leaving VLAN 20 towards that port has its tag removed first.

An access port is therefore a promise made on the device's behalf: *you will never see a tag, and I will never let you leave your network*. The device does not need to know VLANs exist. That is why it works with a printer.

The bridge is the switch and Proxmox is the thing that writes its port table, which is why a guest's NIC gets a `tag` field in the GUI. Under the hood it is one option:

```text
qm set 125 -net0 virtio,bridge=vmbr1,tag=20
```

The guest receives a plain Ethernet card and knows nothing. There is also `trunks=<vlanid;...>` if you want a guest to receive the tagged trunk itself and do its own VLAN configuration — legitimate for a virtual router, and a way to lose the guarantee that the guest stays in the box you put it in.

And the host needs its own way in, one that does not depend on a guest being up. On pve3 that is a VLAN interface stacked on the bridge:

```text
8: vlan50@vmbr1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 ...
    vlan protocol 802.1Q id 50 <REORDER_HDR>
```

declared the boring way in `/etc/network/interfaces`:

```text
auto vmbr1
iface vmbr1 inet manual
        bridge-ports eno4
        bridge-stp off
        bridge-fd 0
        bridge-vlan-aware yes
        bridge-vids 2-4094

auto vlan50
iface vlan50 inet static
        address 10.1.50.103/24
        vlan-raw-device vmbr1
```

Two details worth pausing on. `bridge-vids 2-4094` means "accept anything", which is convenient and also means a typo in a VLAN number fails silently somewhere far away; enumerating only the VLANs you actually use turns that typo into a dropped frame at the port you are looking at. And none of this is ancient machinery: VLAN filtering in the Linux bridge was merged in February 2013 by Vlad Yasevich at Red Hat and landed in kernel 3.8, as [the patch series shows](https://lwn.net/Articles/538877/). Before that, a "VLAN-aware bridge" on Linux meant one bridge interface per VLAN, and a reboot to create one.

## the tag exists for two centimetres of cable

Here is the part I wanted to see rather than read. A container on the production network pings the DNS server on the management network, and I capture the same packet at both ends: on the container's virtual NIC, and on the interface the firewall VM is plugged into.

```text
-- on the access port (veth125i0)
08:01:37.258127 bc:24:11:dc:cc:19 > bc:24:11:44:c2:5c, ethertype IPv4 (0x0800), length 98:
    10.1.20.41 > 10.1.50.53: ICMP echo request, id 16868, seq 1, length 64

-- on the trunk to the firewall (tap503i1)
08:01:31.137388 bc:24:11:dc:cc:19 > bc:24:11:44:c2:5c, ethertype 802.1Q (0x8100), length 102:
    vlan 20, p 0, ethertype IPv4 (0x0800), 10.1.20.41 > 10.1.50.53: ICMP echo request
08:01:31.137616 bc:24:11:44:c2:5c > bc:24:11:80:73:17, ethertype 802.1Q (0x8100), length 102:
    vlan 50, p 0, ethertype IPv4 (0x0800), 10.1.20.41 > 10.1.50.53: ICMP echo request
08:01:31.137659 bc:24:11:80:73:17 > bc:24:11:44:c2:5c, ethertype 802.1Q (0x8100), length 102:
    vlan 50, p 0, ethertype IPv4 (0x0800), 10.1.50.53 > 10.1.20.41: ICMP echo reply
```

Read the lengths: 98 bytes untagged, 102 bytes with the tag. Four bytes, exactly, which is the whole overhead the standard adds. Read the tags: the request leaves the container's port carrying 20, and the same ICMP exchange appears one line later carrying 50 towards the destination. The firewall is not forwarding the frame — it is routing it: it strips the tag, looks up the destination address, builds a new frame with a new destination MAC and a decremented TTL, and tags it for the outgoing network.

The tag, in other words, is a property of a *segment*, not of a packet. It exists between the bridge and the router because those two ports agreed to care; it is created when the frame enters that segment and destroyed when it leaves. The container and the DNS server have never seen one.

There is a second detail in those lines that took me a while to notice: every frame that involves the firewall carries the same MAC, `bc:24:11:44:c2:5c`, whichever VLAN it is on. That is the VM's parent NIC, and FreeBSD's VLAN interfaces inherit it rather than burning an address each. It is legal, normal, and it quietly means that any firewall policy written against MAC addresses on this box is meaningless.

Three consequences follow, and they organise everything else.

**One VLAN is one interface, one subnet, one scope, one rule set.** The tag itself gives you nothing until something terminates it: on my network that something is OPNsense with an interface per VLAN, each with an address, a DHCP range, a DNS story, and a firewall policy. A VLAN without a router interface is an island with no gateway — which is occasionally exactly what you want, and usually a mistake you discover at 23:00. And a VLAN is not a synonym for a subnet: one VLAN can carry several subnets, and one subnet can leak across several VLANs, which is how a network ends up with two halves that can reach each other but cannot ARP.

**A "router on a stick" carries every inter-VLAN flow twice.** All seven VLANs reach each other through one 1 Gbit/s link to the firewall VM, so a transfer between two networks uses that link in both directions. It is fine at homelab scale and it is a hard ceiling: the moment inter-VLAN traffic matters, the topology is the limit, not the CPU.

**The router is the only thing connecting them, so it is also the only thing that can disconnect them.** If that VM is down, my seven VLANs become seven isolated islands and the house notices. Redundancy here means a second VM with the same eight interfaces plus CARP so the pair looks like one router to everyone else. I have the second VM, configured and re-addressed to `.2` on every network; CARP is still on the list. The honest description of that state is "a cold copy", not "high availability".

## seven VLANs for one person: the bill

The layout, in the order the roles matter to me:

- **20 — production** (10.1.20.0/24): every service that faces the internet through a tunnel or a proxy, plus the databases behind them. Thirty-odd guests.
- **50 — management** (10.1.50.0/24): DNS, backups, monitoring, hypervisor management. The things that must work when applications don't.
- **40 — guest**: visitor phones, a TV, anything whose firmware I did not write. Internet through a VPN gateway, DNS, DHCP, and nothing else — with a kill-switch rule underneath for when the tunnel drops.
- **1 — the untagged LAN** (192.168.1.0/24): the historical network, still carried untagged on the trunk and still the address the firewall answers on. Today it is mostly the way back in when I break something.

Then the accretion: **10 — admin** for my workstation, **25 — preproduction** because a course demanded a sandbox that could not touch production, **30 — IoT**, **60 — home** for family devices that get DHCP and no rules of their own. Eight networks, seven tagged, one native.

What it cost, itemised without decoration:

**Re-addressing is the expensive part, not the tagging.** Between 26 and 28 September 2026 about thirty guests moved from `192.168.1.x` to `10.1.20.x`, eighteen reverse-proxy upstreams were rewritten, DNS records followed, and two hosts are *still* dual-homed on the old LAN because their old addresses had leaked into too many places to remove in one go. Turning on a VLAN is a five-minute change; moving into it is a migration with a calendar.

**One device that cannot move costs a rule forever.** The storage box stayed on `192.168.1.16`: it is on the legacy LAN, it holds the media library, and moving it was not worth the risk. So production reaches it through a virtual IP on the firewall and a DNAT rule — one permanent exception, in a design whose whole point was to stop having exceptions. Every network has one of these.

**Every VLAN multiplies the bookkeeping.** A scope, an interface, a rule set, a monitoring target, a backup decision, a line in the reference document. My firewall has eight networks in the sense that matters: eight places a change can be half-applied.

Which is why my verdict, as a preference and not a law: **four of the seven earn their keep.** Production, management and guest are load-bearing — they map to three genuinely different trust levels. The untagged LAN earns its place as a recovery path. Admin could merge into management tomorrow; IoT into home; preproduction exists for a reason that is pedagogical, not architectural, and I would defend it on those grounds rather than pretend it is network design.

## where the model leaks

**The native VLAN is a hole you chose.** On my trunk, VLAN 1 is untagged at both ends, and the firewall's LAN interface lives there. OPNsense's own [VLAN and LAGG guide](https://docs.opnsense.org/manual/how-tos/vlan_and_lagg.html) is explicit: there should be no native VLAN on the trunk that connects to the firewall. I break that rule deliberately, because the untagged subnet is how I get back into the box when a VLAN change locks me out — and I pay for it with the exact shape the double-tagging attack needs, where a frame carrying two tags has its outer one stripped and the inner one obeyed. Keeping that native VLAN out of every user network is what makes the trade survivable: there is no DHCP range on it, and the only address I know in it is the firewall's own. It is still a trade.

**"VLAN equals isolation" is false, and my own firewall proves it.** While collecting the capture above I listed the rules on the production interface and found a `pass` rule from an early experiment — source production, destination any, enabled, logged — still sitting in the list. That is why the ping crossed from production to management: not because VLANs are friendly, but because a rule says yes. The tag carried the packet; the rule allowed it. If I had written this article from memory I would have described a segmented network that does not quite exist. It goes on the list, and the lesson is the one worth keeping: segmentation is the policy, and the policy is only as good as your last audit of it.

**The PVID mistake is silent.** Plug a device into the wrong port and it lands in another network without an error: it gets an address from the wrong scope, or none, and the symptom looks like DNS or "the printer vanished". Two commands settle it in seconds — `bridge vlan show dev <port>` for what the port believes, and `tcpdump -e` for what is actually on the wire.

**Nothing authenticates the tag.** Anyone who controls a trunk port can claim any identifier on it. Physical access and port configuration are the real controls; 802.1Q is a label, not a lock. That is also why a "VLAN for security" argument that stops at the switch is incomplete by construction.

## before you add VLAN number eight

Four questions, in this order, because the third one usually kills the project.

**What failure are you containing?** A compromised gadget, a broadcast storm, a tenant, a course, a flatmate's experiments. If you cannot name the failure, you are about to buy addresses and documentation for nothing.

**Who must reach whom, on which port?** Draw the matrix, not the diagram. If the matrix says everyone-to-everyone, the VLANs will exist and enforce nothing — see the rule I just found. The matrix is also your firewall policy, in draft.

**Can the device be moved?** Most consumer devices cannot tag; they get an access port. Some cannot change address at all — the NAS, the printer, the solar inverter — and each of those becomes a permanent exception. Count them before you start, not after.

**Who updates the address plan when it's late and something is broken?** If the answer is "nobody", the plan drifts, and a drifted plan is worse than a flat network because it *looks* designed.

Then the mechanics, small enough to keep in a shell history:

```bash
# what does the trunk really carry?
bridge vlan show dev eno4 | head

# is the guest's port what you think it is?
bridge vlan show dev veth125i0

# does the tag appear where you expect, and nowhere else?
tcpdump -i eno4 -nn -e 'icmp'       # the trunk port, not the bridge: look for "vlan 20" and length 102
```

On OPNsense the order is: **Interfaces → Devices → VLAN** to create the tagged device (parent, tag, description), then **Interfaces → Assignments** to give it an interface, an address, a DHCP scope and rules. The parent interface stays unassigned; assigning it is how people accidentally put an address on a trunk.

Precautions, all learned the dull way: snapshot the firewall VM before touching assignments; change one guest at a time, because a running guest loses its address the instant its PVID changes; keep one path into the box that does not depend on what you are editing (for me, the untagged LAN and the hypervisor console); remember that `ifreload -a` on the bridge you are connected through will cut your own session; and test the **deny**, not just the allow — ping something that must be blocked from a host in the new VLAN and confirm the block appears in the log. An untested rule is a comment.

## what the tag buys

Seven VLANs on one cable is real, and it is not what the tag does. The tag is four bytes that say *this frame belongs to 20*, written by a port and read by a port that both agreed to care. Everything I actually wanted — the guest phone that cannot reach the backups, the management network that stays reachable when production is on fire — comes from the interfaces those tags terminate on and the rules written there.

What segmentation buys is a shape: one place to write "no", one place to read it back, and a network where the question "should this reach that?" has an answer that is not "probably". What it costs is addresses, exceptions, and documents — and the documents are the part that decides whether the segmentation still exists in a year, when the person who wrote the rules is tired and the rule that allows everything is still enabled in the list.

The tag is not the wall. The wall is the rule.
