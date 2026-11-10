+++
title = "default deny is a rule, not a setting"
date = "2026-11-10T06:50:00Z"
author = "cleeryy"
authorTwitter = ""
cover = ""
tags = ["homelab", "opnsense", "firewall", "pf", "network-security", "pfsense"]
keywords = ["default deny", "opnsense firewall rules", "pf quick keyword", "last matching rule", "stateful packet filter", "rule order", "shadowed firewall rule", "opnsense firewall log", "block vs reject", "bogon networks", "firewall audit", "m0n0wall", "pfsense fork", "deciso"]
description = "pf's own default is to pass the packet. The deny is a rule somebody writes at the bottom of a list — and its value is exactly the quality of the lines above it. Going through the fifteen rules I wrote: the catch-all that carried the traffic, the block that is dead, the block that is not, a guest network with no rule at all, and a log that counts one connection attempt seven times."
showFullContent = false
readingTime = true
hideComments = false
+++

*A default deny is not a posture you enable, it is a line of text at the bottom of a list. I read mine from top to bottom, found the catch-all that carried almost every interesting packet, a VLAN with no rule at all, and a block that only works because of where it sits. The list is the policy. Everything else is machinery.*

## the rule that said yes

My blog runs in a container on the production network, `10.1.20.41`. The backup server sits on the management network, `10.1.50.78`, with its API on port 8007. I opened one TCP socket between them and then read the firewall log:

```text
08:02:24  vlan0.20  in   pass  10.1.20.41 -> 10.1.50.78:8007  tcp  S
          label: "[DEV] PRODUCTION Allow all traffic"

08:02:24  vlan0.50  out  pass  10.1.20.41 -> 10.1.50.78:8007  tcp  S
          label: "let out anything from firewall host itself"
```

Two decisions for one packet: the interface it entered, and the automatic rule that governs everything leaving the firewall. The rule that actually decided is the first one, and I gave it a `[DEV]` prefix — the universal marker for a rule everyone intends to remove.

Which means that packet did not have a policy of its own. Neither does the SSH session I open to the hypervisors, nor the DNS queries from the machines on that network, nor the connection to the firewall's own web interface on `10.1.20.1:443` that appears in the same log excerpt, carried by the same rule. Until I read the list, I would have described my production policy as "production reaches management for backups and nothing else". The list says: production reaches everything. The list is what runs.

So the question this article is really about is not "should I use default deny". It is: what does a default deny actually do, once you already have fifteen rules of your own, and how do you read them?

## where this firewall comes from

The engine underneath is old and unusually well documented, and the product on top of it has a fork history that explains a few things you can see in my own configuration dump.

