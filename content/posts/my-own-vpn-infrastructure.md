+++
title = "how i created my own vpn infrastructure at home"
date = "2025-04-16T13:58:20Z"
author = "cleeryy"
authorTwitter = "" #do not include @
cover = ""
tags = ["vpn", "raspberry-pi", "networking", "security", "wireguard"]
keywords = ["vpn", "raspberry pi", "wireguard", "home network", "wake-on-lan", "network security"]
description = "because nothing says \"i'm a cybersecurity enthusiast\" like running your own vpn server on a device smaller than a sandwich"
showFullContent = false
readingTime = true
hideComments = false
+++

## the motivation

as a computer science student focused on security, i wanted a project that was both practical and educational. accessing my home network securely from anywhere seemed like the perfect challenge - plus, it meant i could pretend my girlfriend's place was just an extension of my home office.

## the hardware setup

for this project, i went with a Raspberry Pi 4 B - the swiss army knife of DIY computing projects. it's small enough to hide behind my router, powerful enough to handle vpn traffic, and doesn't consume enough electricity to make my wallet cry.

## operating system dilemma

i installed Ubuntu Server on my pi. while my heart secretly yearns for Arch Linux (btw) or plain Debian, i needed something that wouldn't decide to have an existential crisis while i'm trying to access important files remotely.

> sometimes boring and stable beats exciting and unpredictable, especially when you're 50km from your server

## pivpn installation

setting up the vpn was surprisingly straightforward thanks to PiVPN. installation was as simple as running:

```bash
curl -L https://install.pivpn.io | bash
```

it's like having training wheels for your vpn installation - guiding you through the process without forcing you to manually edit config files while questioning your life choices.

i chose Wireguard over OpenVPN because:
- it's faster (like, significantly faster)
- the codebase is smaller (fewer places for bugs to hide)
- it's integrated into the linux kernel (fancy!)
- my raspberry pi doesn't heat up like it's trying to toast bread

## the wake-on-lan challenge

here's where things got interesting. i wanted to wake my pc remotely, but Wireguard doesn't let you directly access mac addresses like OpenVPN does.

let me explain this a bit more technically: wireguard operates exclusively at layer 3 (the network/ip layer) of the osi model, while wake-on-lan magic packets need to work at layer 2 (the data link/mac address layer). openVPN can operate in "tap" mode which works at layer 2 and would allow direct mac address access, but wireguard simply can't do this - it was designed for ip traffic only.

instead of accepting defeat or switching to openVPN (and giving up those sweet wireguard performance benefits), i decided to build a small api server on my pi that bridges this gap.

the solution? a simple fastapi-based web service that lives on my raspberry pi inside my local network, where it does have access to layer 2 and can send those magic packets directly.

here's the python magic i crafted:

```python
from fastapi import FastAPI
from wakeonlan import send_magic_packet

app = FastAPI()

# Replace with your PC's MAC address
PC_MAC_ADDRESS = "10:7C:61:4C:7D:C7"

@app.get("/wake")
async def wake_pc():
    try:
        send_magic_packet(PC_MAC_ADDRESS)
        return {"message": "Wake-on-LAN packet sent successfully"}
    except Exception as e:
        return {"error": f"Failed to send Wake-on-LAN packet: {str(e)}"}

@app.get("/")
async def root():
    return {"message": "Welcome to the Wake-on-LAN API"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8008)
```

this tiny api has one job: when i connect through my vpn and make an http request to my raspberry pi at port 8008, it sends the magic packet to wake my computer. since the pi is physically on my local network, it can broadcast the layer 2 frames containing the magic packet with the mac address, which my sleeping pc will recognize.

simple, elegant, and it works like a charm. now i can boot my pc while still in bed, because walking to the power button is so 2023.

## the subnet struggle

i ran into a classic network address collision problem. when connected to external wifi networks (because burning through 200GB of mobile data would cost me a fortune), i couldn't properly access my home devices.

here's why: most home networks (including mine) use the 192.168.1.x range. so when i tried to access my home server at 192.168.1.29 while connected to, say, a café wifi also using 192.168.1.x addressing, my requests would go to devices on the café network instead of tunneling through my vpn to my home devices.

the solution was to set up custom ip mapping with iptables rules on my pi:

```bash
sudo iptables -t nat -A PREROUTING -d 192.168.5.0/24 -j NETMAP --to 192.168.1.0/24
sudo iptables -t nat -A POSTROUTING -s 192.168.5.0/24 -d 192.168.1.0/24 -j MASQUERADE
sudo netfilter-persistent save
```

these commands create a clever address mapping system. when i'm on my vpn and try to access a 192.168.5.x address (like 192.168.5.29), my raspberry pi translates that to the corresponding 192.168.1.x address on my home network (like 192.168.1.29).

it's like having a secret translator that ensures all network traffic reaches its destination, even when everyone's speaking different ip languages.

## the result

after some troubleshooting (and maybe a few colorful words muttered at 2am), i now have a fully functional home vpn infrastructure that:
- lets me securely access my home network from anywhere
- wakes my pc with a simple http request
- handles network traffic routing seamlessly
- makes me feel like a legitimate network administrator

all this running on a device that costs less than a decent dinner for two and uses less power than my phone charger.

## final thoughts

building your own vpn infrastructure is surprisingly rewarding. not only do i have a practical tool i use daily, but i also gained hands-on experience with networking concepts that will be valuable for my security career.

plus, there's something immensely satisfying about saying "let me check that on my home server" when someone asks a technical question. instant credibility points!

*if you've made it this far, congratulations! you now know more about my home network than my isp probably ever will.*
