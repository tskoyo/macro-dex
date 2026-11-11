# Reclaiming an order

A farmer can take back an unsold order once their waiting period is over.

```js
const order = await market.getOrder(id);
const unlocksAt = order.createdAt + order.reclaimLock;

const { timestamp } = await provider.getBlock("latest");
if (BigInt(timestamp) < unlocksAt) {
  // Show: "You can take this back on <date>"
} else {
  await (await market.reclaim(id)).wait();
}
```

The tokens go back to the farmer's wallet (as wETH on ETH markets).

## Showing the button

- Only on the connected user's own orders (`order.farmer === me`).
- Only while the order is Open.
- Before the unlock time, show it disabled with the unlock date: `new Date(Number(unlocksAt) * 1000)`.

## Errors

- `NotFarmer`: someone other than the farmer tried.
- `StillLocked(unlocksAt)`: too early. The error includes the unlock time, so you can show it.
- `OrderNotOpen`: already bought or reclaimed.

## Testing locally

On anvil you can skip ahead in time instead of waiting days. The demo UI has a "+24h" button that does this:

```js
await provider.send("evm_increaseTime", [86400]);
await provider.send("evm_mine", []);
```
