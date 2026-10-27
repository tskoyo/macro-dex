// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Farmer's Market (generic pair)
/// @notice Farmers lock a "base" token at a fixed whole-number price in a "quote" token.
///         Anyone can buy a whole order at once. The farmer can't cancel for a fixed period.
/// @dev No admin, no fees, no upgrades. One deployed instance per pair.
///      For a pair where the base token is wETH, deploy WethMarket instead, which adds
///      a convenience function for paying in plain ETH.
contract Market is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ------------------------------------------------------------------
    // Types
    // ------------------------------------------------------------------

    enum OrderStatus {
        Open,
        Filled,
        Cancelled
    }

    /// @dev Field order is chosen so farmer + createdAt + status share one storage slot.
    struct Order {
        uint256 id; // Same as the mapping key; kept for easy reading.
        uint256 amount; // Base token amount, in the base token's smallest unit.
        uint256 price; // Whole quote units per 1 whole base unit, e.g. 2500.
        address farmer; // The seller.
        uint40 createdAt; // Block timestamp when placed.
        OrderStatus status;
    }

    // ------------------------------------------------------------------
    // Settings (fixed forever at deploy)
    // ------------------------------------------------------------------

    /// @notice Sanity bounds on the cancel lock, so a deploy can't make a market
    ///         that is either pointless (no lock) or a trap (a year-long lock).
    uint256 public constant MIN_CANCEL_LOCK = 24 hours;
    uint256 public constant MAX_CANCEL_LOCK = 7 days;

    /// @notice The token the farmer sells (wETH, wBTC, ...).
    IERC20 public immutable baseToken;
    /// @notice The token the buyer pays with (DAI, USDC, USDT, ...).
    IERC20 public immutable quoteToken;

    uint8 public immutable baseDecimals;
    uint8 public immutable quoteDecimals;

    /// @notice cost = amount * price * scaleMul / scaleDiv.
    ///         Exactly one of these is always 1, so there is at most one multiply
    ///         and at most one divide. See _costOf for why the divide never rounds.
    uint256 public immutable scaleMul;
    uint256 public immutable scaleDiv;

    /// @notice Amounts must be a whole multiple of this, in the base token's smallest unit.
    uint256 public immutable amountStep;

    /// @notice How long a farmer must wait before they may cancel.
    uint256 public immutable cancelLock;

    // ------------------------------------------------------------------
    // Storage
    // ------------------------------------------------------------------

    mapping(uint256 => Order) private _orders;
    uint256 public nextOrderId;

    // ------------------------------------------------------------------
    // Events (the public fill history)
    // ------------------------------------------------------------------

    event OrderPlaced(uint256 indexed id, address indexed farmer, uint256 amount, uint256 price, uint256 createdAt);
    event OrderFilled(
        uint256 indexed id,
        address indexed farmer,
        address indexed buyer,
        uint256 amount,
        uint256 price,
        uint256 cost,
        uint256 filledAt
    );
    event OrderCancelled(uint256 indexed id, address indexed farmer);

    // ------------------------------------------------------------------
    // Errors
    // ------------------------------------------------------------------

    error ZeroAddress();
    error SameToken();
    error DecimalsOutOfRange();
    error DecimalsMismatch(address token, uint8 expected, uint256 reported);
    error InvalidStep();
    error StepWouldRound(uint256 step, uint256 scaleDiv);
    error InvalidCancelLock();
    error InvalidAmount();
    error InvalidPrice();
    error CostTooLarge();
    error OrderNotFound();
    error OrderNotOpen();
    error SelfFill();
    error NotFarmer();
    error StillLocked(uint256 unlocksAt);
    error UnexpectedTransferAmount(uint256 expected, uint256 received);

    // ------------------------------------------------------------------
    // Setup
    // ------------------------------------------------------------------

    /// @param baseToken_      The token being sold (wETH, wBTC, ...).
    /// @param quoteToken_     The token used to pay (DAI, USDC, USDT, ...).
    /// @param baseDecimals_   Decimals of the base token. Cross-checked below.
    /// @param quoteDecimals_  Decimals of the quote token. Cross-checked below.
    /// @param amountStep_     Order sizes must be a multiple of this, e.g. 0.01 ether.
    /// @param cancelLock_     Anti-spoofing delay before a farmer may cancel, e.g. 24 hours.
    constructor(
        IERC20 baseToken_,
        IERC20 quoteToken_,
        uint8 baseDecimals_,
        uint8 quoteDecimals_,
        uint256 amountStep_,
        uint256 cancelLock_
    ) {
        if (address(baseToken_) == address(0) || address(quoteToken_) == address(0)) {
            revert ZeroAddress();
        }
        if (address(baseToken_) == address(quoteToken_)) revert SameToken();

        // 10**36 is already far past anything real; this keeps the scale factors sane.
        if (baseDecimals_ > 36 || quoteDecimals_ > 36) {
            revert DecimalsOutOfRange();
        }

        // Deploy-time guard against a fat-fingered decimals argument.
        _checkReportedDecimals(address(baseToken_), baseDecimals_);
        _checkReportedDecimals(address(quoteToken_), quoteDecimals_);

        // Work out the scale factors. Exactly one of them ends up as 1.
        uint256 mul = 1;
        uint256 div = 1;
        if (quoteDecimals_ >= baseDecimals_) {
            mul = 10 ** uint256(quoteDecimals_ - baseDecimals_);
        } else {
            div = 10 ** uint256(baseDecimals_ - quoteDecimals_);
        }

        if (amountStep_ == 0) revert InvalidStep();

        // THE IMPORTANT CHECK.
        // Every valid amount is k * amountStep. So every cost is
        //     k * amountStep * price * mul / div.
        // If div divides amountStep exactly, the remainder is always zero,
        // for every k and every price. No rounding, ever. If it doesn't divide
        // exactly, this market would quietly lose dust on some trades, so we
        // refuse to exist at all.
        if (amountStep_ % div != 0) revert StepWouldRound(amountStep_, div);

        if (cancelLock_ < MIN_CANCEL_LOCK || cancelLock_ > MAX_CANCEL_LOCK) {
            revert InvalidCancelLock();
        }

        baseToken = baseToken_;
        quoteToken = quoteToken_;
        baseDecimals = baseDecimals_;
        quoteDecimals = quoteDecimals_;
        scaleMul = mul;
        scaleDiv = div;
        amountStep = amountStep_;
        cancelLock = cancelLock_;
    }

    // ------------------------------------------------------------------
    // Placing orders
    // ------------------------------------------------------------------

    /// @notice Place an order with base tokens you already hold. Approve this contract first.
    /// @param amount Base token amount, in its smallest unit. Multiple of amountStep.
    /// @param price  Whole quote units per 1 whole base unit.
    function placeOrder(uint256 amount, uint256 price) external nonReentrant returns (uint256 id) {
        _checkOrder(amount, price);

        // Measure what actually arrived. A fee-on-transfer or rebasing token would
        // deliver less than `amount`, which would leave the contract short later.
        // We refuse those tokens here rather than discover the shortfall at cancel time.
        uint256 balanceBefore = baseToken.balanceOf(address(this));
        baseToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = baseToken.balanceOf(address(this)) - balanceBefore;
        if (received != amount) {
            revert UnexpectedTransferAmount(amount, received);
        }

        id = _createOrder(msg.sender, amount, price);
    }

    // ------------------------------------------------------------------
    // Filling and cancelling
    // ------------------------------------------------------------------

    /// @notice Buy a whole order. Approve this contract for costOf(id) quote tokens first.
    function fill(uint256 id) external nonReentrant {
        Order storage order = _openOrder(id);

        if (msg.sender == order.farmer) revert SelfFill();

        // 1. Update state first, so a call-back can't fill the same order twice.
        order.status = OrderStatus.Filled;

        address farmer = order.farmer;
        uint256 amount = order.amount;
        uint256 price = order.price;
        uint256 cost = _costOf(amount, price);

        emit OrderFilled(id, farmer, msg.sender, amount, price, cost, block.timestamp);

        // 2. Then move tokens. The payment goes straight from buyer to farmer.
        quoteToken.safeTransferFrom(msg.sender, farmer, cost);
        baseToken.safeTransfer(msg.sender, amount);
    }

    /// @notice Take back an unfilled order. Only the farmer, and only after cancelLock.
    function cancel(uint256 id) external nonReentrant {
        Order storage order = _openOrder(id);
        if (msg.sender != order.farmer) revert NotFarmer();

        uint256 unlocksAt = uint256(order.createdAt) + cancelLock;
        if (block.timestamp < unlocksAt) revert StillLocked(unlocksAt);

        order.status = OrderStatus.Cancelled;
        emit OrderCancelled(id, order.farmer);

        baseToken.safeTransfer(order.farmer, order.amount);
    }

    // ------------------------------------------------------------------
    // Reading
    // ------------------------------------------------------------------

    function getOrder(uint256 id) external view returns (Order memory) {
        if (id >= nextOrderId) revert OrderNotFound();
        return _orders[id];
    }

    /// @notice How much quote token (smallest unit) a buyer pays for an order.
    function costOf(uint256 id) external view returns (uint256) {
        if (id >= nextOrderId) revert OrderNotFound();
        Order storage order = _orders[id];
        return _costOf(order.amount, order.price);
    }

    /// @notice Price an order before placing it, so the frontend can show the exact number.
    function quoteCost(uint256 amount, uint256 price) external view returns (uint256) {
        _checkOrder(amount, price);
        return _costOf(amount, price);
    }

    // ------------------------------------------------------------------
    // Internal helpers
    // ------------------------------------------------------------------

    /// @dev cost = amount * price * scaleMul / scaleDiv.
    ///      Example, wETH/DAI (18 and 18): scaleMul = 1, scaleDiv = 1.
    ///          0.5e18 * 2500 = 1250e18          = 1,250 DAI
    ///      Example, wETH/USDC (18 and 6): scaleMul = 1, scaleDiv = 1e12.
    ///          0.5e18 * 2500 / 1e12 = 1250e6    = 1,250 USDC
    ///      The divide is exact for every valid order, because the constructor
    ///      refused to deploy unless scaleDiv divides amountStep exactly.
    function _costOf(uint256 amount, uint256 price) internal view returns (uint256) {
        return (amount * price * scaleMul) / scaleDiv;
    }

    /// @dev Validates an order and guarantees the cost arithmetic can never overflow.
    ///      This matters because an order that is placed but un-fillable would lock
    ///      the farmer's tokens until the cancel window opens.
    function _checkOrder(uint256 amount, uint256 price) internal view {
        if (amount == 0 || amount % amountStep != 0) revert InvalidAmount();
        if (price == 0) revert InvalidPrice();
        if (price > type(uint256).max / amount) revert CostTooLarge();
        uint256 gross = amount * price;
        if (gross > type(uint256).max / scaleMul) revert CostTooLarge();
    }

    function _createOrder(address farmer, uint256 amount, uint256 price) internal returns (uint256 id) {
        id = nextOrderId++;
        _orders[id] = Order({
            id: id,
            amount: amount,
            price: price,
            farmer: farmer,
            createdAt: uint40(block.timestamp),
            status: OrderStatus.Open
        });
        emit OrderPlaced(id, farmer, amount, price, block.timestamp);
    }

    function _openOrder(uint256 id) private view returns (Order storage order) {
        if (id >= nextOrderId) revert OrderNotFound();
        order = _orders[id];
        if (order.status != OrderStatus.Open) revert OrderNotOpen();
    }

    /// @dev Ask the token what its decimals are and compare with what the deployer said.
    ///      decimals() is optional in ERC-20, and USDT declares it as uint256 rather than
    ///      uint8, so we use a low-level call and read 32 bytes. A token that doesn't
    ///      answer is tolerated; a token that answers differently is rejected.
    function _checkReportedDecimals(address token, uint8 expected) private view {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSignature("decimals()"));
        if (ok && data.length >= 32) {
            uint256 reported = abi.decode(data, (uint256));
            if (reported != expected) {
                revert DecimalsMismatch(token, expected, reported);
            }
        }
    }

    // No receive() or fallback(): plain ETH sent directly is rejected.
}
