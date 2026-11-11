# Reading orders

## Market settings

Read these once on page load. They never change.

```js
const [lotSize, baseDecimals, quoteDecimals] = await Promise.all([
  market.LOT_SIZE(), market.BASE_DECIMALS(), market.QUOTE_DECIMALS(),
]);
```

## Listing all orders

Order IDs start at 0 and count up. `nextOrderId()` is the ID the *next* order will get, so it's also the total count.

```js
const STATUS = ["Open", "Filled", "Reclaimed"];

const count = await market.nextOrderId();
const orders = await Promise.all(
  [...Array(Number(count)).keys()].map((i) => market.getOrder(i)),
);

const open = orders.filter((o) => Number(o.status) === 0);
```

Each order has: `id`, `amount` (base, smallest unit), `price` (whole number), `farmer`, `createdAt` (unix seconds), `reclaimLock` (seconds), `status`.

::: warning Scaling
This reads every order, which is fine for a demo. For a busy market, build the list from events instead (below) or use an indexer.
:::

## What a buyer will pay

```js
const cost = await market.costOf(id);                 // existing order
const preview = await market.quoteCost(amount, price); // before placing one
```

Both return the quote amount in its smallest unit. `quoteCost` also reverts with the same errors `placeOrder` would (bad amount, zero price), so it doubles as form validation.

## When the farmer can reclaim

```js
const unlocksAt = order.createdAt + order.reclaimLock; // unix seconds
```

Compare with the latest block's timestamp, not the user's clock:

```js
const { timestamp } = await provider.getBlock("latest");
const locked = BigInt(timestamp) < unlocksAt;
```

## Events: history and live updates

| Event | When |
|---|---|
| `OrderPlaced(id, farmer, reclaimLock, amount, price, createdAt)` | new order |
| `OrderFilled(id, farmer, buyer, amount, price, cost, filledAt)` | someone bought |
| `OrderReclaimed(id, farmer)` | farmer took it back |

`id`, `farmer` and `buyer` are indexed, so you can filter on them.

```js
// Past fills for one farmer
const fills = await market.queryFilter(market.filters.OrderFilled(null, farmerAddr));

// Live updates
market.on("OrderPlaced", (id) => refresh());
market.on("OrderFilled", (id) => refresh());
market.on("OrderReclaimed", (id) => refresh());
```

The demo UI simply re-reads everything on each new block (`provider.on("block", refresh)`), which is the simplest option locally.
