# Frontend integration: overview

This section shows how a website talks to the market contracts. The examples use [ethers v6](https://docs.ethers.org/v6/), the same library as the demo UI in `ui/index.html`.

## What you need

1. **The addresses** of the market and its two tokens. Locally, `make deploy` writes them to `ui/deployments.json`:

   ```json
   { "market": "0x…", "weth": "0x…", "dai": "0x…" }
   ```

   No public network deployment exists yet.

2. **The ABIs.** You can use the full JSON from `out/Market.sol/Market.json` (after `forge build`), or the short human-readable list below.

3. **A wallet connection** for anything that sends a transaction.

## Connecting

```js
import { ethers } from "ethers";

// Read-only: any RPC works.
const provider = new ethers.JsonRpcProvider("http://127.0.0.1:8545");

// To send transactions, use the user's wallet:
const browser = new ethers.BrowserProvider(window.ethereum);
const signer = await browser.getSigner();

const market = new ethers.Contract(addrs.market, MARKET_ABI, signer);
const base   = new ethers.Contract(addrs.weth,   ERC20_ABI,  signer);
const quote  = new ethers.Contract(addrs.dai,    ERC20_ABI,  signer);
```

::: tip Demo UI
The demo UI skips the wallet and uses anvil's unlocked accounts via `new ethers.JsonRpcSigner(provider, address)`. That only works on a local chain.
:::

## ABIs

```js
const MARKET_ABI = [
  "function placeOrder(uint256 amount, uint256 price, uint40 reclaimLock) returns (uint256)",
  "function placeOrderEth(uint256 price, uint40 reclaimLock) payable returns (uint256)", // WethMarket only
  "function fill(uint256 id)",
  "function reclaim(uint256 id)",
  "function getOrder(uint256 id) view returns (tuple(uint256 id, uint256 amount, uint256 price, address farmer, uint40 createdAt, uint40 reclaimLock, uint8 status))",
  "function costOf(uint256 id) view returns (uint256)",
  "function quoteCost(uint256 amount, uint256 price) view returns (uint256)",
  "function nextOrderId() view returns (uint256)",
  "function LOT_SIZE() view returns (uint256)",
  "function BASE_TOKEN() view returns (address)",
  "function QUOTE_TOKEN() view returns (address)",
  "function BASE_DECIMALS() view returns (uint8)",
  "function QUOTE_DECIMALS() view returns (uint8)",
  "event OrderPlaced(uint256 indexed id, address indexed farmer, uint40 reclaimLock, uint256 amount, uint256 price, uint256 createdAt)",
  "event OrderFilled(uint256 indexed id, address indexed farmer, address indexed buyer, uint256 amount, uint256 price, uint256 cost, uint256 filledAt)",
  "event OrderReclaimed(uint256 indexed id, address indexed farmer)",
  // errors: see "Handling errors"
];

const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
];
```

## The three user flows

| Flow | Who | Steps |
|---|---|---|
| [Place an order](./placing) | Farmer | approve base token → `placeOrder` (or `placeOrderEth`, no approve) |
| [Buy an order](./buying) | Buyer | `costOf` → approve quote token → `fill` |
| [Reclaim an order](./reclaiming) | Farmer | wait for the lock → `reclaim` |

## Units, in one paragraph

Amounts are always in the token's smallest unit (wei for 18-decimal tokens). **Price is the exception**: it's a plain whole number of quote tokens per whole base token, e.g. `2500n`. Never compute the cost yourself for display if you can avoid it; ask the contract with `quoteCost` or `costOf`.
