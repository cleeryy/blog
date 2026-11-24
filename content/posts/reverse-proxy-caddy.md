+++
title = "the caddyfile is not the config: anatomy, wildcards, and the gate before reload"
date = "2026-11-24T06:55:24Z"
author = "cleeryy"
authorTwitter = ""
cover = ""
tags = ["homelab", "reverse-proxy", "caddy", "tls", "acme", "dns", "configuration"]
keywords = ["caddyfile", "caddy adapt", "caddyfile anatomy", "directive order", "route vs handle", "caddy json config", "caddy admin api", "caddy validate", "caddy reload", "zero downtime reload", "wildcard certificate", "dns-01 challenge", "acme dns challenge", "cloudflare dns plugin", "xcaddy", "libdns", "certmagic", "letsencrypt wildcard", "propagation timeout", "caddy pitfalls"]
description = "A Caddyfile is not what Caddy runs: it is compiled into JSON first, and that one fact explains the ordering surprises, the whole-config reloads and the plugin you forgot to build. Three levels of the format, why a wildcard certificate forces DNS-01 and what a DNS token really costs, and the validate-then-reload ritual measured on 2.11.7 — including a config that passes validation and answers 503 to every request."
showFullContent = false
readingTime = true
hideComments = false
+++

*Everything behind my front door is routed by a format that Caddy never executes. The Caddyfile is an adapter input, compiled to JSON before the process sees it — and once you know that, its oddities stop being oddities: why directives run in an order you did not write, why a reload replaces everything at once, why one missing module can take every hostname down. Here is the file's anatomy, the real price of a wildcard certificate, and the gate I now put between editing and reloading, measured rather than remembered.*

## the file that gets compiled

