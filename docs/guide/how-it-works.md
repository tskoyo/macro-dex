# How it works

Every order goes through a short, predictable life.

```text
   Farmer places order
           │
           ▼
        ┌──────┐
        │ Open │
        └──────┘
         │     │
 a buyer │     │ waiting period over,
 buys it │     │ farmer takes it back
         ▼     ▼
   ┌────────┐ ┌───────────┐
   │ Filled │ │ Reclaimed │
   └────────┘ └───────────┘
```

An order is always in one of three states: **Open**, **Filled**, or **Reclaimed**. Once it's Filled or Reclaimed, it's finished for good.

## 1. A farmer places an order

The farmer decides three things:

- **How much** to sell. Amounts come in fixed steps called the [lot size](./glossary#lot-size), for example 0.01 ETH at a time.
- **The price**, as a whole number. For example, "2,500 DAI for each ETH".
- **The waiting period**: 1, 2, 3, 4, or 5 days.

The farmer's tokens move into the market and the order appears for everyone to see.

When the base token is ETH, farmers can send plain ETH. The market wraps it into wETH for them automatically.

## 2a. A buyer buys it

A buyer picks an open order and pays the full price. In one step:

- the payment goes **directly to the farmer**, and
- the tokens go **directly to the buyer**.

The order is now **Filled**. A farmer can't buy their own order.

## 2b. Or the farmer takes it back

If nobody buys the order, the farmer can take their tokens back, but only **after** the waiting period they chose has passed.

The order is now **Reclaimed**.

## Why the waiting period?

Without it, a farmer could post a tempting order and pull it the instant a buyer tried to take it. That's a trick called *spoofing*: it makes the market look busier or cheaper than it really is. The waiting period means every order you see is genuinely available for at least a day.

Next: [Why it's safe →](./safety)
