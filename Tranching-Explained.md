# Wildcat Tranching, Explained

*One loan, two ways to lend it. This is the friendly, no-jargon tour of how Wildcat tranching works, what it does for you, and what it does when things go wrong. If you have never touched DeFi, start here. If you run a credit desk, this still covers everything, just gently.*

---

## The whole thing in one breath

Wildcat lets a real borrower take out a loan on-chain. Tranching takes that single loan and splits the lender side into two pieces: a **safe seat** and a **spicy seat**. The safe seat gets paid first and earns a steady return. The spicy seat gets paid last, earns more when things go well, and takes the hit first when things go badly. Same loan, same borrower, two completely different rides. You pick the seat that suits you.

That is the entire idea. Everything below is just the careful version.

---

## Step 1: Start with the loan

On Wildcat, a borrower (think a trading firm like Wintermute) asks to borrow stablecoins, usually USDC. Lenders put USDC in. The borrower pays interest. This is a private credit market: a real loan to a real, named counterparty, with terms everyone can see.

When you lend into one of these markets, you get a token that represents your share of the loan plus the interest piling up on it. Wildcat wraps that into a tidy, standard-shaped receipt called **v-wmtUSDC**. Think of v-wmtUSDC as a claim ticket: "I am owed this slice of the loan, and it is growing."

So far, every lender is in the same boat. Everyone shares the upside the same way, and everyone shares the risk the same way. That is fine, but it is one-size-fits-all. Some people want safety. Some people want yield. Tranching gives both groups what they want out of the same loan.

---

## Step 2: Split the lenders into two groups

Tranching takes the pool of lender claims and divides it into two tranches. "Tranche" is just French for "slice." Each slice is its own token you can hold, transfer, or sell:

- **Senior, `sr-wmtUSDC`.** The safe seat. First in line for interest, first in line to get paid back, last to take a loss.
- **Junior, `jr-wmtUSDC`.** The spicy seat. It earns whatever is left after senior is paid, which is usually more, and it absorbs losses first.

Picture two people funding a lemonade stand. The senior partner says "pay me my fixed cut first, every time." The junior partner says "I will take whatever is left over: more on a great day, nothing on a bad day, and I will eat the loss if a customer skips the bill." Same stand, same lemonade, two very different deals. That is senior and junior.

The borrower, by the way, notices none of this. They still see one loan with one set of terms. The splitting happens entirely on the lender side.

---

## Step 3: The cushion (this is the important part)

Here is what makes the safe seat actually safe. The junior slice sits underneath the senior slice and acts as a cushion. If the loan loses value, the loss eats into the junior cushion first. Senior is only touched after the entire junior cushion is gone.

Two rules keep that cushion meaningful:

- **The cushion is always at least 20% of the money.** Junior can never shrink below one fifth of the total. So senior always has a real buffer beneath it, not a token gesture.
- **Senior can never be more than four times the junior.** Same rule from the other direction. It stops the structure from getting top-heavy.

In plain terms: before a single senior dollar is at risk, at least twenty cents of every dollar in the structure (all of it junior money) has to be wiped out first. That is the protection senior is paying for by accepting a lower return.

---

## Step 4: When things go well, who earns what

The loan pays interest. That interest flows like water down a set of buckets, and the order is fixed.

**Senior's bucket fills first.** Senior is owed a target return. It is not a number plucked from the air, and it is not a promise carved in stone either. It is tied directly to what the borrower is actually paying. Senior earns a set **share** of the loan's interest rate. If the facility pays 8.5%, and senior's share is set to 80%, then senior targets about 6.8%. If the borrower's rate goes up, senior's target goes up with it. If the borrower's rate goes down, senior's target follows it down. Senior tracks the loan. It never tries to earn more than the loan itself pays.

**Junior gets everything left in the stream.** Once senior's bucket is full, the rest of the interest overflows into junior. This is where the spicy seat earns its keep. Because junior is a thin slice earning the leftover spread on the whole loan, its return is amplified. A small base of junior money is catching the overflow from a much larger pool. On a good loan, junior can earn well above the headline rate.

Quick feel for the numbers. Say senior is 300, junior is 100, the loan pays 8.5%, and senior's share is set to 80%:

