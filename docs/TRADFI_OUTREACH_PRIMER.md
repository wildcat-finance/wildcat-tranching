# Two-class credit in 90 seconds

For a full meeting pack, use the [BD field kit](bd/README.md).

## The trade

One borrower. One facility. Two risk books.

Junior funds the first-loss piece and keeps the residual return. Senior funds above it for a fixed
accounting target and gets first claim on value and recovery cash. If junior is exhausted, senior loses
money. Both classes live or die on the same borrower.

This is not a claim that private credit has become liquid. Exit waits for the underlying loan to produce
cash and may settle in pieces.

## Who might want it

- a borrower or originator trying to match one facility with two pools of risk appetite;
- a senior desk that wants visible first-loss capital beneath it;
- a junior desk willing to take the first hit for the residual economics; or
- a treasury or allocator willing to underwrite one named credit and an asynchronous exit.

## What to ask

1. Who is the borrower and what repays the loan?
2. How much junior capital is funded, and which downside burns through it?
3. What return does senior need for the credit and expected time to cash?
4. What can change after closing, and who can say no?
5. Who may hold each class, and who owns monitoring and workout?
6. What are the full borrower charges, including platform, origination and arrears costs?

## What not to pretend

- Senior is not guaranteed.
- The junior cushion is not rebuilt after loss.
- Transferability does not create a market or a bid.
- An exit request is not a promise to pay on a fixed date.
- Operating wind-down is not automatically legal default.
- The current implementation is a tested prototype, not a rated, audited or production product.

## Platform charge

The borrower pays the loan rate plus the platform charge. The current participation facility adds no
second fee. The platform charge is a percentage of lender interest, not principal, and it affects the
cash available before unprocessed exits. Cash already processed for withdrawal is not displaced by a
later fee collection.

## Next meeting

Bring one borrower, one proposed capital stack and three cash cases: whole, junior impaired and senior
impaired. If the price, subordination and time to cash survive those cases, keep going.
