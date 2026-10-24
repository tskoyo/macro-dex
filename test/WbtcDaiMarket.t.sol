// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Market} from "../src/Market.sol";
import {MarketTestBase} from "./MarketTestBase.sol";

/// @notice wBTC/DAI (8 → 18). The quote has more decimals, so the market multiplies by 1e10.
///         Any step works, but the multiply lowers the overflow ceiling on price.
contract WbtcDaiMarketTest is MarketTestBase {
    function _deploy() internal override {
        // 0.001 BTC step, 60,000 DAI per BTC.
        _deployMockPair("WBTC", 8, "DAI", 18, 1e5, 60_000);
    }

    function test_pair_scaleFactors() public view {
        assertEq(market.SCALE_MUL(), 1e10);
        assertEq(market.SCALE_DIV(), 1);
    }

    function test_pair_costInDai() public view {
        assertEq(market.quoteCost(1e8, 60_000), 60_000e18, "1 BTC @ 60,000 = 60,000 DAI");
        assertEq(market.quoteCost(1e5, 60_000), 60e18, "0.001 BTC @ 60,000 = 60 DAI");
    }

    function test_constructor_acceptsOneSatStep() public {
        Market m = new Market(baseToken, quote, 8, 18, 1, LOCK);
        assertEq(m.quoteCost(1, 60_000), 6e14, "1 sat @ 60,000 = 0.0006 DAI");
    }

    /// @dev This price passes the first overflow check (amount * price fits), but
    ///      multiplying by SCALE_MUL would overflow. In a 1:1 market it would be fine.
    function test_placeOrder_revertsWhenScaleMulWouldOverflow() public {
        uint256 p = type(uint256).max / unit;

        _fundBase(farmer, unit);
        vm.expectRevert(Market.CostTooLarge.selector);
        vm.prank(farmer);
        market.placeOrder(unit, p);
    }
}
