// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Market} from "../src/Market.sol";
import {MarketTestBase} from "./MarketTestBase.sol";

/// @notice wBTC/USDC (8 → 6). The quote has fewer decimals, so the market divides by 100.
///         Steps must be whole multiples of 100 sats or the divide would drop dust.
contract WbtcUsdcMarketTest is MarketTestBase {
    function _deploy() internal override {
        // 0.001 BTC step, 60,000 USDC per BTC.
        _deployMockPair("WBTC", 8, "USDC", 6, 1e5, 60_000);
    }

    function test_pair_scaleFactors() public view {
        assertEq(market.SCALE_MUL(), 1);
        assertEq(market.SCALE_DIV(), 100);
    }

    function test_pair_costInUsdc() public view {
        assertEq(market.quoteCost(1e8, 60_000), 60_000e6, "1 BTC @ 60,000 = 60,000 USDC");
        assertEq(market.quoteCost(1e5, 60_000), 60e6, "0.001 BTC @ 60,000 = 60 USDC");
        assertEq(market.quoteCost(1e5, 1), 1000, "0.001 BTC @ 1 = 0.001 USDC");
    }

    function test_constructor_revertsWhenStepWouldRound() public {
        vm.expectRevert(abi.encodeWithSelector(Market.StepWouldRound.selector, 1, 100));
        new Market(baseToken, quote, 8, 6, 1, LOCK);

        vm.expectRevert(abi.encodeWithSelector(Market.StepWouldRound.selector, 150, 100));
        new Market(baseToken, quote, 8, 6, 150, LOCK);
    }

    function test_constructor_acceptsStepOf100Sats() public {
        Market m = new Market(baseToken, quote, 8, 6, 100, LOCK);
        // The smallest possible order at the smallest price costs exactly 1 USDC unit.
        assertEq(m.quoteCost(100, 1), 1);
    }
}
