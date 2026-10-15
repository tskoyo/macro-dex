// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IERC20Errors
} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {FarmersMarket, IWETH} from "../src/FarmersMarket.sol";
import {MockWETH, MockDAI} from "../src/Mocks.sol";

/// @dev Stablecoin with the wrong decimals, for the constructor check.
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin (mock)", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract FarmersMarketTest is Test {
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

    uint256 constant CAP = 10 ether;
    uint256 constant PRICE = 3000;

    MockWETH weth;
    MockDAI dai;
    FarmersMarket market;

    address farmer = makeAddr("farmer");
    address buyer = makeAddr("buyer");
    address stranger = makeAddr("stranger");
    address bot = makeAddr("bot");

    function setUp() public {
        weth = new MockWETH();
        dai = new MockDAI();
        market = new FarmersMarket(IWETH(address(weth)), dai, CAP);

        vm.deal(farmer, 100 ether);
        vm.deal(buyer, 100 ether);
    }

    function _placeETH(
        uint256 amount,
        uint256 price
    ) internal returns (uint256 id) {
        vm.prank(farmer);
        id = market.placeOrderETH{value: amount}(price);
    }

    function _wrapAndApprove(address who, uint256 amount) internal {
        vm.deal(who, who.balance + amount);
        vm.startPrank(who);
        weth.deposit{value: amount}();
        weth.approve(address(market), amount);
        vm.stopPrank();
    }

    function _fundDai(address who, uint256 amount) internal {
        dai.mint(who, amount);
        vm.prank(who);
        dai.approve(address(market), amount);
    }

    function _status(
        uint256 id
    ) internal view returns (FarmersMarket.OrderStatus) {
        return market.getOrder(id).status;
    }

    function test_constructor_setsImmutables() public view {
        assertEq(address(market.weth()), address(weth));
        assertEq(address(market.stablecoin()), address(dai));
        assertEq(market.maxOrderAmount(), CAP);
        assertEq(market.nextOrderId(), 0);
    }

    function test_constructor_revertsOnZeroWeth() public {
        vm.expectRevert(FarmersMarket.ZeroAddress.selector);
        new FarmersMarket(IWETH(address(0)), dai, CAP);
    }

    function test_constructor_revertsOnZeroStablecoin() public {
        vm.expectRevert(FarmersMarket.ZeroAddress.selector);
        new FarmersMarket(IWETH(address(weth)), IERC20(address(0)), CAP);
    }

    function test_constructor_revertsOnWrongDecimals() public {
        MockUSDC usdc = new MockUSDC();
        vm.expectRevert(FarmersMarket.WrongDecimals.selector);
        new FarmersMarket(IWETH(address(weth)), usdc, CAP);
    }

    function test_constructor_revertsWhenCapBelowStep() public {
        vm.expectRevert(FarmersMarket.InvalidCap.selector);
        new FarmersMarket(IWETH(address(weth)), dai, 0);

        vm.expectRevert(FarmersMarket.InvalidCap.selector);
        new FarmersMarket(IWETH(address(weth)), dai, 0.01 ether - 1);
    }

    function test_constructor_revertsWhenCapNotMultipleOfStep() public {
        vm.expectRevert(FarmersMarket.InvalidCap.selector);
        new FarmersMarket(IWETH(address(weth)), dai, 1.005 ether);
    }

    function test_constructor_acceptsCapEqualToStep() public {
        FarmersMarket m = new FarmersMarket(
            IWETH(address(weth)),
            dai,
            0.01 ether
        );
        assertEq(m.maxOrderAmount(), 0.01 ether);
    }

    function test_placeOrderETH_wrapsEthIntoWeth() public {
        uint256 farmerEthBefore = farmer.balance;

        uint256 id = _placeETH(1 ether, PRICE);

        assertEq(farmer.balance, farmerEthBefore - 1 ether, "farmer ETH spent");
        assertEq(address(market).balance, 0, "market holds no raw ETH");
        assertEq(address(weth).balance, 1 ether, "ETH sits in WETH contract");
        assertEq(weth.balanceOf(address(market)), 1 ether, "market holds WETH");
        assertEq(weth.balanceOf(farmer), 0, "farmer gets no WETH");

        FarmersMarket.Order memory o = market.getOrder(id);
        assertEq(o.id, 0);
        assertEq(o.amount, 1 ether);
        assertEq(o.price, PRICE);
        assertEq(o.farmer, farmer);
        assertEq(o.createdAt, block.timestamp);
        assertEq(uint8(o.status), uint8(FarmersMarket.OrderStatus.Open));
        assertEq(market.nextOrderId(), 1);
    }

    function test_placeOrderETH_emitsOrderPlaced() public {
        vm.expectEmit(address(market));
        emit OrderPlaced(0, farmer, 1 ether, PRICE, block.timestamp);
        _placeETH(1 ether, PRICE);
    }

    function test_placeOrderETH_incrementsIds() public {
        assertEq(_placeETH(1 ether, PRICE), 0);
        assertEq(_placeETH(2 ether, PRICE), 1);
        assertEq(market.nextOrderId(), 2);
    }

    function test_placeOrderETH_acceptsAmountEqualToCap() public {
        _placeETH(CAP, PRICE);
        assertEq(market.getOrder(0).amount, CAP);
    }

    function test_placeOrderETH_revertsOnZeroAmount() public {
        vm.expectRevert(FarmersMarket.InvalidAmount.selector);
        _placeETH(0, PRICE);
    }

    function test_placeOrderETH_revertsWhenAmountNotMultipleOfStep() public {
        vm.expectRevert(FarmersMarket.InvalidAmount.selector);
        _placeETH(0.015 ether, PRICE);
    }

    function test_placeOrderETH_revertsWhenAmountAboveCap() public {
        vm.expectRevert(FarmersMarket.AmountAboveCap.selector);
        _placeETH(CAP + 0.01 ether, PRICE);
    }

    function test_placeOrderETH_revertsOnZeroPrice() public {
        vm.expectRevert(FarmersMarket.InvalidPrice.selector);
        _placeETH(1 ether, 0);
    }

    function test_placeOrderETH_revertsWhenCostWouldOverflow() public {
        uint256 amount = 1 ether;
        vm.expectRevert(FarmersMarket.InvalidPrice.selector);
        _placeETH(amount, type(uint256).max / amount + 1);
    }

    function test_placeOrderETH_acceptsLargestNonOverflowingPrice() public {
        uint256 amount = 1 ether;
        uint256 id = _placeETH(amount, type(uint256).max / amount);
        assertEq(market.costOf(id), amount * (type(uint256).max / amount));
    }

    function testFuzz_placeOrderETH_validAmounts(uint256 steps) public {
        steps = bound(steps, 1, CAP / market.AMOUNT_STEP());
        uint256 amount = steps * market.AMOUNT_STEP();
        vm.deal(farmer, amount);

        uint256 id = _placeETH(amount, PRICE);

        assertEq(weth.balanceOf(address(market)), amount);
        assertEq(market.costOf(id), amount * PRICE);
    }

    function test_rawEthTransferIsRejected() public {
        vm.prank(farmer);
        (bool ok, ) = address(market).call{value: 1 ether}("");
        assertFalse(ok);
    }

    function test_placeOrderWETH_pullsWeth() public {
        _wrapAndApprove(farmer, 1 ether);

        vm.prank(farmer);
        uint256 id = market.placeOrderWETH(1 ether, PRICE);

        assertEq(weth.balanceOf(farmer), 0);
        assertEq(weth.balanceOf(address(market)), 1 ether);
        assertEq(market.getOrder(id).farmer, farmer);
        assertEq(market.getOrder(id).amount, 1 ether);
    }

    function test_placeOrderWETH_emitsOrderPlaced() public {
        _wrapAndApprove(farmer, 1 ether);

        vm.expectEmit(address(market));
        emit OrderPlaced(0, farmer, 1 ether, PRICE, block.timestamp);
        vm.prank(farmer);
        market.placeOrderWETH(1 ether, PRICE);
    }

    function test_placeOrderWETH_revertsOnZeroAmount() public {
        vm.expectRevert(FarmersMarket.InvalidAmount.selector);
        vm.prank(farmer);
        market.placeOrderWETH(0, PRICE);
    }

    function test_placeOrderWETH_revertsWhenAmountNotMultipleOfStep() public {
        _wrapAndApprove(farmer, 1 ether);
        vm.expectRevert(FarmersMarket.InvalidAmount.selector);
        vm.prank(farmer);
        market.placeOrderWETH(0.999 ether, PRICE);
    }

    function test_placeOrderWETH_revertsWhenAmountAboveCap() public {
        _wrapAndApprove(farmer, CAP + 0.01 ether);
        vm.expectRevert(FarmersMarket.AmountAboveCap.selector);
        vm.prank(farmer);
        market.placeOrderWETH(CAP + 0.01 ether, PRICE);
    }

    function test_placeOrderWETH_revertsOnZeroPrice() public {
        _wrapAndApprove(farmer, 1 ether);
        vm.expectRevert(FarmersMarket.InvalidPrice.selector);
        vm.prank(farmer);
        market.placeOrderWETH(1 ether, 0);
    }

    function test_placeOrderWETH_revertsWhenCostWouldOverflow() public {
        _wrapAndApprove(farmer, 1 ether);
        vm.expectRevert(FarmersMarket.InvalidPrice.selector);
        vm.prank(farmer);
        market.placeOrderWETH(1 ether, type(uint256).max / 1 ether + 1);
    }

    function test_placeOrderWETH_revertsWithoutApproval() public {
        vm.prank(farmer);
        weth.deposit{value: 1 ether}();

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(market),
                0,
                1 ether
            )
        );
        vm.prank(farmer);
        market.placeOrderWETH(1 ether, PRICE);
    }

    function test_placeOrderWETH_revertsWithoutBalance() public {
        vm.prank(farmer);
        weth.approve(address(market), 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                farmer,
                0,
                1 ether
            )
        );
        vm.prank(farmer);
        market.placeOrderWETH(1 ether, PRICE);
    }

    function test_fill_swapsTokens() public {
        uint256 id = _placeETH(1 ether, PRICE);
        uint256 cost = market.costOf(id);
        assertEq(cost, 3000 ether, "1 ETH @ 3000 costs 3000 DAI");
        _fundDai(buyer, cost);

        vm.prank(buyer);
        market.fill(id);

        assertEq(dai.balanceOf(farmer), cost, "farmer paid in DAI");
        assertEq(dai.balanceOf(buyer), 0, "buyer spent DAI");
        assertEq(weth.balanceOf(buyer), 1 ether, "buyer received WETH");
        assertEq(weth.balanceOf(address(market)), 0, "market emptied");
        assertEq(uint8(_status(id)), uint8(FarmersMarket.OrderStatus.Filled));
    }

    function test_fill_emitsOrderFilled() public {
        uint256 id = _placeETH(1 ether, PRICE);
        _fundDai(buyer, market.costOf(id));

        vm.expectEmit(address(market));
        emit OrderFilled(id, farmer, buyer, 1 ether, PRICE, block.timestamp);
        vm.prank(buyer);
        market.fill(id);
    }

    function test_fill_revertsOnSelfFill() public {
        uint256 id = _placeETH(1 ether, PRICE);
        _fundDai(farmer, market.costOf(id));

        vm.expectRevert(FarmersMarket.SelfFill.selector);
        vm.prank(farmer);
        market.fill(id);
    }

    function test_fill_revertsOnUnknownOrder() public {
        vm.expectRevert(FarmersMarket.OrderNotFound.selector);
        vm.prank(buyer);
        market.fill(0);
    }

    function test_fill_revertsWhenAlreadyFilled() public {
        uint256 id = _placeETH(1 ether, PRICE);
        _fundDai(buyer, market.costOf(id) * 2);
        vm.prank(buyer);
        market.fill(id);

        vm.expectRevert(FarmersMarket.OrderNotOpen.selector);
        vm.prank(buyer);
        market.fill(id);
    }

    function test_fill_revertsWhenCancelled() public {
        uint256 id = _placeETH(1 ether, PRICE);
        vm.warp(block.timestamp + market.CANCEL_LOCK());
        vm.prank(farmer);
        market.cancel(id);

        _fundDai(buyer, market.costOf(id));
        vm.expectRevert(FarmersMarket.OrderNotOpen.selector);
        vm.prank(buyer);
        market.fill(id);
    }

    function test_fill_revertsWithInsufficientAllowance_andOrderStaysOpen()
        public
    {
        uint256 id = _placeETH(1 ether, PRICE);
        uint256 cost = market.costOf(id);
        dai.mint(buyer, cost);
        vm.prank(buyer);
        dai.approve(address(market), cost - 1);

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
            uint8(FarmersMarket.OrderStatus.Open),
            "status change rolled back"
        );
        assertEq(weth.balanceOf(address(market)), 1 ether);
    }

    function test_fill_revertsWithInsufficientBalance() public {
        uint256 id = _placeETH(1 ether, PRICE);
        uint256 cost = market.costOf(id);
        dai.mint(buyer, cost - 1);
        vm.prank(buyer);
        dai.approve(address(market), cost);

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
        uint256 id = _placeETH(1 ether, PRICE);
        vm.warp(block.timestamp + market.CANCEL_LOCK() + 365 days);
        _fundDai(buyer, market.costOf(id));

        vm.prank(buyer);
        market.fill(id);
        assertEq(uint8(_status(id)), uint8(FarmersMarket.OrderStatus.Filled));
    }

    function test_fill_onlyTouchesItsOwnOrder() public {
        uint256 a = _placeETH(1 ether, PRICE);
        uint256 b = _placeETH(2 ether, PRICE + 1);
        _fundDai(buyer, market.costOf(b));

        vm.prank(buyer);
        market.fill(b);

        assertEq(uint8(_status(a)), uint8(FarmersMarket.OrderStatus.Open));
        assertEq(
            weth.balanceOf(address(market)),
            1 ether,
            "order a's WETH still escrowed"
        );
        assertEq(weth.balanceOf(buyer), 2 ether);
    }

    function test_fill_atCapAndMaxPrice() public {
        uint256 price = type(uint256).max / CAP;
        uint256 id = _placeETH(CAP, price);
        uint256 cost = market.costOf(id);
        _fundDai(buyer, cost);

        vm.prank(buyer);
        market.fill(id);

        assertEq(dai.balanceOf(farmer), cost);
        assertEq(weth.balanceOf(buyer), CAP);
    }

    function test_cancel_revertsIfNotFarmer() public {
        uint256 id = _placeETH(1 ether, PRICE);
        vm.warp(block.timestamp + market.CANCEL_LOCK());

        vm.expectRevert(FarmersMarket.NotFarmer.selector);
        vm.prank(stranger);
        market.cancel(id);
    }

    function test_cancel_revertsWhileLocked() public {
        uint256 id = _placeETH(1 ether, PRICE);
        uint256 unlocksAt = block.timestamp + market.CANCEL_LOCK();

        vm.expectRevert(
            abi.encodeWithSelector(
                FarmersMarket.StillLocked.selector,
                unlocksAt
            )
        );
        vm.prank(farmer);
        market.cancel(id);

        // One second before unlock is still locked.
        vm.warp(unlocksAt - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                FarmersMarket.StillLocked.selector,
                unlocksAt
            )
        );
        vm.prank(farmer);
        market.cancel(id);
    }

    function test_cancel_succeedsExactlyAtUnlock() public {
        uint256 id = _placeETH(1 ether, PRICE);
        vm.warp(block.timestamp + market.CANCEL_LOCK());

        vm.prank(farmer);
        market.cancel(id);
        assertEq(
            uint8(_status(id)),
            uint8(FarmersMarket.OrderStatus.Cancelled)
        );
    }

    function test_cancel_emitsEventAndReturnsWeth() public {
        uint256 id = _placeETH(1 ether, PRICE);
        vm.warp(block.timestamp + market.CANCEL_LOCK());

        vm.expectEmit(address(market));
        emit OrderCancelled(id, farmer);
        vm.prank(farmer);
        market.cancel(id);

        assertEq(
            weth.balanceOf(farmer),
            1 ether,
            "farmer gets WETH back, not ETH"
        );
        assertEq(weth.balanceOf(address(market)), 0);
        assertEq(
            uint8(_status(id)),
            uint8(FarmersMarket.OrderStatus.Cancelled)
        );
    }

    function test_cancel_revertsOnUnknownOrder() public {
        vm.expectRevert(FarmersMarket.OrderNotFound.selector);
        vm.prank(farmer);
        market.cancel(0);
    }

    function test_cancel_revertsWhenAlreadyCancelled() public {
        uint256 id = _placeETH(1 ether, PRICE);
        vm.warp(block.timestamp + market.CANCEL_LOCK());
        vm.prank(farmer);
        market.cancel(id);

        vm.expectRevert(FarmersMarket.OrderNotOpen.selector);
        vm.prank(farmer);
        market.cancel(id);
    }

    function test_cancel_revertsWhenFilled() public {
        uint256 id = _placeETH(1 ether, PRICE);
        _fundDai(buyer, market.costOf(id));
        vm.prank(buyer);
        market.fill(id);

        vm.warp(block.timestamp + market.CANCEL_LOCK());
        vm.expectRevert(FarmersMarket.OrderNotOpen.selector);
        vm.prank(farmer);
        market.cancel(id);
    }

    function test_getOrder_revertsOnUnknownOrder() public {
        vm.expectRevert(FarmersMarket.OrderNotFound.selector);
        market.getOrder(0);
    }

    function test_costOf_revertsOnUnknownOrder() public {
        vm.expectRevert(FarmersMarket.OrderNotFound.selector);
        market.costOf(0);
    }

    function test_FrontRun_LateBuyerFailsAndKeepsFunds() public {
        uint256 id = _placeETH(1 ether, PRICE);
        uint256 cost = market.costOf(id);

        _fundDai(buyer, cost);
        _fundDai(bot, cost);

        vm.prank(bot);
        market.fill(id);

        vm.expectRevert(FarmersMarket.OrderNotOpen.selector);
        vm.prank(buyer);
        market.fill(id);

        assertEq(dai.balanceOf(buyer), cost, "buyer keeps DAI");
        assertEq(
            dai.allowance(buyer, address(market)),
            cost,
            "buyer's approval untouched"
        );
        assertEq(weth.balanceOf(buyer), 0, "buyer gets no WETH");
        assertEq(weth.balanceOf(bot), 1 ether, "bot got the order");
    }

    function test_CancelledMeanwhile_BuyerFailsAndKeepsFunds() public {
        uint256 id = _placeETH(1 ether, PRICE);
        uint256 cost = market.costOf(id);

        _fundDai(buyer, cost);

        vm.warp(block.timestamp + market.CANCEL_LOCK());
        vm.prank(farmer);
        market.cancel(id);

        vm.expectRevert(FarmersMarket.OrderNotOpen.selector);
        vm.prank(buyer);
        market.fill(id);

        assertEq(dai.balanceOf(buyer), cost, "buyer keeps DAI");
        assertEq(
            dai.allowance(buyer, address(market)),
            cost,
            "buyer's approval untouched"
        );
        assertEq(weth.balanceOf(buyer), 0, "buyer gets no WETH");
        assertEq(weth.balanceOf(farmer), 1 ether, "farmer got their WETH back");
    }
}
