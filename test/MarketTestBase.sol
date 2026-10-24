// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IERC20Errors
} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Market} from "../src/Market.sol";
import {MockToken} from "../src/Mocks.sol";

/// @notice Pair-agnostic Market tests. Every test here runs once per concrete pair.
/// @dev A subclass deploys its pair in _deploy() and sets the config fields below.
///      Amounts and prices are never hard-coded: they come from `unit`, `step` and `price`,
///      and expected costs are worked out independently of the contract's scale factors.
abstract contract MarketTestBase is Test {
    uint256 constant LOCK = 24 hours;

    // Pair config, set by the subclass in _deploy().
    IERC20 baseToken;
    MockToken quote;
    Market market;
    uint8 baseDecimals;
    uint8 quoteDecimals;
    uint256 step; // amountStep the market is deployed with
    uint256 price; // a realistic price for the pair, in whole quote units

    /// @dev One whole base token, in its smallest unit (1e18 for wETH, 1e8 for wBTC).
    uint256 unit;

    address farmer = makeAddr("farmer");
    address buyer = makeAddr("buyer");
    address stranger = makeAddr("stranger");
    address bot = makeAddr("bot");

    function setUp() public virtual {
        _deploy();
        unit = 10 ** uint256(baseDecimals);
        vm.deal(farmer, 100 ether);
        vm.deal(buyer, 100 ether);
    }

    /// @dev Deploy the tokens and market, and set every config field above.
    function _deploy() internal virtual;

    /// @dev Give `who` base tokens without approving the market.
    function _mintBase(address who, uint256 amount) internal virtual {
        MockToken(address(baseToken)).mint(who, amount);
    }

    function _mintQuote(address who, uint256 amount) internal {
        quote.mint(who, amount);
    }

    /// @dev Shared deploy for pairs where both sides are plain MockTokens.
    function _deployMockPair(
        string memory baseSymbol,
        uint8 baseDecimals_,
        string memory quoteSymbol,
        uint8 quoteDecimals_,
        uint256 step_,
        uint256 price_
    ) internal {
        baseDecimals = baseDecimals_;
        quoteDecimals = quoteDecimals_;
        step = step_;
        price = price_;
        baseToken = new MockToken(baseSymbol, baseSymbol, baseDecimals_);
        quote = new MockToken(quoteSymbol, quoteSymbol, quoteDecimals_);
        market = new Market(
            baseToken,
            quote,
            baseDecimals_,
            quoteDecimals_,
            step_,
            LOCK
        );
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function createOrder(
        uint256 amount,
        uint256 price_
    ) internal returns (uint256 id) {
        _fundBase(farmer, amount);
        vm.prank(farmer);
        id = market.placeOrder(amount, price_);
    }

    function _fundBase(address who, uint256 amount) internal {
        _mintBase(who, amount);
        vm.prank(who);
        baseToken.approve(address(market), amount);
    }

    function _fundQuote(address who, uint256 amount) internal {
        _mintQuote(who, amount);
        vm.prank(who);
        quote.approve(address(market), amount);
    }

    function _status(uint256 id) internal view returns (Market.OrderStatus) {
        return market.getOrder(id).status;
    }

    /// @dev The cost worked out from decimals directly, not from the market's scale factors.
    function _expectedCost(
        uint256 amount,
        uint256 price_
    ) internal view returns (uint256) {
        return
            (amount * price_ * 10 ** uint256(quoteDecimals)) /
            10 ** uint256(baseDecimals);
    }

    // ------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------

    function test_constructor_setsImmutables() public view {
        assertEq(address(market.baseToken()), address(baseToken));
        assertEq(address(market.quoteToken()), address(quote));
        assertEq(market.baseDecimals(), baseDecimals);
        assertEq(market.quoteDecimals(), quoteDecimals);
        assertEq(market.amountStep(), step);
        assertEq(market.cancelLock(), LOCK);
        assertEq(market.nextOrderId(), 0);

        if (quoteDecimals >= baseDecimals) {
            assertEq(
                market.scaleMul(),
                10 ** uint256(quoteDecimals - baseDecimals)
            );
            assertEq(market.scaleDiv(), 1);
        } else {
            assertEq(market.scaleMul(), 1);
            assertEq(
                market.scaleDiv(),
                10 ** uint256(baseDecimals - quoteDecimals)
            );
        }
    }

    function test_constructor_revertsOnZeroBase() public {
        vm.expectRevert(Market.ZeroAddress.selector);
        new Market(
            IERC20(address(0)),
            quote,
            baseDecimals,
            quoteDecimals,
            step,
            LOCK
        );
    }

    function test_constructor_revertsOnZeroQuote() public {
        vm.expectRevert(Market.ZeroAddress.selector);
        new Market(
            baseToken,
            IERC20(address(0)),
            baseDecimals,
            quoteDecimals,
            step,
            LOCK
        );
    }

    function test_constructor_revertsOnSameToken() public {
        vm.expectRevert(Market.SameToken.selector);
        new Market(
            baseToken,
            baseToken,
            baseDecimals,
            baseDecimals,
            step,
            LOCK
        );
    }

    function test_constructor_revertsOnWrongBaseDecimals() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Market.DecimalsMismatch.selector,
                address(baseToken),
                baseDecimals + 1,
                baseDecimals
            )
        );
        new Market(
            baseToken,
            quote,
            baseDecimals + 1,
            quoteDecimals,
            step,
            LOCK
        );
    }

    function test_constructor_revertsOnWrongQuoteDecimals() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Market.DecimalsMismatch.selector,
                address(quote),
                quoteDecimals + 1,
                quoteDecimals
            )
        );
        new Market(
            baseToken,
            quote,
            baseDecimals,
            quoteDecimals + 1,
            step,
            LOCK
        );
    }

    function test_constructor_revertsOnZeroStep() public {
        vm.expectRevert(Market.InvalidStep.selector);
        new Market(baseToken, quote, baseDecimals, quoteDecimals, 0, LOCK);
    }

    function test_constructor_revertsOnCancelLockOutOfRange() public {
        uint256 minLock = market.MIN_CANCEL_LOCK();
        uint256 maxLock = market.MAX_CANCEL_LOCK();

        vm.expectRevert(Market.InvalidCancelLock.selector);
        new Market(
            baseToken,
            quote,
            baseDecimals,
            quoteDecimals,
            step,
            minLock - 1
        );

        vm.expectRevert(Market.InvalidCancelLock.selector);
        new Market(
            baseToken,
            quote,
            baseDecimals,
            quoteDecimals,
            step,
            maxLock + 1
        );
    }

    // ------------------------------------------------------------------
    // Placing orders
    // ------------------------------------------------------------------

    function test_placeOrder_pullsBase() public {
        uint256 id = createOrder(unit, price);

        assertEq(baseToken.balanceOf(farmer), 0);
        assertEq(baseToken.balanceOf(address(market)), unit);

        Market.Order memory o = market.getOrder(id);
        assertEq(o.id, 0);
        assertEq(o.amount, unit);
        assertEq(o.price, price);
        assertEq(o.farmer, farmer);
        assertEq(o.createdAt, block.timestamp);
        assertEq(uint8(o.status), uint8(Market.OrderStatus.Open));
        assertEq(market.nextOrderId(), 1);
    }

    function test_placeOrder_emitsOrderPlaced() public {
        _fundBase(farmer, unit);

        vm.expectEmit(address(market));
        emit Market.OrderPlaced(0, farmer, unit, price, block.timestamp);
        vm.prank(farmer);
        market.placeOrder(unit, price);
    }

    function test_placeOrder_incrementsIds() public {
        assertEq(createOrder(unit, price), 0);
        assertEq(createOrder(2 * unit, price), 1);
        assertEq(market.nextOrderId(), 2);
    }

    function test_placeOrder_acceptsSmallestStep() public {
        uint256 id = createOrder(step, price);
        assertEq(market.getOrder(id).amount, step);
        assertEq(market.costOf(id), _expectedCost(step, price));
    }

    function test_placeOrder_revertsOnZeroAmount() public {
        vm.expectRevert(Market.InvalidAmount.selector);
        vm.prank(farmer);
        market.placeOrder(0, price);
    }

    function test_placeOrder_revertsWhenAmountNotMultipleOfStep() public {
        _fundBase(farmer, unit + 1);
        vm.expectRevert(Market.InvalidAmount.selector);
        vm.prank(farmer);
        market.placeOrder(unit + 1, price);
    }

    function test_placeOrder_revertsOnZeroPrice() public {
        _fundBase(farmer, unit);
        vm.expectRevert(Market.InvalidPrice.selector);
        vm.prank(farmer);
        market.placeOrder(unit, 0);
    }

    function test_placeOrder_largestNonOverflowingPrice() public {
        uint256 maxPrice = type(uint256).max / market.scaleMul() / unit;

        uint256 id = createOrder(unit, maxPrice);
        assertEq(
            market.costOf(id),
            (unit * maxPrice * market.scaleMul()) / market.scaleDiv()
        );

        _fundBase(farmer, unit);
        vm.expectRevert(Market.CostTooLarge.selector);
        vm.prank(farmer);
        market.placeOrder(unit, maxPrice + 1);
    }

    function test_placeOrder_revertsWithoutApproval() public {
        _mintBase(farmer, unit);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(market),
                0,
                unit
            )
        );
        vm.prank(farmer);
        market.placeOrder(unit, price);
    }

    function test_placeOrder_revertsWithoutBalance() public {
        vm.prank(farmer);
        baseToken.approve(address(market), unit);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                farmer,
                0,
                unit
            )
        );
        vm.prank(farmer);
        market.placeOrder(unit, price);
    }

    function testFuzz_placeOrder_validAmounts(uint256 steps) public {
        steps = bound(steps, 1, 10_000);
        uint256 amount = steps * step;

        uint256 id = createOrder(amount, price);

        assertEq(baseToken.balanceOf(address(market)), amount);
        assertEq(market.costOf(id), _expectedCost(amount, price));
    }

    /// @dev The core rounding claim: for every valid order the divide is exact.
    function testFuzz_costIsExact(uint256 steps, uint256 price_) public view {
        steps = bound(steps, 1, 1_000_000);
        price_ = bound(price_, 1, 1e12);
        uint256 amount = steps * step;

        uint256 cost = market.quoteCost(amount, price_);
        assertEq(
            cost * 10 ** uint256(baseDecimals),
            amount * price_ * 10 ** uint256(quoteDecimals),
            "no dust lost"
        );
    }

    // ------------------------------------------------------------------
    // Reading
    // ------------------------------------------------------------------

    function test_quoteCost_matchesCostOf() public {
        uint256 amount = unit + unit / 2;
        uint256 quoted = market.quoteCost(amount, price);
        uint256 id = createOrder(amount, price);
        assertEq(market.costOf(id), quoted);
        assertEq(quoted, _expectedCost(amount, price));
    }

    function test_getOrder_revertsOnUnknownOrder() public {
        vm.expectRevert(Market.OrderNotFound.selector);
        market.getOrder(0);
    }

    function test_costOf_revertsOnUnknownOrder() public {
        vm.expectRevert(Market.OrderNotFound.selector);
        market.costOf(0);
    }

    // ------------------------------------------------------------------
    // Filling
    // ------------------------------------------------------------------

    function test_fill_swapsTokens() public {
        uint256 id = createOrder(unit, price);
        uint256 cost = market.costOf(id);
        assertEq(cost, _expectedCost(unit, price));
        _fundQuote(buyer, cost);

        vm.prank(buyer);
        market.fill(id);

        assertEq(quote.balanceOf(farmer), cost, "farmer paid in quote");
        assertEq(quote.balanceOf(buyer), 0, "buyer spent quote");
        assertEq(baseToken.balanceOf(buyer), unit, "buyer received base");
        assertEq(baseToken.balanceOf(address(market)), 0, "market emptied");
        assertEq(uint8(_status(id)), uint8(Market.OrderStatus.Filled));
    }

    function test_fill_emitsOrderFilled() public {
        uint256 id = createOrder(unit, price);
        uint256 cost = market.costOf(id);
        _fundQuote(buyer, cost);

        vm.expectEmit(address(market));
        emit Market.OrderFilled(
            id,
            farmer,
            buyer,
            unit,
            price,
            cost,
            block.timestamp
        );
        vm.prank(buyer);
        market.fill(id);
    }

    function test_fill_revertsOnSelfFill() public {
        uint256 id = createOrder(unit, price);
        _fundQuote(farmer, market.costOf(id));

        vm.expectRevert(Market.SelfFill.selector);
        vm.prank(farmer);
        market.fill(id);
    }

    function test_fill_revertsOnUnknownOrder() public {
        vm.expectRevert(Market.OrderNotFound.selector);
        vm.prank(buyer);
        market.fill(0);
    }

    function test_fill_revertsWhenAlreadyFilled() public {
        uint256 id = createOrder(unit, price);
        _fundQuote(buyer, market.costOf(id) * 2);
        vm.prank(buyer);
        market.fill(id);

        vm.expectRevert(Market.OrderNotOpen.selector);
        vm.prank(buyer);
        market.fill(id);
    }

    function test_fill_revertsWhenCancelled() public {
        uint256 id = createOrder(unit, price);
        vm.warp(block.timestamp + market.cancelLock());
        vm.prank(farmer);
        market.cancel(id);

        _fundQuote(buyer, market.costOf(id));
        vm.expectRevert(Market.OrderNotOpen.selector);
        vm.prank(buyer);
        market.fill(id);
    }

    function test_fill_revertsWithInsufficientAllowance_andOrderStaysOpen()
        public
    {
        uint256 id = createOrder(unit, price);
        uint256 cost = market.costOf(id);
        quote.mint(buyer, cost);
        vm.prank(buyer);
        quote.approve(address(market), cost - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(market),
                cost - 1,
                cost
            )
        );
        vm.prank(buyer);
        market.fill(id);

        assertEq(
            uint8(_status(id)),
            uint8(Market.OrderStatus.Open),
            "status change rolled back"
        );
        assertEq(baseToken.balanceOf(address(market)), unit);
    }

    function test_fill_revertsWithInsufficientBalance() public {
        uint256 id = createOrder(unit, price);
        uint256 cost = market.costOf(id);
        quote.mint(buyer, cost - 1);
        vm.prank(buyer);
        quote.approve(address(market), cost);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                buyer,
                cost - 1,
                cost
            )
        );
        vm.prank(buyer);
        market.fill(id);
    }

    function test_fill_worksAfterCancelLockExpires() public {
        uint256 id = createOrder(unit, price);
        vm.warp(block.timestamp + market.cancelLock() + 365 days);
        _fundQuote(buyer, market.costOf(id));

        vm.prank(buyer);
        market.fill(id);
        assertEq(uint8(_status(id)), uint8(Market.OrderStatus.Filled));
    }

    function test_fill_onlyTouchesItsOwnOrder() public {
        uint256 a = createOrder(unit, price);
        uint256 b = createOrder(2 * unit, price + 1);
        _fundQuote(buyer, market.costOf(b));

        vm.prank(buyer);
        market.fill(b);

        assertEq(uint8(_status(a)), uint8(Market.OrderStatus.Open));
        assertEq(
            baseToken.balanceOf(address(market)),
            unit,
            "order a's base still escrowed"
        );
        assertEq(baseToken.balanceOf(buyer), 2 * unit);
    }

    function test_fill_atMaxPrice() public {
        uint256 amount = 10 * unit;
        uint256 maxPrice = type(uint256).max / market.scaleMul() / amount;
        uint256 id = createOrder(amount, maxPrice);
        uint256 cost = market.costOf(id);
        _fundQuote(buyer, cost);

        vm.prank(buyer);
        market.fill(id);

        assertEq(quote.balanceOf(farmer), cost);
        assertEq(baseToken.balanceOf(buyer), amount);
    }

    // ------------------------------------------------------------------
    // Cancelling
    // ------------------------------------------------------------------

    function test_cancel_revertsIfNotFarmer() public {
        uint256 id = createOrder(unit, price);
        vm.warp(block.timestamp + market.cancelLock());

        vm.expectRevert(Market.NotFarmer.selector);
        vm.prank(stranger);
        market.cancel(id);
    }

    function test_cancel_revertsWhileLocked() public {
        uint256 id = createOrder(unit, price);
        uint256 unlocksAt = block.timestamp + market.cancelLock();

        vm.expectRevert(
            abi.encodeWithSelector(Market.StillLocked.selector, unlocksAt)
        );
        vm.prank(farmer);
        market.cancel(id);

        // One second before unlock is still locked.
        vm.warp(unlocksAt - 1);
        vm.expectRevert(
            abi.encodeWithSelector(Market.StillLocked.selector, unlocksAt)
        );
        vm.prank(farmer);
        market.cancel(id);
    }

    function test_cancel_succeedsExactlyAtUnlock() public {
        uint256 id = createOrder(unit, price);
        vm.warp(block.timestamp + market.cancelLock());

        vm.prank(farmer);
        market.cancel(id);
        assertEq(uint8(_status(id)), uint8(Market.OrderStatus.Cancelled));
    }

    function test_cancel_emitsEventAndReturnsBase() public {
        uint256 id = createOrder(unit, price);
        vm.warp(block.timestamp + market.cancelLock());

        vm.expectEmit(address(market));
        emit Market.OrderCancelled(id, farmer);
        vm.prank(farmer);
        market.cancel(id);

        assertEq(baseToken.balanceOf(farmer), unit, "farmer gets base back");
        assertEq(baseToken.balanceOf(address(market)), 0);
        assertEq(uint8(_status(id)), uint8(Market.OrderStatus.Cancelled));
    }

    function test_cancel_revertsOnUnknownOrder() public {
        vm.expectRevert(Market.OrderNotFound.selector);
        vm.prank(farmer);
        market.cancel(0);
    }

    function test_cancel_revertsWhenAlreadyCancelled() public {
        uint256 id = createOrder(unit, price);
        vm.warp(block.timestamp + market.cancelLock());
        vm.prank(farmer);
        market.cancel(id);

        vm.expectRevert(Market.OrderNotOpen.selector);
        vm.prank(farmer);
        market.cancel(id);
    }

    function test_cancel_revertsWhenFilled() public {
        uint256 id = createOrder(unit, price);
        _fundQuote(buyer, market.costOf(id));
        vm.prank(buyer);
        market.fill(id);

        vm.warp(block.timestamp + market.cancelLock());
        vm.expectRevert(Market.OrderNotOpen.selector);
        vm.prank(farmer);
        market.cancel(id);
    }

    // ------------------------------------------------------------------
    // Races
    // ------------------------------------------------------------------

    function test_FrontRun_LateBuyerFailsAndKeepsFunds() public {
        uint256 id = createOrder(unit, price);
        uint256 cost = market.costOf(id);

        _fundQuote(buyer, cost);
        _fundQuote(bot, cost);

        vm.prank(bot);
        market.fill(id);

        vm.expectRevert(Market.OrderNotOpen.selector);
        vm.prank(buyer);
        market.fill(id);

        assertEq(quote.balanceOf(buyer), cost, "buyer keeps quote");
        assertEq(
            quote.allowance(buyer, address(market)),
            cost,
            "buyer's approval untouched"
        );
        assertEq(baseToken.balanceOf(buyer), 0, "buyer gets no base");
        assertEq(baseToken.balanceOf(bot), unit, "bot got the order");
    }

    function test_CancelledMeanwhile_BuyerFailsAndKeepsFunds() public {
        uint256 id = createOrder(unit, price);
        uint256 cost = market.costOf(id);

        _fundQuote(buyer, cost);

        vm.warp(block.timestamp + market.cancelLock());
        vm.prank(farmer);
        market.cancel(id);

        vm.expectRevert(Market.OrderNotOpen.selector);
        vm.prank(buyer);
        market.fill(id);

        assertEq(quote.balanceOf(buyer), cost, "buyer keeps quote");
        assertEq(
            quote.allowance(buyer, address(market)),
            cost,
            "buyer's approval untouched"
        );
        assertEq(baseToken.balanceOf(buyer), 0, "buyer gets no base");
        assertEq(
            baseToken.balanceOf(farmer),
            unit,
            "farmer got their base back"
        );
    }

    function test_CancelOneSecondBeforeUnlock_FailsSoBuyerCanStillFill()
        public
    {
        uint256 id = createOrder(unit, price);
        uint256 cost = market.costOf(id);

        _fundQuote(buyer, cost);

        vm.warp(block.timestamp + market.cancelLock() - 1);
        vm.prank(farmer);
        vm.expectRevert(
            abi.encodeWithSelector(
                Market.StillLocked.selector,
                block.timestamp + 1
            )
        );
        market.cancel(id);

        vm.prank(buyer);
        market.fill(id);

        assertEq(quote.balanceOf(buyer), 0, "buyer spent quote");
        assertEq(baseToken.balanceOf(buyer), unit, "buyer got base");
    }

    function testFuzz_ManyBuyers_ExactlyOneWinner(
        uint256 n,
        uint256 winner
    ) public {
        n = bound(n, 1, 10);
        winner = bound(winner, 0, n - 1);

        uint256 id = createOrder(unit, price);
        uint256 cost = market.costOf(id);

        for (uint256 i; i < n; ++i) {
            address buyerAddr = address(uint160(i + 1));
            _fundQuote(buyerAddr, cost);
        }

        vm.prank(address(uint160(winner + 1)));
        market.fill(id);

        for (uint256 i; i < n; ++i) {
            address buyerAddr = address(uint160(i + 1));
            if (i == winner) {
                assertEq(baseToken.balanceOf(buyerAddr), unit);
                assertEq(quote.balanceOf(buyerAddr), 0);
            } else {
                assertEq(baseToken.balanceOf(buyerAddr), 0);
                assertEq(quote.balanceOf(buyerAddr), cost);
            }
        }
    }
}
