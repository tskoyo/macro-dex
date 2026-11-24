// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Market} from "../../src/Market.sol";

/// @notice Test-only bot contract that buys several orders in one tx by calling `fill` in a loop.
///         Market has no sweep of its own (F4 is out of the MVP), but `fill` is permissionless,
///         so anyone can build this. It pays from its own quote balance and keeps the base tokens.
contract Sweeper {
    Market immutable market;

    constructor(Market market_) {
        market = market_;
        market_.QUOTE_TOKEN().approve(address(market_), type(uint256).max);
    }

    /// @dev All-or-nothing: if any order can't be filled, the whole tx reverts.
    function sweepAll(uint256[] calldata ids) external {
        for (uint256 i; i < ids.length; ++i) {
            market.fill(ids[i]);
        }
    }

    /// @dev Best-effort: skips orders that fail (e.g. already taken) and fills the rest.
    function sweepSkip(uint256[] calldata ids) external returns (uint256 filled) {
        for (uint256 i; i < ids.length; ++i) {
            try market.fill(ids[i]) {
                ++filled;
            } catch {}
        }
    }
}
