# Placing an order

A farmer chooses an **amount**, a **price**, and a **waiting period**.

## Check the inputs first

- **Amount** must be a non-zero multiple of `LOT_SIZE`.
- **Price** must be a whole number above zero.
- **Waiting period** must be exactly 1, 2, 3, 4 or 5 days, in seconds. Offer these as five fixed choices, not a free field.

```js
const DAY = 86400n;
const LOCK_CHOICES = [1n, 2n, 3n, 4n, 5n].map((d) => d * DAY);

const amount = ethers.parseUnits(amountInput, baseDecimals); // e.g. "0.5" → 0.5e18
const price  = BigInt(priceInput);                           // e.g. "2500"
const lock   = LOCK_CHOICES[selectedIndex];

if (amount === 0n || amount % lotSize !== 0n) throw new Error("Amount must be a multiple of the lot size");

// Show the buyer's total before submitting (also validates amount & price):
const total = await market.quoteCost(amount, price);
```

## Option A: with tokens the farmer already holds

Two transactions: approve, then place.

```js
const allowance = await base.allowance(me, addrs.market);
if (allowance < amount) {
  await (await base.approve(addrs.market, amount)).wait();
}

const tx = await market.placeOrder(amount, price, lock);
const receipt = await tx.wait();
```

## Option B: with plain ETH (ETH markets only)

If the market is a `WethMarket`, farmers can send ETH directly. One transaction, no approval needed.

```js
const tx = await market.placeOrderEth(price, lock, { value: amount });
await tx.wait();
```

`amount` here is the ETH value sent, and still has to be a multiple of `LOT_SIZE`.

## Getting the new order's ID

Read it from the `OrderPlaced` event in the receipt:

```js
const placed = receipt.logs
  .map((log) => { try { return market.interface.parseLog(log); } catch { return null; } })
  .find((e) => e?.name === "OrderPlaced");

const orderId = placed.args.id;
```

## Things that can go wrong

`InvalidAmount`, `InvalidPrice`, `InvalidReclaimLock`, `CostTooLarge`, `UnexpectedTransferAmount`, or the token's own "not enough balance/allowance" error. See [Handling errors](./errors).
