// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice The one wETH function we need beyond a normal token: wrapping ETH.
interface IWETH is IERC20 {
    function deposit() external payable;
}

/// @title ETH/DAI Farmer's Market (MVP)
/// @notice Farmers lock ETH as wETH at a fixed whole-number stablecoin price.
///         Anyone can buy a whole order at once. The farmer can't cancel for 24 hours.
/// @dev No admin, no fees, no upgrades. Holds only wETH; never sends raw ETH.
contract FarmersMarket is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH;

    enum OrderStatus {
        Open,
        Filled,
        Cancelled
    }

    /// @dev Field order is chosen so farmer + createdAt + status share one storage slot (cheaper gas).
    struct Order {
        uint256 id;
        uint256 amount;
        uint256 price;
        address farmer;
        uint40 createdAt;
        OrderStatus status;
    }

    /// @notice Amounts move in steps of 0.01 ETH.
    uint256 public constant AMOUNT_STEP = 0.01 ether;

    /// @notice Farmers can't cancel during the first 24 hours.
    uint256 public constant CANCEL_LOCK = 24 hours;

    IWETH public immutable weth;
    IERC20 public immutable stablecoin;

    /// @notice Launch cap: the largest amount one order may hold, in wei.
    uint256 public immutable maxOrderAmount;

    mapping(uint256 => Order) private _orders;
    uint256 public nextOrderId;

    event OrderPlaced(
        uint256 indexed id,
        address indexed farmer,
        uint256 amount,
        uint256 price,
        uint256 createdAt
    );
    event OrderFilled(
        uint256 indexed id,
        address indexed farmer,
        address indexed buyer,
        uint256 amount,
        uint256 price,
        uint256 filledAt
    );
    event OrderCancelled(uint256 indexed id, address indexed farmer);

    error ZeroAddress();
    error WrongDecimals();
    error InvalidCap();
    error InvalidAmount();
    error AmountAboveCap();
    error InvalidPrice();
    error OrderNotFound();
    error OrderNotOpen();
    error NotFarmer();
    error StillLocked(uint256 unlocksAt);
    error SelfFill();

    /// @param weth_ The official wETH contract.
    /// @param stablecoin_ DAI or USDS. Must have 18 decimals, like ETH.
    /// @param maxOrderAmount_ Launch cap in wei, e.g. 10 ether. Multiple of 0.01 ETH.
    constructor(IWETH weth_, IERC20 stablecoin_, uint256 maxOrderAmount_) {
        if (address(weth_) == address(0) || address(stablecoin_) == address(0))
            revert ZeroAddress();
        // The cost formula (amount x price) only works if both tokens use 18 decimals.
        if (IERC20Metadata(address(stablecoin_)).decimals() != 18)
            revert WrongDecimals();
        if (maxOrderAmount_ < AMOUNT_STEP || maxOrderAmount_ % AMOUNT_STEP != 0)
            revert InvalidCap();

        weth = weth_;
        stablecoin = stablecoin_;
        maxOrderAmount = maxOrderAmount_;
    }

    /// @notice Place an order by sending plain ETH. The contract wraps it into wETH.
    /// @param price Whole stablecoin units per 1 ETH.
    function placeOrderETH(
        uint256 price
    ) external payable nonReentrant returns (uint256 id) {
        _checkOrder(msg.value, price);
        weth.deposit{value: msg.value}();
        id = _createOrder(msg.value, price);
    }

    /// @notice Place an order with wETH you already hold. Approve this contract first.
    /// @param amount ETH amount in wei.
    /// @param price Whole stablecoin units per 1 ETH.
    function placeOrderWETH(
        uint256 amount,
        uint256 price
    ) external nonReentrant returns (uint256 id) {
        _checkOrder(amount, price);
        weth.safeTransferFrom(msg.sender, address(this), amount);
        id = _createOrder(amount, price);
    }

    /// @notice Buy a whole order. Approve this contract for `amount x price` stablecoin first.
    function fill(uint256 id) external nonReentrant {
        Order storage order = _openOrder(id);

        if (msg.sender == order.farmer) revert SelfFill();

        order.status = OrderStatus.Filled;

        uint256 cost = order.amount * order.price;
        emit OrderFilled(
            id,
            order.farmer,
            msg.sender,
            order.amount,
            order.price,
            block.timestamp
        );

        stablecoin.safeTransferFrom(msg.sender, order.farmer, cost);
        weth.safeTransfer(msg.sender, order.amount);
    }

    /// @notice Take back an unfilled order. Only the farmer, and only after 24 hours.
    function cancel(uint256 id) external nonReentrant {
        Order storage order = _openOrder(id);
        if (msg.sender != order.farmer) revert NotFarmer();

        uint256 unlocksAt = uint256(order.createdAt) + CANCEL_LOCK;
        if (block.timestamp < unlocksAt) revert StillLocked(unlocksAt);

        order.status = OrderStatus.Cancelled;
        emit OrderCancelled(id, order.farmer);

        weth.safeTransfer(order.farmer, order.amount);
    }

    function getOrder(uint256 id) external view returns (Order memory) {
        if (id >= nextOrderId) revert OrderNotFound();
        return _orders[id];
    }

    /// @notice How much stablecoin (smallest unit) a buyer pays for an order.
    function costOf(uint256 id) external view returns (uint256) {
        if (id >= nextOrderId) revert OrderNotFound();
        Order storage order = _orders[id];
        return order.amount * order.price;
    }

    function _checkOrder(uint256 amount, uint256 price) private view {
        if (amount == 0 || amount % AMOUNT_STEP != 0) revert InvalidAmount();
        if (amount > maxOrderAmount) revert AmountAboveCap();
        if (price == 0) revert InvalidPrice();
        // Make sure amount x price can't overflow later, so fill() can never get stuck.
        if (price > type(uint256).max / amount) revert InvalidPrice();
    }

    function _createOrder(
        uint256 amount,
        uint256 price
    ) private returns (uint256 id) {
        id = nextOrderId++;
        _orders[id] = Order({
            id: id,
            amount: amount,
            price: price,
            farmer: msg.sender,
            createdAt: uint40(block.timestamp),
            status: OrderStatus.Open
        });
        emit OrderPlaced(id, msg.sender, amount, price, block.timestamp);
    }

    function _openOrder(uint256 id) private view returns (Order storage order) {
        if (id >= nextOrderId) revert OrderNotFound();
        order = _orders[id];
        if (order.status != OrderStatus.Open) revert OrderNotOpen();
    }

    // No receive() or fallback(): plain ETH sent directly is rejected.
    // ETH only enters through placeOrderETH, and is wrapped immediately.
}