- The whole 400 earns 8.5%, so 34 of interest is generated.
- Senior takes 6.8% on its 300, which is about 20.
- Junior keeps the rest, about 14, on a base of just 100. That is roughly a 14% return. The same 8.5% loan, felt as 14% by junior.

That amplification is the deal junior signs up for. It is also why junior takes the first loss: the extra return is the pay for standing in front.

(One edge worth knowing: if you set senior's share all the way to 100%, senior simply earns the full loan rate and junior earns the same rate, with no amplification left over. Junior would then be taking first-loss risk for no extra reward, which nobody wants. So in practice the share is set below 100%, and that gap is exactly junior's premium for being the cushion.)

---

## Step 5: When things go badly, who loses what

Losses run down the same buckets, but in the opposite direction, draining from the bottom.

If the loan loses value, junior's bucket empties first. Senior stays completely whole until junior hits zero. Only after the junior cushion is entirely gone does senior start to feel anything.

A quick feel for it, same 300 senior and 100 junior:

- The pool drops 20%, from 400 to 320. Senior is still owed 300, so senior is fine at 300. Junior absorbs the entire 80 of loss and is left with 20.
- The pool drops to 200. Junior was only 100, so junior is wiped out to zero, and senior, owed 300, now holds the remaining 200. Senior finally takes a loss, but only after junior was completely gone.

This is "first-loss," and in Wildcat it is not a marketing claim. It is enforced by the contract on every single calculation. Junior cannot dodge it, and senior cannot jump the queue in reverse.

---

## Step 6: How your slice is valued (no pretending)

Each tranche has a price, and you might expect that price to wobble around based on guesses about the future. It does not. The value is based only on money that is actually real and actually there. No oracles guessing a price, no optimistic marks.

This matters most when a borrower starts paying late. On Wildcat, late borrowers get charged a penalty rate, and on paper that makes the claim look like it is growing even faster. It would be easy, and dishonest, to book that paper growth as profit. Tranching refuses to. When the loan is in trouble, the value is frozen at its last genuinely-good level. It does not climb on penalty interest that has not actually been paid.

The rule is simple and one-directional: freeze the gains you have not really earned, but recognize the losses immediately. You only ever count money you can actually point to.

---

## Step 7: Getting your money out

This is the part people most often get wrong, so read it twice. Tranches are **not an ATM**. You do not click withdraw and get instant cash. You join a queue, the same withdrawal queue the underlying loan uses.

Here is the flow:

1. **You request to exit.** You hand back your senior or junior tokens and get put in line for your share of the loan.
2. **You wait.** The request sits in the loan's withdrawal queue until there is real cash to pay it. That cash comes from the borrower repaying or from new lenders coming in.
3. **You claim.** Once cash is available, you pull your share.

And the queue has a strict order: **senior is always at the front.** When cash comes back, senior gets made whole first. Junior is paid only once senior has what it is owed. So if there is only enough cash for some of the line, senior gets it, and junior waits.

This is on purpose. The whole point of the safe seat is that it is first to be paid, in good times and in bad. The trade-off is that everyone, senior included, is in a queue rather than holding instant-access cash. Think semi-liquid, not a checking account.

---

## Step 8: What "default" means, and what happens

Borrowers can be a little late. That is normal, and the loan charges them a penalty for it. "Default" is something more serious: the borrower has been deep in arrears for a long, sustained stretch.

Wildcat's own rules define this. After a borrower blows past their grace period and then stays in penalty for a continuous further 90 days, the loan is considered in default. Tranching mirrors that exact definition on-chain, reading the loan's own clock. (A specific written agreement between borrower and lenders can override the timing, in either direction, since the real definition is ultimately a legal one.)

Nothing on a blockchain happens by itself, so this does not magically trigger. Anyone can give the contract a nudge to check the clock, and ordinary activity (someone depositing or redeeming) nudges it automatically. The moment the contract registers default, three things happen:

- **Senior stops its meter.** Senior's claim stops growing, frozen at its default-day value.
- **The doors close to new money.** No new deposits.
- **An orderly wind-down begins.** Whatever can be recovered, including anything recovered later through off-chain legal enforcement, is paid out through the queue, senior-first, with junior absorbing whatever shortfall remains.

