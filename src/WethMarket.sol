// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Market} from "./Market.sol";

/// @notice The one wETH function we need beyond a normal token: wrapping ETH.
interface IWETH is IERC20 {
    function deposit() external payable;
}

/// @title Farmer's Market for a wETH pair
/// @notice Same contract as Market, plus one convenience: farmers may pay in plain ETH
///         and the contract wraps it into wETH for them.
/// @dev The contract still only ever holds and sends wETH. It never sends raw ETH,
///      which keeps the reentrancy surface small. The frontend offers unwrapping.
contract WethMarket is Market {
    IWETH public immutable weth;

    error WrapFailed(uint256 expected, uint256 received);

    /// @param weth_            The official wETH contract. Always 18 decimals.
    /// @param quoteToken_      DAI, USDC, USDT, ...
    /// @param quoteDecimals_   Decimals of the quote token. Cross-checked in Market.
    /// @param amountStep_      e.g. 0.01 ether.
    /// @param cancelLock_      e.g. 24 hours.
    constructor(
        IWETH weth_,
        IERC20 quoteToken_,
        uint8 quoteDecimals_,
        uint256 amountStep_,
        uint256 cancelLock_
    )
        Market(
            IERC20(address(weth_)),
            quoteToken_,
            18,
            quoteDecimals_,
            amountStep_,
            cancelLock_
        )
    {
        // Market's constructor already confirmed this token really reports 18 decimals.
        weth = weth_;
    }

    /// @notice Place an order by sending plain ETH. The contract wraps it into wETH.
    /// @param price Whole quote units per 1 ETH, e.g. 2500.
    function placeOrderETH(
        uint256 price
    ) external payable nonReentrant returns (uint256 id) {
        _checkOrder(msg.value, price);

        // Same safety idea as placeOrder: confirm we really received what we expect,
        // rather than trusting the wrapper. wETH mints 1:1, so this should always hold.
        uint256 balanceBefore = weth.balanceOf(address(this));
        weth.deposit{value: msg.value}();
        uint256 received = weth.balanceOf(address(this)) - balanceBefore;
        if (received != msg.value) revert WrapFailed(msg.value, received);

        id = _createOrder(msg.sender, msg.value, price);
    }
}
