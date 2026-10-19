+++
title = "neoprivesc - thcon 2025"
date = '2025-04-12T10:07:00Z'
draft = false
categories = ["misc", "privilege escalation"]
description = 'when your terminal flexing becomes a security issue'
+++

## the mission

> we saw that gideon morse is a keen artist and that he loves beautiful things... perhaps a bit too much. looks like he's been into ricing his nixOS / libreBoot / hyprland / astrovim / neofetch / btop a lot lately and we think this may help us.
>
> we have access to a user session on his laptop but all important files are only available to administrator.

**points**: 500  
**category**: misc

## connection confusion

my first attempt at connecting to the challenge server was a complete failure:

```
[apr 12, 2025 - 10:07:33 (cest)] exegol-thcon ctf # nc 74.234.198.209 32849
SSH-2.0-OpenSSH_7.7
ls
protocol mismatch.
```

oops! the server was expecting ssh, not my casual netcat approach. after a facepalm moment, i re-read the challenge details and noticed the credentials were hiding in plain sight: `bud:bud` (apparently they weren't there at first, making me feel slightly less oblivious).

## poking around

after ssh-ing in as "bud", i did what any curious hacker would do - started snooping around:

1. spotted a juicy `flag.txt` file in `/home/bud/`, but it was taunting me with permissions belonging to someone named "blossom".

2. checked what superpowers our buddy "bud" had:

```
$ sudo -l
user bud may run the following commands on hostname:
(blossom) NOPASSWD: /usr/bin/neofetch
```

hold up... we can run neofetch as blossom? the same blossom who owns our flag? interesting! 

## the "oooh, pretty!" vulnerability

for those unfamiliar, neofetch is that tool linux enthusiasts use to show off their system specs with fancy ascii art (because regular system monitoring tools aren't aesthetic enough).

the key insight: neofetch has a `--source` parameter that lets you specify a custom file for the ascii art. 

and guess who can run neofetch as blossom? that's right - us! 
and guess what file blossom can read? the flag!

this is like finding out the security guard with access to the vault also has a habit of reading documents out loud when asked nicely.

## getting artsy with it

the exploitation was as elegant as it was simple:

```bash
sudo -u blossom neofetch --backend ascii --source /home/bud/flag.txt
```

i told neofetch to run as blossom, interpret the flag file as ascii art, and display it to me. suddenly, our flag wasn't just information - it was art!

## the treasure

```
flag{*******}
```

## security takeaways

besides getting a cool flag, this challenge taught some valuable lessons:

1. **harmless tools can bite**: even a tool designed to make your terminal look pretty can become a security nightmare when given the wrong permissions.

2. **sudo privileges matter**: giving users the ability to run specific commands as other users should be carefully considered - even "harmless" display tools.

3. **think creatively**: sometimes the path to privilege escalation isn't through buffer overflows or injection attacks - it's through the aesthetic customization tools of a linux enthusiast.

moral of the story: next time someone shows off their fancy neofetch setup, maybe check if they can also read your private files with it.
