# Buying an order

A buyer always buys the **whole** order.

## Steps

1. Ask the contract for the exact cost.
2. Approve the market to take that much of the quote token.
3. Call `fill`.

```js
const cost = await market.costOf(id);

const allowance = await quote.allowance(me, addrs.market);
if (allowance < cost) {
  await (await quote.approve(addrs.market, cost)).wait();
}

await (await market.fill(id)).wait();
```

In that one `fill` transaction, the payment goes from the buyer straight to the farmer, and the base tokens go from the market to the buyer.

## Before showing the Buy button

- Only for orders with `status === 0` (Open).
- Hide it on the farmer's own orders. Filling your own order reverts with `SelfFill`.
- Check the buyer has at least `cost` of the quote token, so you can show a clear message instead of a failed transaction.

## If two people try at once

Only the first `fill` to land succeeds. The second reverts with `OrderNotOpen`. Show "Someone just bought this order" and refresh the list.

## ETH markets

Buyers always receive **wETH**, never plain ETH. If you want users to end up with ETH, offer an "Unwrap" button that calls `withdraw(amount)` on the wETH contract.
