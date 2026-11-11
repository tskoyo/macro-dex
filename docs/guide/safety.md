# Why it's safe

Farmer's Market is deliberately small. Fewer moving parts means fewer things that can go wrong.

## No one is in charge

There is no owner, no admin key, and no upgrade button. Once a market is launched, its rules are fixed forever. Nobody can pause it, change the fees (there are none), or move anyone's tokens.

## No fees

The farmer receives exactly what the buyer pays. Nothing is skimmed off.

## No rounding, ever

Different tokens count in different-sized units, a bit like dollars vs. cents. Converting between them can leave tiny leftover crumbs that someone loses.

Farmer's Market avoids this completely. When a market is launched, it checks that its lot size makes every possible trade come out exact. If it wouldn't, the market refuses to launch at all.

## Strange tokens are turned away

Some tokens take a cut every time they move, or change balances on their own. These would leave the market short when it's time to pay someone back. The market checks that it received exactly what was promised on every new order, and refuses the order if not.

## Orders can't be pulled at the last second

Every order stays available for the full waiting period the farmer chose (1 to 5 days). See [How it works](./how-it-works#why-the-waiting-period).

## Every order can always be bought

The market checks every new order to make sure the price math will always work. An order that could never be bought would trap the farmer's tokens, so such orders are rejected up front.

## Protected against double-dipping

An order is marked as finished **before** any tokens move. That way nobody can trick the market into paying out the same order twice.

## It only holds what it needs

The market never holds plain ETH and never sends it. It only holds the tokens of the open orders, and every one of those is owed to a specific farmer or buyer.