[m0n0wall](https://en.wikipedia.org/wiki/M0n0wall) came first: a FreeBSD image with a web interface, built by Manuel Kasper in 2003 for embedded PCs, at a time when a firewall meant a proprietary box or a hand-written ruleset on a server. pfSense forked it in 2004 and became the reference answer for the next decade. In 2014 the company behind pfSense changed hands, the build tools stopped being publicly available, and Deciso — a Dutch networking firm that had been sponsoring the project — decided to fork.

The [OPNsense "About the Fork" page](https://docs.opnsense.org/history/thefork.html) is explicit about the reasons, and they are worth reading as an argument rather than a grievance: code quality and a dispersed development method, a web GUI that performed tasks requiring root, a framework (they chose Phalcon, an MVC layer for PHP) so that new features would not be written as one more page of procedural PHP, build tools anyone could use, a predictable release cadence, and a simple licence. The first release, `15.1 "Ascending Albatross"`, is dated [2 January 2015](https://docs.opnsense.org/releases/CE_15.1.html) in the project's own notes, based on FreeBSD 10 and BSD-2-Clause licensed. m0n0wall's author shut his project down the following month and told its users to look at OPNsense.

Eleven years later the shape of that decision is visible in the version number: the project releases on a year.month calendar, two majors a year in January and July. My firewall reports `26.1.11`, code name "Witty Woodpecker", firmware built 7 August 2026; `26.1` itself shipped on [28 January 2026](https://docs.opnsense.org/releases/CE_26.1.html) and `26.7` is the next series. The independent coverage of 26.1 — [Help Net Security](https://www.helpnetsecurity.com/2026/01/29/opnsense-26-1-open-source-firewall/) among others — picks the same headline features the release notes do: a redesigned rules interface, a live log rewritten for faster reading, Suricata 8 with inline inspection through `divert`, and extended API coverage including NAT.

That API matters to me more than the GUI. This article exists because I can query the rule list and the log programmatically and compare them, which is the only reason I noticed the catch-all at all.

The ecosystem, briefly, because "which firewall" is the wrong question and "which packet filter, for which shape of network" is the right one. pfSense CE still uses the same `pf` engine and is Apache-2.0 today, but its release rhythm and its commercial split make it a different bet. OpenWrt runs on Linux with nftables and solves the router-plus-Wi-Fi problem rather than the firewall problem. VyOS is a routed platform with a CLI, no GUI to speak of, and a configuration model closer to Junos. IPFire is a distribution built as an appliance. RouterOS is closed. And plain nftables on a Linux box is a real option for someone who enjoys writing rules by hand — it is what I would use if I only needed a router.

What OPNsense occupies is the narrow middle: FreeBSD and `pf` under a full web interface and a REST API, with a configuration that lives in a single XML file you can copy, diff and version. What it costs is equally specific. There are two rule implementations living side by side — the original PHP pages whose rules sit in `config.xml`, and the newer MVC/API model that `26.1` extended — and my own rules all come back from the API flagged `legacy: true`, a 2015-era configuration running inside a 2026 firewall. The GUI still runs with privileges a web application should not have, which [XDA notes a decade after the fork was justified partly by fixing exactly that](https://www.xda-developers.com/why-use-opnsense-over-pfsense-dont-trust-netgate). Clustering is CARP plus manual work, not a product feature. And `pf` states are a finite resource the firewall reserves for itself, ten percent of RAM by default. None of this is disqualifying; all of it is the price of the licence and the cadence.

## pf's own default is to pass

Here is the fact that reorganises the whole subject. From the [pf.conf manual](https://man.openbsd.org/pf.conf):

> For `block` and `pass`, the last matching rule decides what action is taken; if no rule matches the packet, the default action is to pass the packet without creating a state.

The packet filter does not deny anything by default. It passes. A firewall that blocked traffic out of the box would be a firewall you cannot SSH into after installing it, so the safe default for a general-purpose engine is permissiveness, and the deny has to be installed as policy.

OPNsense installs it as a rule. In my dump it is the first entry, and it is named:

```text
action   block
quick    false
log      true
label    "Default deny / state violation rule"
```

Everything about how it works is in those four fields. It blocks, it logs, it is *not* `quick`, and it is registered before the rules you write, because the ruleset is sorted by an internal priority where system rules come first: floating rules, then interface groups, then the interface's own. The tab you are looking at is never the whole order.

The `quick` field is the mechanism. In `pf`, rules are evaluated in order; the last matching rule wins, unless a rule carries `quick`, in which case evaluation stops at the first match. OPNsense sets `quick` on the rules you create — it is the default in the dialog — so your rules behave as "first match wins", top to bottom, which is how everyone describes firewalls. The deny deliberately leaves `quick` off, so it never wins an argument: it only applies to packets that fell through every other rule and reached the end of the list.

The rest of the order, from the [rules documentation](https://docs.opnsense.org/manual/firewall.html): automatic rules first, then floating rules (priority `200000`), then interface groups (`300000`), then the rules of the interface itself (`400000`), with the visible sequence deciding within a group. My dump confirms the numbering — the automatic entries carry sort orders like `000001.1000016`, and the WAN bogon block sits at `000005.1000049`, ahead of everything I wrote.

Two more properties complete the model.

**Filtering happens on entry.** A rule on the production interface governs traffic *arriving from* that network. Return traffic does not need a rule, because a `pass` creates a state and the state table answers for the reply. That is also why the WAN rules are mostly about refusing things nobody asked for: most of what crosses that interface is reply traffic no rule will ever evaluate, and the log only shows decisions, not flows.

**NAT is evaluated before the filter.** The docs are blunt about the consequence: a port forward with "filter rule association: pass" generates a rule that lets the translated traffic through before your ruleset gets a look, and "no other rules will apply". A default deny cannot help you with a NAT rule you forgot.

So the correct sentence about default deny is: it is the rule that catches what no other rule claimed. It cannot be wrong in your favour, it costs nothing, and it says exactly zero about what you allowed. A blocked packet in the log tells you what you did not permit; it does not tell you what you decided.

## fifteen rules, read in order

I have eighteen rules in the configuration, three of them disabled. The rules screen counts seventy-seven entries because the system adds its own: the deny, the IPv6 ICMP exemptions, the DHCP exceptions written per interface, a CrowdSec blocklist, a Wazuh drop table, the port-zero guards. Fifteen lines are mine, and reading them top to bottom, per interface, is the whole audit.

Start with the one I already showed you, on production:

```text
1  DNS Technitium                pass  -> 10.1.50.53:53
2  PRODUCTION acces NAS          pass  -> 192.168.1.16/32
3  [DEV] PRODUCTION Allow all    pass  -> any
```

Rule 2 is decoration. Rule 3 already permits the NAS, and permits everything else as well, so the specific rule adds nothing to the decision — it adds a sentence to the interface that reads like specificity and behaves like a comment. Rule 1 does real work, but not the work it looks like: it is there to log DNS traffic, because the catch-all would pass it anyway.

Now the same shape, one interface over, on my administrative network:

```text
1  DNS Technitium                pass  -> 10.1.50.53:53
2  Allow all local traffic       pass  -> RFC1918
3  Filtered Blocked Access       block -> any
```

This one is alive, and the reason is instructive. Rule 2 is broad but its destination is *narrower* than any — it only matches private address space. So rule 3 is not shadowed by it: it catches everything rule 2 declined, which is the entire internet. Read literally, this interface says: this network may reach every private address I own, and — as far as the filter is concerned — may not reach the internet at all. I am honestly not sure I wrote it intending that sentence. But that is the sentence that runs, and it is the sentence I would have to defend if someone asked why the admin laptop cannot download a browser update.

Put a single rule in a different position and the meaning inverts. If rule 2 had said `any` instead of `RFC1918`, rule 3 would be dead text — unreachable, because nothing would ever get past the pass. That is the entire failure mode of firewall administration, and it does not look like a mistake in the interface: it looks like a careful list where one line is quietly doing nothing.

Which is why the count of `any` is my first audit number. Five of my fifteen enabled rules have `any` as destination. Two of those are deliberate blocks. Three are passes, and one of the three is named `[DEV]`.

## what the log counts

Reading the log is the second half of the skill, and the log lies in specific, learnable ways.

**One forwarded packet produces two entries.** You saw it above: `in` on the production interface with my rule's label, `out` on the management interface with an automatic rule that says yes. So the log's line count is roughly twice the packet count for routed traffic, and the second line rarely tells you anything — outbound is permitted by default in OPNsense, using a non-quick rule whose honest label is "let out anything from firewall host itself".

**Retransmissions look like an attack.** Here are seven entries from twenty-nine seconds of my WAN log, with the addresses blanked:

```text
08:01:52  in  block  <src>:22462 -> <wan-ip>:23  tcp  S  ttl 47  label "Default deny / state violation rule"
08:01:55  in  block  <src>:22462 -> <wan-ip>:23  tcp  S  ttl 47  id 58362
08:01:58  in  block  <src>:22462 -> <wan-ip>:23  tcp  S  ttl 47  id 58362
08:02:09  in  block  <src>:22462 -> <wan-ip>:23  tcp  S  ttl 47  id 58362
08:02:12  in  block  <src>:22462 -> <wan-ip>:23  tcp  S  ttl 47  id 58362
08:02:18  in  block  <src>:22462 -> <wan-ip>:23  tcp  S  ttl 47  id 58362
08:02:21  in  block  <src>:22462 -> <wan-ip>:23  tcp  S  ttl 47  id 58362
```

Same source port, same IP identification field, same initial sequence number, same TTL: one SYN that nobody answered, retried by the sender with backoff. Seven lines, one connection attempt. Any "blocked packets per hour" figure counts retries as events, and so does any sentence beginning "my firewall blocked four thousand attacks".

**The label is the only part of the log you control.** `reason: match` means a rule decided. The label tells you which. When the label is `Default deny / state violation rule`, you know a packet was refused but not by what policy — only that no policy claimed it. That is why the rules worth naming are the blocks, not the passes.

**Two denied packets look completely different to the client.** `Block` drops silently. `Reject` answers: TCP gets a reset, UDP gets an ICMP unreachable. The docs recommend block towards untrusted networks and reject internally so a client fails in milliseconds instead of waiting out its timeout. I use block everywhere, which means most of my internal denials are indistinguishable, from the client's side, from a cable being unplugged.

And one measurement of my own that was worth more than the others:

```text
$ ping -c1 10.1.50.53
ping: socket: Operation not permitted
$ nc -z -w2 10.1.50.53 53   ; echo $?
0
$ nc -z -w2 10.1.50.53 9999 ; echo $?
1
```

The ping failed because the container I ran it from has no `CAP_NET_RAW`, not because a firewall did anything. If I had written my notes from the first line I would have concluded "ICMP blocked between production and management", which is false — the packet never left the host. The third command is the useful one: exit code 1 means the host answered with a reset, so it was reached and nothing was listening; a hang would have meant the packet was dropped somewhere. Distinguishing "no answer" from "an answer that says no" is most of network diagnosis, and it is the first thing a silent block takes away from you.

## the shape of a small ruleset

A per-interface ruleset for a network that should reach the internet and nothing else has four jobs, and the order is the design. This is `pf` syntax, written to show the shape — OPNsense generates its own labelled version of the same decisions, and I would not paste this into anything:

```text
# guest: address, resolver, way out, and then nothing
pass  in  quick  on $guest  proto udp  from any to any port 67   # DHCP
pass  in  quick  on $guest  proto tcp/udp from <guest> to <resolver> port 53
pass  in  quick  on $guest  route-to ($tun, $tun_gw) from any to !<rfc1918>
block in  quick  on $guest  from any to any  log
```

Line one exists because a DHCP server writes it automatically when you enable DHCP on an interface — which is also why an interface with DHCP enabled is never truly rule-less.

Line two is narrower than it looks: DNS goes to one address, not to "the internet", because a guest that can choose its own resolver can bypass every name-based policy you think you have.

Line three is the interesting one. Its destination is "anything that is not private", and it is pinned to a gateway — the tunnel. That pin is what turns a routing preference into a policy: traffic that the tunnel rule does not carry falls through to line four, which blocks. The block at the bottom is technically redundant, because the default deny would catch the same packets; it exists to attach a name to them, so that the log says *which* refusal rather than pointing at the generic deny every time.

I should be precise about what I have and have not verified here. The ordering is what makes this construction possible, and the ordering is visible in my configuration. I have not pulled the tunnel down to watch a packet fall into the block, so I am describing the design and what it is for, not a measurement.

Now the finding that made me rewrite my audit list. My guest interface, `vlan0.40`, has the DHCP exception the system wrote for it and no rule of mine at all. Not a narrow one, not a wrong one: none. Which means a visitor joins the network, receives an address, and then meets silence. The default deny is doing its job perfectly — it is denying, as instructed, everything nobody asked for. The list above it is simply empty.

Two readings, and I cannot pick one for you. Either guest is not in service yet, in which case the configuration is honest and the article is the only thing that just learned it; or guest is in service and nobody has tried to use it from a device that was not already on another network. Either way the lesson is the same and it is not about the deny: an empty policy and a strict policy produce the same log lines.

## an audit you can finish

The method I now use, short enough to actually repeat, in the order that finds the most for the least work.

**Count your `any`s.** Export the configuration, open the filter section, and count rules whose destination is `any`. Five, in my case. For each, ask which flows would break if it disappeared — and write those down. Mine were four: production to the backup API on 8007, production to SSH on the hypervisors, production to the resolver, production to the NAS. Four rules that say what I actually use, replacing one that says "yes".

**Read each interface as one sentence.** Not "these are my rules" but "this network may reach X and may not reach Y". If you cannot write the sentence, the list does not have one, and neither does your policy.

**Test the deny, not the allow.** From each network, connect to something that must fail and confirm your block's label appears in the log. An untested block is a comment. And test it with a tool that can tell the difference between a reset and a silence — `nc -z` and its exit code, not a ping you did not check the permissions of.

**Ask the generated ruleset, not the table.** The documentation points at `/tmp/rules.debug` whenever the order is in doubt, because that file is what the filter actually loads — internal rules, labels, `quick` keywords and all. The screens are a view; that file is the object.

**Log the rules you doubt, not all of them.** Every logged pass on a busy interface is a line you will scroll past. My DNS rules are logged because DNS is the flow I most often misconfigure; my internet pass is not, because "something reached the internet" is not news.

**Diff the export every quarter.** Not the GUI: the file. A versioned `config.xml` turns "when did this rule appear" from an archaeology project into a command.

## what a default deny is worth

Mine is worth exactly what the fifteen lines above it are worth. It is not protecting the backup API from production, because a rule called `[DEV]` says production may go there. It is not isolating admin from the internet: that sentence comes from a `block` sitting in third position behind a pass that is deliberately narrower than it. It is not even making guest safe, because guest has no policy to enforce — only a deny at the end that says "and nothing else" to a list that said nothing at all.

What it does do is make the absence visible. A firewall with a deny logs the packets nobody wrote a rule for, and those packets are the gap between what you believe about your network and what it does. That gap is the only thing worth auditing.

`pf` will happily pass every packet you never mention. The deny is one line that reverses that, and it is the least interesting line in the file — four fields, no cleverness, no `quick`, sitting at the bottom of a list that decides everything before it is ever consulted.

The list is the policy. The deny, the log, the blocklist holding sixty-nine thousand addresses: machinery around one sentence you have to be able to read out loud.
