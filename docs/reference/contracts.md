# Contracts

Two contracts, both in `src/`. One instance is launched per token pair.

- **`Market`**: the general market for any pair of standard tokens.
- **`WethMarket`**: the same market for pairs where ETH is sold, plus one extra function to pay in plain ETH.

Neither has an owner, fees, or upgrades.

## Settings (fixed at launch)

| Name | Meaning |
|---|---|
| `BASE_TOKEN()` | token being sold |
| `QUOTE_TOKEN()` | token used to pay |
| `BASE_DECIMALS()` / `QUOTE_DECIMALS()` | each token's decimals, checked against the token at launch |
| `LOT_SIZE()` | order amounts must be a multiple of this |
| `SCALE_MUL()` / `SCALE_DIV()` | internal unit conversion between the two tokens; one is always 1 |

Launch parameters: `Market(baseToken, quoteToken, baseDecimals, quoteDecimals, lotSize)` and `WethMarket(weth, quoteToken, quoteDecimals, lotSize)`. A market refuses to launch if its lot size could ever cause rounding.

## Actions

| Function | Who | What it does |
|---|---|---|
| `placeOrder(amount, price, reclaimLock) → id` | farmer | locks `amount` base tokens (approve first) |
| `placeOrderEth(price, reclaimLock) → id` | farmer | `WethMarket` only: send ETH, it's wrapped and locked |
| `fill(id)` | buyer | buys the whole order (approve `costOf(id)` quote first) |
| `reclaim(id)` | farmer | takes an unsold order back after its lock |

`reclaimLock` must be one of 86400, 172800, 259200, 345600, 432000 seconds (1 to 5 days).

## Reading

| Function | Returns |
|---|---|
| `nextOrderId()` | number of orders ever placed (next ID) |
| `getOrder(id)` | the order (fields below) |
| `costOf(id)` | what a buyer pays, in quote smallest units |
| `quoteCost(amount, price)` | the same, before placing; reverts on invalid input |

**Order fields:** `id`, `amount`, `price`, `farmer`, `createdAt`, `reclaimLock`, `status` (0 Open, 1 Filled, 2 Reclaimed).

## Events

| Event | Emitted by |
|---|---|
| `OrderPlaced(id, farmer, reclaimLock, amount, price, createdAt)` | `placeOrder`, `placeOrderEth` |
| `OrderFilled(id, farmer, buyer, amount, price, cost, filledAt)` | `fill` |
| `OrderReclaimed(id, farmer)` | `reclaim` |

## Errors

See [Handling errors](../integration/errors) for the full list and suggested messages.
