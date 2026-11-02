// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Market} from "./Market.sol";

/// @title Farmer's Market for a wETH pair
/// @notice Same contract as Market, plus one convenience: farmers may pay in plain ETH
///         and the contract wraps it into wETH for them.
/// @dev The contract still only ever holds and sends wETH. It never sends raw ETH,
///      which keeps the reentrancy surface small. The frontend offers unwrapping.
contract WethMarket is Market {
    IERC20 public immutable WETH;

    error WrapFailed(uint256 expected, uint256 received);

    /// @param weth_            The official wETH contract. Always 18 decimals.
    /// @param quoteToken_      DAI, USDC, USDT, ...
    /// @param quoteDecimals_   Decimals of the quote token. Cross-checked in Market.
    /// @param amountStep_      e.g. 0.01 ether.
    constructor(IERC20 weth_, IERC20 quoteToken_, uint8 quoteDecimals_, uint256 amountStep_)
        Market(weth_, quoteToken_, 18, quoteDecimals_, amountStep_)
    {
        // Market's constructor already confirmed this token really reports 18 decimals.
        WETH = weth_;
    }

    /// @notice Place an order by sending plain ETH. The contract wraps it into wETH.
    /// @param price Whole quote units per 1 ETH, e.g. 2500.
    /// @param cancelLock Anti-spoofing delay before a farmer may cancel, e.g. 24 hours.
    function placeOrderEth(uint256 price, uint256 cancelLock) external payable nonReentrant returns (uint256 id) {
        _checkAmountAndPrice(msg.value, price);
        _checkCancelLock(cancelLock);

        // Same safety idea as placeOrder: confirm we really received what we expect,
        // rather than trusting the wrapper. wETH mints 1:1, so this should always hold.
        uint256 balanceBefore = WETH.balanceOf(address(this));
        // WETH.deposit{value: msg.value}();
        (bool ok,) = address(WETH).call{value: msg.value}(abi.encodeWithSignature("deposit()"));
        if (!ok) {
            revert WrapFailed(msg.value, WETH.balanceOf(address(this)) - balanceBefore);
        }

        uint256 received = WETH.balanceOf(address(this)) - balanceBefore;
        if (received != msg.value) revert WrapFailed(msg.value, received);

        id = _createOrder(msg.sender, msg.value, price, cancelLock);
    }
}
