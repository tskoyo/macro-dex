# Glossary

### Farmer
The person selling. They place an order and their tokens are held by the market.

### Buyer
The person buying. They pay for a whole order in one step.

### Order
One offer to sell a set amount at a set price. Each order has a number (its ID), starting from 0.

### Base token
The token being sold, such as ETH or BTC.

### Quote token
The token used to pay, such as DAI or USDC.

### Price
How many whole quote tokens buy one whole base token. Always a whole number, for example 2,500.

### Lot size
The smallest step an order can be sized in. If the lot size is 0.01 ETH, an order can be 0.01, 0.02, 1.5 ETH and so on, but not 0.015 ETH. Each market has its own lot size, fixed at launch.

### Waiting period (reclaim lock)
How long the farmer must wait before they can take back an unsold order: 1, 2, 3, 4, or 5 days, chosen by the farmer.

### Filled
The order was bought. Finished.

### Reclaimed
The farmer took the order back. Finished.

### Spoofing
Posting fake orders to mislead others, then pulling them before anyone can buy. The waiting period prevents this.
