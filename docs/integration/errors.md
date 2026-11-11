# Handling errors

The market uses named errors instead of text messages. Turn them into something a person can read.

## Decoding

Include the errors in your ABI (list below). ethers then decodes them for you:

```js
try {
  await (await market.fill(id)).wait();
} catch (e) {
  const name = e.revert?.name;          // e.g. "OrderNotOpen"
  const args = e.revert?.args;          // e.g. [unlocksAt] for StillLocked
  showMessage(MESSAGES[name] ?? e.shortMessage ?? "Something went wrong");
}
```

If `e.revert` is missing, the raw data can still be decoded. This is what the demo UI does:

```js
const data = e?.data ?? e?.info?.error?.data;
const decoded = new ethers.Interface(MARKET_ABI).parseError(data);
```

## What to tell the user

| Error | When | Suggested message |
|---|---|---|
| `InvalidAmount` | amount is 0 or not a multiple of the lot size | "Amount must be a multiple of {lot size}." |
| `InvalidPrice` | price is 0 | "Enter a price above zero." |
| `InvalidReclaimLock` | lock isn't 1–5 days | "Pick a waiting period of 1 to 5 days." |
| `CostTooLarge` | amount × price is absurdly large | "That order is too large." |
| `OrderNotFound` | ID doesn't exist | "That order doesn't exist." |
| `OrderNotOpen` | already filled or reclaimed | "This order is no longer available." |
| `SelfFill` | farmer tries to buy own order | "You can't buy your own order." |
| `NotFarmer` | someone else tries to reclaim | "Only the seller can take this back." |
| `StillLocked(unlocksAt)` | reclaim too early | "You can take this back on {date}." |
| `UnexpectedTransferAmount` | token took a fee on transfer | "This token isn't supported." |
| `WrapFailed` | ETH wrapping failed (ETH markets) | "Couldn't wrap your ETH. Try again." |
| `ERC20InsufficientBalance` | not enough tokens | "Not enough {token} in your wallet." |
| `ERC20InsufficientAllowance` | approval missing or too small | "Please approve {token} first." |

`ZeroAddress`, `SameToken`, `DecimalsOutOfRange`, `DecimalsMismatch`, `InvalidStep` and `StepWouldRound` only happen when launching a market, never in normal use.

## Error ABI

```js
const ERROR_ABI = [
  "error ZeroAddress()", "error SameToken()", "error DecimalsOutOfRange()",
  "error DecimalsMismatch(address token, uint8 expected, uint256 reported)",
  "error InvalidStep()", "error StepWouldRound(uint256 step, uint256 scaleDiv)",
  "error InvalidReclaimLock()", "error InvalidAmount()", "error InvalidPrice()",
  "error CostTooLarge()", "error OrderNotFound()", "error OrderNotOpen()",
  "error SelfFill()", "error NotFarmer()", "error StillLocked(uint256 unlocksAt)",
  "error UnexpectedTransferAmount(uint256 expected, uint256 received)",
  "error WrapFailed()",
  "error ReentrancyGuardReentrantCall()", "error SafeERC20FailedOperation(address token)",
  "error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed)",
  "error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed)",
];
```

The two `ERC20…` errors come from OpenZeppelin tokens like the local mocks. Real tokens (USDT, older DAI) may revert with a plain message instead, so always keep a fallback.