So to be perfectly clear about where the pain actually shows up: the contract never reaches in and slashes a price out of nowhere. During trouble, values freeze. The real loss lands later, as cash comes back lighter than hoped through the withdrawal queue, and that cash is always handed out senior-first. Junior is written down to zero before senior loses a cent.

---

## Step 9: The safety rails

A few things are built in specifically so you do not have to trust anyone's good behavior:

- **The core logic cannot be changed.** The rules of the waterfall are immutable. No one can rewrite them after you are in.
- **The few adjustable settings move slowly.** The handful of knobs that can be tuned (like senior's share of the rate) sit behind a mandatory waiting period, so any change is announced well before it takes effect. No surprise overnight changes.
- **No one can freeze your exit.** The controls can pause new deposits, but they can never block senior from getting paid out. The exit door for existing money stays open.
- **Sanctions are respected.** If an address is sanctioned, its funds are routed to a secure escrow rather than paid directly, the same compliance backbone the rest of Wildcat uses.
- **The junior seat is invite-only.** First-loss is not for everyone, so junior is restricted to qualified participants who understand they are the cushion. Senior is open to the lenders the market already approves.

There is no admin button that drains the pool, and no way for the operators to walk off with the money. The structure is designed so the rules, not the operators, are in charge.

---

## Who each seat is for

**Take the senior seat if** you want capital preservation with a clear, named borrower and a hard cushion beneath you. You get a priority return that tracks the loan, you sit behind a 20% first-loss buffer, and you can watch the whole structure on-chain in real time. This is for treasuries, conservative credit allocators, and anyone who wants more than a money-market fund without giving up their place at the front of the line.

**Take the junior seat if** you have a view on the borrower and you want to be paid for it. You earn the amplified spread on the whole loan against a thin slice of capital, with no protection and the first dollar of loss. This is for credit funds, prop desks, and yield-seekers who would rather own the risk than hedge it.

**Run the desk that places both** if you want to widen your buyer base without renegotiating anything with the borrower. One loan becomes two products. You sell safety to the capital that needs safety and yield to the capital that wants yield, which deepens the facility and lowers its blended cost, all without the borrower changing a thing.

---

## How this is different

**Versus traditional securitization.** No special-purpose vehicle, no trustee, no servicer, no quarterly remittance reports. You deploy a contract per loan and you are done, with no ongoing intermediary skimming fees. Everything is visible per-block instead of in a monthly statement, settlement is instant, and the tranches are real tokens you can hold and move. The trade-offs are honest ones: you take on smart-contract and stablecoin risk, secondary markets are thinner, and final recovery in a default still leans on off-chain legal enforcement.

**Versus other on-chain tranching.** Most on-chain tranching splits up *liquid* yield, where a loss is just a price gently sliding down. Wildcat tranching is built for undercollateralized private credit, where a loss is a discrete, real-world credit event. So the loss trigger is tied to the loan's *actual* default definition, not a price chart. And the whole layer is owned by Wildcat, so there is no third party to depend on and no revenue share, and the tranche tokens slot straight into the same approved deposit flow as everything else.

---

## The honest fine print

We would rather you know this up front:

- **It is semi-liquid, not daily-liquidity.** Exits queue and can fill partially under stress. Senior-first, always.
- **It is one borrower per tranche set.** Your diversification comes from spreading across different loans, not from any single one.
- **Junior is genuinely first-loss.** It can be written all the way to zero before senior loses anything. That is the design, not an accident.
- **Recovery is part code, part courtroom.** The contract distributes recoveries senior-first, but how much is ultimately recovered in a real default depends on off-chain legal enforcement.
- **Standard DeFi risks apply.** Smart-contract risk and stablecoin risk are real. The system is independently audited before it handles real money.

---

## The recap, for the dog

One loan. Two seats. Senior is the safe seat: paid first, steady return that tracks the loan, protected by a cushion of at least 20%. Junior is the spicy seat: paid last, earns the amplified leftover, and is the cushion. Interest fills senior's bucket first and junior catches the overflow. Losses drain junior's bucket first and only reach senior once junior is empty. Getting out means joining a queue, with senior at the front. If the borrower truly defaults, senior's meter stops and everything left is paid out senior-first. The rules are fixed in code, the few knobs move slowly and in the open, and nobody can run off with the money. Pick your seat.
