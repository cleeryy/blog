+++
title = "one front door: what a reverse proxy actually does"
date = "2026-11-03T06:55:23Z"
author = "cleeryy"
authorTwitter = ""
cover = ""
tags = ["homelab", "reverse-proxy", "tls", "caddy", "nginx", "traefik"]
keywords = ["reverse proxy", "sni", "server name indication", "tls termination", "host header", "x-forwarded-for", "x-forwarded-proto", "acme dns-01", "wildcard certificate", "caddy", "nginx-proxy-manager", "traefik", "upstream dns resolution"]
description = "A reverse proxy is not a pipe with a certificate on it. Two names get read on every request — one in the handshake, one in the request line — and between them sits a component that re-frames everything it forwards. Measured on a two-backend lab, then the honest case for Caddy, nginx-proxy-manager and Traefik."
showFullContent = false
readingTime = true
hideComments = false
+++

*Every homelab ends up with the same mess: a dozen services, each on its own port, each wanting its own certificate. One front door fixes the visible part of that and quietly introduces a component that reads your hostname twice per request, decrypts your traffic, rewrites your headers and changes when bytes leave. I put two backends behind Caddy and behind stock nginx and measured what actually arrives where. The three proxies everyone argues about do not compete on features — they disagree about where the routing table should live, and that is the only question worth answering.*

## the port numbers were never the problem

For a while, `:3000` for one app and `:8080` for another is fine. You bookmark them, you learn them, you stop noticing. What you also stop noticing is what each of those ports drags along: one certificate per service, one renewal per certificate, one authentication layer, one set of access rules, one place per service where compression and logging and headers are configured slightly differently. Twelve services, twelve small decisions made in twelve places, none of them documented.

One reverse proxy collapses that into a single listener on 443. One certificate store. One place where a request is logged, one place where a hostname can be refused, one place where an auth check runs before anything else. In exchange you get a new single point of failure, an extra hop, and a new participant in every HTTP conversation — one that is allowed to modify the message.

To see exactly what that participant does, I built the smallest lab that shows it: two Python backends that print the headers they receive, one Caddy 2.11.7, one stock nginx 1.31.8, on one Docker network, on loopback. Everything below is measured there with curl 8.14.1. Where a number is an artifact of my test rather than a property of the tool, I say so.

## the client says the name before it says hello