Ask Caddy what it is configured to do and the honest answer is a JSON document. The Caddyfile is a convenience format with its own adapter, and [`caddy adapt`](https://caddyserver.com/docs/command-line) prints exactly what your file becomes:

```text
$ caddy adapt --config Caddyfile --pretty
{
  "apps": { "http": { "servers": { "srv0": { "listen": [":8080"], "routes": [ ... ] } } } }
}
```

That is not a debugging curiosity. It is the whole mental model. The process holds JSON; the admin API on `localhost:2019` speaks JSON; `caddy reload` ships JSON. The Caddyfile only exists between your editor and that compile step, which has three practical consequences I use every week.

The first: errors arrive before anything runs, with a line number. A trailing directive and a forgotten brace in one of my test files produced this, exit code 1, process untouched:

```text
adapting config using caddyfile: syntax error: unexpected token 'yes',
expecting '}', at /cfg/Caddyfile.syntax:8
```

The second: what you can ask a running Caddy is the compiled form, not your file. There is no "show me the Caddyfile you loaded" — there is `/config/` and a JSON tree. Good for verification, useless for diffing against git unless you also keep the source.

The third, and the one that bites: the Caddyfile has no partial updates. The project's [own comparison table](https://caddyserver.com/docs/getting-started) is unusually blunt about this, listing "whole config changes" for the Caddyfile against "partial config changes" for JSON, plus "cannot traverse within Caddyfile" and "more computational". Every reload is the entire configuration, recompiled. That is a trade I accept for readability, but it means a mistake in one site block and a mistake in twenty are the same event.

## where this thing comes from

Two lines of history explain the shape of the format better than any tutorial.

Matt Holt started Caddy in 2014 and released it publicly in 2015, with automatic HTTPS as the organising idea — [Ardan Labs' acquisition announcement](https://www.ardanlabs.com/news/2020/08/caddy-server-is-acquired/) describes it as "a way to provide automatic and default HTTPS support for websites". Version 1 landed in April 2019. Then [2.0, in May 2020](https://en.wikipedia.org/wiki/Caddy_%28web_server%29), was not an increment: it was a rewrite around modules, a JSON configuration document and an admin API, with the Caddyfile demoted to one adapter among several. That rewrite is why `caddy adapt` exists at all, and why a module you did not compile in is a fatal parse error rather than a warning: the binary is assembled from modules, and the configuration names them.

Ownership changed in 2020. Holt [announced in September](https://caddy.community/t/caddy-and-certmagic-have-new-ownership-no-changes-to-licensing-or-development/9754) that the project had been acquired by apilayer — the deal closed about six months earlier, with Ardan Labs staying on as commercial support — while the licence stayed Apache-2.0 and he kept working on it full-time, funded by sponsorship. Alongside apilayer as premier sponsor, the sponsor page asks every professional user to contribute; a third-party profile lists companies such as Stripe, Framer and Mercedes-Benz among them, which I would treat as reported rather than verified.

Where it is now: the 2.11 line. [2.11.9](https://github.com/caddyserver/caddy/releases) shipped on 5 November 2026 — mostly FastCGI security fixes plus a fix for a regression that broke PHP directory indexes, with the notes recommending an upgrade. My proxy runs 2.11.7, two patches behind, and the cadence is quick enough to matter: 2.11.6 on 1 October, 2.11.9 five weeks later, and the patch releases carry their own "breaking changes" sections. That is honest engineering, and it means reading release notes before upgrading, not after.

The honest ledger, since nobody needs another feature list. What it does well: a routing table that fits in a review diff, HTTPS that is on by default without external ACME tooling, one static binary, and a JSON API good enough that you can build your own control plane. What it costs: the Caddyfile is deliberately less expressive than the JSON underneath it, every non-core feature is a module and therefore a custom build, and the DNS providers in particular are community-maintained one per registrar, so their quality and their maintenance are not uniform. Add the learning curve of a directive order you did not write, and you have a tool that rewards reading its documentation — which is roughly the point of this article.

## three levels and one rule

The format fits on one screen once you accept it has exactly three levels: an optional global options block, optional snippets, and site blocks.

```caddyfile
{
	email ops@example.com
	acme_dns cloudflare {env.CF_API_TOKEN}
}

(security-headers) {
	header {
		Strict-Transport-Security "max-age=31536000"
		X-Content-Type-Options "nosniff"
	}
}

app.example.com {
	import security-headers
	reverse_proxy 10.0.0.20:8080
}
```

The global block carries decisions that belong to the process rather than a site: the ACME account email, the admin address, storage, default ports. Snippets are textual macros — `import security-headers` pastes a block, and `import` can take arguments. Site blocks are the only place directives may live, and the [documentation](https://caddyserver.com/docs/caddyfile/concepts) states the rule plainly: there is no global scope or inheritance across site blocks.

That sentence deserves a moment, because it is where people coming from nginx get hurt. There is no `http { }` wrapper for shared proxy settings. Two sites that need the same four lines need the same four lines twice, or a snippet. If two site blocks' addresses overlap, the most specific address wins and the request does not cascade into the other block. It is a set of independent programs that happen to live in one file, not a hierarchy.

Inside a site block, the first token on a line is a directive, and the second may be a matcher. A path (`/api/*`), a named matcher (`@post`), a host, a method, a header — matchers are how you say *this directive applies to these requests*:

```caddyfile
app.example.com {
	@api path /api/*
	reverse_proxy @api 10.0.0.20:8080
	reverse_proxy 10.0.0.30:3000
}
```

### the order you wrote is not the order that runs

Here is the part that produces most of the "Caddy ignored my directive" reports. Directives are not evaluated top to bottom. The adapter sorts them into a [default order hard-coded into Caddy](https://caddyserver.com/docs/caddyfile/directives), so that a proxy always runs before a file server regardless of where you typed it.

I wrote a site block with five directives in a deliberately awkward order — `file_server`, `encode`, `reverse_proxy`, `header`, `root` — and asked the adapter what it made of it:

```text
written:   file_server, encode, reverse_proxy /api/*, header /api/*, root *
compiled:  vars(root) -> headers -> encode -> reverse_proxy -> file_server
```

Root first, because it is a variable that later handlers read. Headers before the encoder, because response headers are set before the body is compressed. The proxy after both. The file server last, as the fallback. Nothing was reordered randomly; the sort encodes a dependency graph, and the documentation says so: the order can be overridden with the `order` global option or escaped entirely with `route`.

`route` is the escape hatch worth knowing, because [its contents keep written order](https://caddyserver.com/docs/caddyfile/directives/route) — the adapter wraps them in a `subroute` and does not sort them:

```caddyfile
:8081 {
	route {
		header X-Step one
		respond "written order"
	}
}
```

Compiled, that is a `subroute` whose inner handle list is `headers`, then `static_response`, in the order I typed. And `handle` is the third option, subtly different: mutually exclusive blocks evaluated in written order, first match wins — which is what you want when "these requests go here and no further".

Three ways to express order, and they are not interchangeable. Default sort for normal sites; `handle` for mutually exclusive branches; `route` when you genuinely need a sequence. When a config behaves strangely, `caddy adapt` is the arbiter, not your reading of the file.

## what the shorthand buys, and what it costs

A single line, `reverse_proxy 10.0.0.20:8080`, is doing more than it looks: setting `X-Forwarded-For`, `X-Forwarded-Proto` and `X-Forwarded-Host`, preserving the client's `Host` (unlike stock nginx), negotiating compression with the upstream, and streaming rather than buffering. I measured those defaults against nginx in [the earlier post about what a proxy actually does](/posts/reverse-proxy-explained/), so I will not re-litigate them here.

The larger shorthand is TLS. A site address is not just a routing key, it is a *name Caddy is now responsible for*: list `app.example.com` and Caddy obtains a certificate for it, renews it, and redirects port 80 to 443 without being asked. Names that cannot have public certificates — `localhost`, an internal hostname — get a locally-trusted CA instead, which is why a throwaway lab on loopback shows certificates issued by "Caddy Local Authority".

This is the design decision that separates Caddy from the rest of the field, and it has a price worth naming: the process needs to know every name at compile time, needs write access to a certificate store, and needs a way to prove control of each domain. Which brings us to the one case where "automatic" stops being automatic.

## a wildcard costs a dns token

A wildcard certificate is the obvious answer to "fifty hostnames, one cert". It is also the point where Caddy's automation stops and your DNS provider starts, for a reason that comes from ACME rather than Caddy: Let's Encrypt's [challenge documentation](https://letsencrypt.org/docs/challenge-types/) is explicit that HTTP-01 "cannot be used to issue wildcard certificates", and that DNS-01 "also allows you to issue wildcard certificates". The reason is structural — HTTP-01 proves control of one name by serving a file on it, and a wildcard is not a name you can serve a file on. DNS-01 instead asks you to publish a TXT record at `_acme-challenge.<your domain>`, which is a statement about the whole zone.

So a wildcard means your web server holds an API credential for your DNS. That is the trade, stated without decoration: a token that can create and delete records in a zone, on the machine that terminates traffic for that zone.

Caddy supports it through provider plugins, one per DNS host, mostly community-maintained under the [`caddy-dns`](https://github.com/caddy-dns) organisation. And here is the trap that catches people on their first attempt, which I reproduced in a container running the stock image:

```text
$ caddy validate --config Caddyfile.wildcard      # tls { dns cloudflare {env.CF_API_TOKEN} }
adapting config using caddyfile: parsing caddyfile tokens for 'tls':
getting module named 'dns.providers.cloudflare': module not registered: dns.providers.cloudflare
```

Exit code 1. And `caddy list-modules | grep dns` on that same image returns exactly one line — `tls.ech.publishers.dns` — nothing that can write a TXT record. The official `caddy:2` image has no DNS providers at all. DNS-01 is not a configuration you can add to a stock Caddy; it is a different binary, built with the module compiled in, usually via `xcaddy build --with github.com/caddy-dns/cloudflare`.

That single fact has a consequence I lived through the hard way: a custom binary that loses a module can no longer parse a configuration that uses it, and if it loses it during an upgrade, the process exits at config load and every hostname behind it goes dark. Mine did, for about forty seconds, because of a missing provider module rather than a bad site.

### the zone that is not a zone

Two more failure modes are worth knowing before you spend an evening on them, because both look like "the API token is wrong" and neither is.

The first is scope. The Cloudflare provider resolves a zone by name before it writes anything, and if the challenge domain is a subdomain that is not itself a zone in your account, that lookup finds nothing. What you get is `expected 1 zone, got 0 for …` — an error that appears in the [provider's own troubleshooting section](https://github.com/caddy-dns/cloudflare), usually attributed to local DNS interfering with resolution. In my case the name resolved fine and the token was fine; the certificate was simply being requested for `*.something.example.com` while the account only contains the zone `example.com`. The wildcard existed as a hostname, not as a zone, and the provider had nothing to attach a TXT record to.

The available fixes are structural, not cosmetic: request the wildcard from a name that *is* a zone, delegate `_acme-challenge` to another zone with a CNAME (the documented use of `dns_challenge_override_domain`, and it works without provider support), or take the certificate out of Caddy's hands entirely and issue it with an ACME client that walks up to the parent zone. I chose the third for one internal name — certbot with the Cloudflare plugin, a deploy hook copying the files where the service user can read them, and a hard-coded `tls` path in the site block. It works, it renews, and it is one more thing to monitor.

The override subdirective is not a free win either. Because it rewrites the domain the challenge is answered *for*, not only the domain the TXT record is written to, my attempt at it produced `Incorrect TXT record` from the CA — the record existed, at a name and with a digest the validator was not expecting. The CNAME delegation route avoids that; the subdirective, at least in the version I tried, did not.

That last detail bit twice, incidentally. Caddy runs as its own unprivileged user, `/etc/letsencrypt/live/` is root-only, and pointing `tls` at it produces a `permission denied` at reload — after which Caddy keeps serving the certificate it already had, silently, until it expires. A copy into a directory owned by the service user, refreshed by a renewal hook, is not elegance; it is the difference between a renewal and an outage with a three-month fuse.

The second failure mode is propagation. The provider writes the TXT record, then Caddy waits for it to appear in DNS before telling the CA to check. That wait has a default ceiling — `propagation_timeout` [defaults to two minutes](https://caddyserver.com/docs/caddyfile/directives/tls) — and it asks whatever resolver the box has, which on a homelab is often the internal DNS server that does not see the public zone. Both are configurable, and the provider's README suggests pinning a public resolver for the check:

```caddyfile
tls {
	dns cloudflare {env.CF_API_TOKEN}
	resolvers 1.1.1.1
}
```

### the token, since it is the actual risk

Everything above is plumbing compared to this. A DNS API token that can edit a zone can redirect every name in it; it is a more dangerous credential than a serve-only TLS key. Let's Encrypt puts it flatly: putting full DNS credentials on a web server "significantly increases the impact if that web server is hacked", and recommends narrowly scoped credentials, or running validation on a separate machine and copying certificates across. The [EFF write-up](https://www.eff.org/deeplinks/2018/02/technical-deep-dive-securing-automation-acme-dns-challenge-validation) linked from that page is worth reading before you paste a token anywhere.

In practice, that means: a token scoped to one zone and one permission (DNS edit, nothing else), stored outside the repository, injected through an environment variable so it never appears in the file you commit. My own config lives in git and gets mirrored onto the proxy host every minute, so the token lives in a separate environment file that the mirror never touches. Two paths, one of which is not versioned, on purpose.

## validate is a gate, not a proof

With DNS-01, the reload question gets sharper: a configuration that fails to load does not degrade one site, it takes certificate automation down with it. So the ritual around reloading matters more than the reload itself.

The pieces are small. `caddy validate --config Caddyfile --envfile <secrets>` parses, adapts and provisions the configuration without starting it. `caddy reload` ships a new config to the running process over the admin API. `caddy fmt --diff` shows what the formatter would change, which keeps diffs honest. And `caddy adapt --pretty` tells you what you actually wrote.

Two measurements make the shape of the gate clear. First, the case the gate catches:

```text
$ caddy validate --config Caddyfile.syntax     # unbalanced brace
syntax error: unexpected token 'yes', expecting '}' ...   exit 1
$ curl -s -o /dev/null -w '%{http_code}' localhost:18080  # still serving
200
```

The reload never happened, and the process kept its previous configuration. This is the property that makes reload-not-restart the right default: a failed reload is a no-op, not an outage. The same applies to a reload when the admin endpoint is switched off — with [`admin off`](https://caddyserver.com/docs/caddyfile/options), configuration changes become impossible without stopping the process, because `caddy reload` has nothing to talk to.

Second, the case it does not catch, which I did not expect:

```caddyfile
:8080 {
	reverse_proxy
}
```

No upstream at all. `caddy validate` answered `Valid configuration`, exit code 0. The reload succeeded, exit code 0. And then every request returned **503** with an empty body — a service that is up, listening, and unable to answer anything.

That is not a Caddy defect; it is the honest limit of validation. It checks that the file parses, that every module named exists in the binary, and that each handler can be provisioned. It cannot know that you meant to type an address. A validator sees a proxy with zero upstreams, and a validator has no opinion about your intent.

So the ritual I use has two gates, not one: validate before the switch, and a probe after it. The probe is deliberately dumb — one request per published hostname, expecting 200 or a specific redirect, run from a host that is not the proxy. It catches the 503 class of mistake, which validation structurally cannot. And because a failed reload leaves the old config running, the rollback is not a procedure: it is "don't do the second thing".

One more piece of the gate, learned from that forty-second outage: check that the binary can still parse the file *before* replacing the binary. When the proxy is a custom build, the config and the build are coupled — a module dropped from the build is not a degraded feature, it is a config that no longer compiles. Validate with the new binary, then switch, then keep the previous drop-in on disk so going back does not depend on the thing that just failed.

## the minute after the commit

I keep the routing table in a git repository — one small file per hostname, grouped by public and internal zones — and a cron job mirrors it onto the proxy host every minute, runs validate, and reloads only if validation passed. The Caddyfile itself is in that repository too, so the shape of the file is reviewable in a diff, and a bad change has a commit to revert to.

The mirror is the part that taught me the most, because it is not a deployment, it is a delete-and-replace: `rsync --delete` against the directory the process reads. A route file written by hand on the box, outside the repository, disappears at the next sync — and it disappears silently, taking one hostname down while an unrelated commit looks like the culprit. That is exactly what happened to me: a file created by hand on one day, wiped at 00:23 the next while an unrelated change synced, and two hostnames returning 404 until the file was rebuilt from the repository.

Since then the rule is boring and absolute: the repository is the configuration, the box is a copy, and anything typed directly on the box has a lifetime measured in minutes. It also means the sync script — not my memory — has to be the thing that validates, because the file that breaks production is usually not the one I was looking at.

## the gate is the point

The Caddyfile is a pleasant little language, and nearly every surprise it produces comes from forgetting that it is compiled. Directives are sorted by a dependency graph, not by your paragraphs. Snippets paste text, they do not create inheritance. A reload replaces the whole document. And the names in your site blocks are not labels — they are promises that something will obtain and renew a certificate for them.

Wildcards are where those promises cost the most: a wildcard certificate is not a bigger certificate, it is a different proof, and the proof is a credential that can rewrite your DNS. That is a fair trade if you scope the token and know which zone you are proving control of. It is a bad trade if you find out at renewal time that your wildcard was never a zone.

Which leaves the part worth keeping regardless of which proxy you run. Validation catches the file you mistyped; it does not catch the file you meant badly. The second gate — a real request to a real hostname after the switch — is two lines of shell, and it is the difference between noticing in ten seconds and noticing when someone tells you.

If you take one thing from my lab: run `caddy adapt` once on a config you think you understand. The gap between what you wrote and what runs is small, specific, and entirely predictable — as long as you look.