Before any HTTP exists, there is a TLS handshake, and the first message of that handshake is the ClientHello. It carries extensions, one of which is `server_name` — the hostname the client wants, sent in the clear, standardised in [RFC 6066](https://www.rfc-editor.org/rfc/rfc6066.txt). This is Server Name Indication, and it is the reason one IP address can host an unlimited number of certificates: the server picks the certificate during the handshake, before it has seen a single byte of the request.

Two site blocks, one port, in one Caddyfile:

```caddyfile
one.internal:8443 {
	respond "body served for host one"
}

two.internal:8443 {
	respond "body served for host two"
}
```

Caddy logs "obtaining certificate" twice, once per identifier, and the handshake then selects by name:

```text
-- servername=one.internal
issuer=CN=Caddy Local Authority - ECC Intermediate
X509v3 Subject Alternative Name: critical
    DNS:one.internal
-- servername=two.internal
issuer=CN=Caddy Local Authority - ECC Intermediate
X509v3 Subject Alternative Name: critical
    DNS:two.internal
```

Same socket, same port, two identities. That is SNI, and it is the whole reason self-hosting stopped requiring one public IP per site.

The more interesting half is what happens with no SNI at all:

```text
$ echo | openssl s_client -connect 127.0.0.1:8443 -noservername
...error:0A000438:SSL routines:ssl3_read_bytes:tlsv1 alert internal error...
CONNECTED(00000003)
no peer certificate available
```

Handshake refused. With two sites configured and no default site, the server has no way to choose, so it declines rather than guess. In practice: a client that reaches the server by IP instead of by name gets a failed connection instead of a warning page, and if you want `https://192.168.1.10` to work at all you need a site that answers for the bare IP. Not every server behaves this way — plenty fall back to the first vhost and serve a certificate that doesn't match — which is why the symptom usually presents as "it works everywhere except on this one old device".

The same extension has a privacy flip side worth one sentence, because it explains why SNI keeps appearing in security news: it travels in cleartext, so anyone on the path sees which name you asked for. Encrypted Client Hello exists to close that, and Cloudflare [documents its implementation](https://developers.cloudflare.com/ssl/edge-certificates/ech/) as partial. It doesn't change a homelab config. It does explain the attention.

## then it says it again, in the request

The handshake gives the proxy one name. The request gives it another: `Host` in HTTP/1.1, `:authority` in HTTP/2. Different layers, same string, and the fact that they can disagree is where most of the confusion in this subject lives.

One listener, two backends, no TLS involved:

```text
$ curl -H 'Host: one.internal' http://127.0.0.1:8080/hello   -> backend1
$ curl -H 'Host: two.internal' http://127.0.0.1:8080/hello   -> backend2
$ curl -H 'Host: nope.internal' http://127.0.0.1:8080/       -> 404
```

nginx does the same with two `server_name` blocks and a `default_server` that returns 404, and over TLS the routing decision is unchanged: `curl --http2` reports `proto=2 code=200`, having routed on `:authority`. So the proxy is a switch on a name — and the two names are independent. One wildcard certificate can cover fifty hostnames; fifty certificates can point at one hostname.

What breaks is the mismatch, and it breaks quietly. SNI matches and `Host` doesn't: valid certificate, correct handshake, 404 from the proxy — a page that looks like a DNS failure and isn't. `Host` matches and SNI doesn't: HTTP/2 has a status code for it (421 Misdirected Request) if the server is strict, HTTP/1.1 serves you the wrong vhost with no complaint at all. When someone tells me their certificate is fine but the page 404s, this mismatch is the first thing I ask them to eliminate.

## where the tunnel stops

Terminating TLS at the proxy means the encrypted segment ends there. Client to proxy: TLS. Proxy to backend: whatever the upstream speaks, which in a homelab is almost always plain HTTP over a bridge network.

Measured, from inside that network, asking the backend for a TLS handshake on its HTTP port:

```text
backend1   refused the handshake: SSLError: WRONG_VERSION_NUMBER
```

The proxy, asked the same question on its TLS port, completed the handshake and answered in HTTP/2. So the plaintext exists for a few centimetres of virtual cable, and everything downstream sees the request in the clear. Four consequences follow, and all four are practical rather than theoretical.

**The application has to be told what the client actually did.** It receives a plain HTTP connection, so it believes the site is HTTP. Left alone it will redirect to `http://`, or build absolute URLs with the wrong scheme, and you get a redirect loop that exists only behind the proxy. The signal is `X-Forwarded-Proto`, joined by `X-Forwarded-For` for the client address and `X-Forwarded-Host` for the original name. If a service works on its own port and loops behind the proxy, this is nearly always why.

**The internal hop is a trust boundary you chose.** Plain HTTP between proxy and app means anyone who can reach that network can read and alter the traffic. On one host with containers, that is usually a reasonable trade. Across hosts, or for anything carrying a session token in a header, terminate a second time — `reverse_proxy https://backend:8443` with an internal CA or a pinned certificate — and let the proxy speak TLS on both sides.

**Certificates live in exactly one place.** That is the win: one ACME client, one renewal job, one place to notice that renewal has been failing for a week. It is also the risk: one expiry takes every hostname down at once, which makes renewal a thing to monitor rather than a thing to assume.

**Whatever terminates TLS can read and rewrite the body.** This is not a defect; it is the property that makes the proxy worth having. It is also why injecting a script tag into every page is a small config change rather than a reverse-engineering project — I do exactly that in my own lab, for analytics — and why the right to edit that config is a privilege worth thinking about. A proxy that can rewrite HTML can rewrite a login form.

If you cannot terminate, none of this applies, because you don't use a reverse proxy. Passthrough exists: an L4 proxy reads the SNI field, ignores everything after it, and forwards bytes to a backend that keeps its own certificate. The trade is total — no path routing, no header rewriting, no auth injection, and the client address usually has to be carried separately with PROXY protocol. It is the right answer for non-HTTP protocols and for software that insists on owning its keys. It is the wrong answer for a homelab front door.

## it does not relay, it re-frames

Same request, same backend, seen from the application. Through Caddy:

```json
"headers_seen": {
  "host": "one.internal:8080",
  "via": "1.1 Caddy",
  "x-forwarded-for": "172.20.0.1",
  "x-forwarded-host": "one.internal:8080",
  "x-forwarded-proto": "http",
  "accept-encoding": "gzip"
}
```

Through stock nginx, with a single `proxy_pass http://backend1:8000;`:

```json
"headers_seen": {
  "host": "backend1:8000",
  "user-agent": "curl/8.14.1",
  "accept": "*/*"
}
```

Read those two blocks carefully, because they explain a decade of bug reports. nginx rewrote `Host` to the upstream's own name — `$proxy_host` is the default — and added no forwarding headers at all. Caddy passed the original `Host` through and added three. Both are correct. Neither is what people assume. An application that checks `Host` against a configured domain (Django's `ALLOWED_HOSTS`, Nextcloud's trusted domains, anything with a CSRF origin check) works behind one and returns 403 behind the other, for a request that is otherwise identical.

The nginx fix is four lines, and they are worth knowing by heart:

```nginx
location / {
    proxy_pass http://backend1:8000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

One caveat that the snippet itself doesn't show: `X-Forwarded-For` arrives from the client, so `$proxy_add_x_forwarded_for` appends to a value the client controls. An app that trusts the leftmost entry is trusting whoever can reach the proxy. Overwrite rather than append at the edge, and let each proxy in the chain add its own hop only where you know the chain.

The `accept-encoding: gzip` in Caddy's request is the other half of "re-frames". The proxy negotiates compression with the upstream on its own terms, so that it can decompress, modify and re-compress for a client that asked for something else. That is the mechanism behind body rewriting — and the reason a page-injection snippet needs the upstream to answer uncompressed. I learned that the tedious way, watching a rewrite do precisely nothing on gzipped responses with no error anywhere.

### the numbers, and what they don't say

Three hundred sequential keep-alive requests, one client, loopback, small JSON body:

```text
direct      median=42.00 ms   p95=43.13 ms
via caddy   median=42.77 ms   p95=44.04 ms
via nginx   median=1.01 ms    p95=1.35 ms
```

The honest reading is not "Caddy is forty times slower than nginx". Both the direct and the Caddy paths are dominated by something unrelated to proxying: my Python backend writes headers and body as two small writes, and the ~40 ms gap is consistent with the classic delayed-ACK/Nagle interaction. I did not capture packets, so that stays an interpretation, not a proven cause. nginx's default response buffering is the likely reason for the 1 ms figure: it collects the body and writes it once, which removes the 40 ms wait entirely.

Which is the actual lesson: a proxy is an HTTP peer, so it takes part in message framing, and framing alone can move a latency number by a factor of forty without anything being wrong. It also means most "proxy X is faster" benchmarks are really benchmarks of the backend's write pattern and the client's behaviour. These numbers say nothing about throughput, TLS handshakes or concurrency. One client, one socket, on loopback.

The same caution applies to the folklore that nginx buffers server-sent events and that you must set `proxy_buffering off`. With stock defaults, a four-event stream arrived as emitted through both proxies:

```text
caddy   first chunk at 1 ms, then 1002 / 2002 / 3002
nginx   first chunk at 3 ms, then 1004 / 2004 / 3004
```

The flag was not the problem here. What genuinely breaks streaming is compression, because a gzip buffer is not a stream, and slow clients, where buffering changes when bytes actually leave. I would rather report that the widespread advice did not reproduce on my setup than repeat it as fact.

### what containers do to a fixed config

One more measurement, because it decides more homelab arguments than any benchmark. I moved a backend to a different address on the same network and asked each proxy for a page, reloading nothing:

```text
via caddy:  200, served by the container at its new address
via nginx:  502 after 38.7 s
            connect() failed ... upstream: "http://172.20.0.2:8000/x"
```

Caddy resolves the upstream name when it dials, so the next request finds the new address. nginx resolved `backend1` once, at config load, and kept the old address until a reload. With stock configuration it also refuses to start if the name doesn't resolve yet — my first attempt died with `host not found in upstream "backend1"`, which is a genuinely confusing error when the container is simply not up yet.

Three ways out: static addresses (simple, needs discipline), a `resolver 127.0.0.11 valid=10s;` with a variable in `proxy_pass` (correct, but it changes how the request URI is passed, which surprises people), or regenerate and reload on container events. This is the strongest practical argument for a proxy that watches the runtime instead of reading a file.

## three front doors, three answers to where the truth lives

Now the choice — with the history, because the defaults only make sense as sediment.

**nginx** is the substrate. Igor Sysoev began it in 2002 and released it publicly in 2004 under a BSD licence, event-driven by design at a time when the competition allocated a process per connection. Nginx, Inc. was founded in 2011; F5 [announced the acquisition](https://www.f5.com/company/news/press-releases/f5-acquires-nginx-to-bridge-netops-devops) on 11 March 2019 for about $670 million and [closed it](https://www.f5.com/company/news/press-releases/f5-completes-acquisition-of-nginx) on 9 May 2019. In February 2024, core developer Maxim Dounin forked it as [freenginx](https://freenginx.org/pipermail/nginx-devel/2024-February/000002.html), writing that F5 had overridden the project's own security policy by forcing a security release for bugs in experimental HTTP/3 code — as [The Register reported](https://www.theregister.com/software/2024/02/16/nginx-web-server-forked-as-freenginx/), a disagreement about process rather than code. For a homelab, the durable facts are duller: configuration is a file read at start and reload, upstream names are resolved at that instant, and almost every GUI in this space is a generator for that file.

**Caddy** is the one that made HTTPS the default and then built a company story around it. Matt Holt started it in December 2014 and released it in April 2015; 1.0 came in April 2019, and [2.0 on 5 May 2020](https://en.wikipedia.org/wiki/Caddy_%28web_server%29) was a full rewrite — JSON configuration, an admin REST API, everything as modules compiled into one binary. In 2020, ownership passed to apilayer with the licence unchanged at Apache-2.0, as Holt [announced himself](https://caddy.community/t/caddy-and-certmagic-have-new-ownership-no-changes-to-licensing-or-development/9754). The design consequence is the one that matters: the server knows which hostnames it serves, so it can obtain and renew certificates for them without being told, and it uses a local CA for names that can't have public ones — which is exactly what the two-certificate test above used.

**Traefik** is the one that does not want a configuration file at all. Émile Vauge wrote the first lines in 2015 in Lyon and posted it to Hacker News on 22 September 2015; v1.0 landed in 2016, v2 in 2019 rebuilt the model around routers, middlewares and services, v3 in April 2024, and the company is now Traefik Labs — a decade of that arc is [told by its author](https://traefik.io/blog/celebrating-10-years-of-traefik). Its bet is that in a container world the routing table *is* the runtime: providers watch Docker labels, files or Kubernetes objects and derive routes from them. The cost is real — there is no file to read to know what is routed, and the Docker provider needs the Docker socket, which on any host is root-equivalent.

**nginx-proxy-manager** is the GUI layer over the substrate. The repository dates from 20 December 2017, MIT licensed, built by Jamie Curnow to make "reverse proxying hosts with SSL termination" easy enough that, in the [README](https://github.com/NginxProxyManager/nginx-proxy-manager)'s words, "a monkey could do it". Proxy hosts live in a SQLite database, nginx config is generated from them, certificates come from certbot inside the image. As I write, the project carries ~34.5k stars and 871 open issues, and the [latest release](https://github.com/NginxProxyManager/nginx-proxy-manager/releases) (v2.16.0, September 2026) includes bumping OpenResty for a batch of CVEs. That lag between an nginx CVE and the image that bundles it is the concrete complaint behind community forks such as [NPMplus](https://github.com/ZoeyVid/NPMplus), and it is the honest weak point of the model: you have added an abstraction, and you now depend on someone else's rebuild cadence for the security of the layer underneath.

## the criteria I would actually weigh

Not a ranking — four questions, because they decide more than features do.

**Where should the routing table live?** In a file you can diff, in a database behind a form, or in the runtime itself. A file in git gives review, history and rollback, and it is what I use: one small file per hostname, a directory mirrored by cron, `caddy validate` before a reload. A database gives speed of entry and little else — no diff, and the configuration exists only on that machine. Runtime labels give correctness when containers churn, at the cost of legibility.

**Who owns certificates, and can it get a wildcard?** All three speak ACME. What separates them is the challenge. HTTP-01 needs port 80 reachable from the internet for every name, one at a time. DNS-01 needs API credentials for your DNS provider and buys you `*.example.com` in a single certificate — the only version that works for names that never face the internet. That token can rewrite your DNS; scope it to one zone and treat it as a secret, because it is one.

**What happens when a backend's address changes?** Measured above: nothing for a fixed nginx config, everything for a proxy that watches the runtime. If your services are containers that get recreated, a static upstream is a config that is silently wrong until someone notices. Choose deliberately: static addresses, a resolver directive with its sharp edges, or a runtime-aware proxy.

**What is the failure mode?** With a file-based proxy, a bad config usually fails at validation or at reload and the old config keeps serving — a property worth designing around: validate, then reload, never restart. With a runtime-derived proxy, a bad label deployed by someone else's `docker compose up` takes effect immediately, with no gate. With a GUI, the blast radius is whatever the form allows, and the audit trail is a checkbox.

## the door is also the single point of failure

All of the above is why one front door is convenient. Here is what it costs, from my own lab: a custom Caddy build that was missing a DNS provider module exited at config load, the service did not come back, and every hostname behind it answered nothing for about forty seconds — not because a site was misconfigured, but because the binary could no longer parse a directive it had been compiled without. The fix was a rebuild and reverting one file.

The lesson was not "don't build custom binaries". It was that the component in front of everything needs a validation step that runs *before* the switch, and a way back that does not depend on the thing that just failed.

What I keep as a result: config in git, one file per host, validate-then-reload (reload, never restart, so in-flight connections survive), a snapshot before upgrading the proxy itself, and an inventory of which hostnames point at it — because "half the sites are down" is much easier to bound when you can list them. And the boring one: a homelab proxy is not a load balancer. If the machine it runs on reboots, everything behind it is down anyway, and no config makes that untrue.

## one door

A reverse proxy does not remove complexity; it collects it, in one place, where you can finally see it. Two names are read on every request — one during the handshake to choose a certificate, one in the request line to choose a backend — and between them sits a component that ends encryption, rewrites headers, negotiates compression and decides when bytes leave. That is a lot of decisions in one process, which is exactly why it deserves to be one process, and exactly why it should be legible.

So the real question is not Caddy versus nginx versus Traefik. It is: do you want the routing table to be a file you can read, a form you can click, or a fact derived from what is currently running? Pick the one whose failure mode you can diagnose at two in the morning — and then make sure certificate renewal on it is monitored, because that is the failure that arrives with no deploy behind it.
