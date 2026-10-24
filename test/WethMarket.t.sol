// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Market} from "../src/Market.sol";
import {WethMarket} from "../src/WethMarket.sol";
import {MockWETH, MockToken} from "../src/Mocks.sol";
import {MarketTestBase} from "./MarketTestBase.sol";

/// @notice wETH/DAI (18 → 18). Runs the shared suite, plus WethMarket's plain-ETH entry point.
contract WethMarketTest is MarketTestBase {
    MockWETH weth;
    WethMarket wethMarket;

    function _deploy() internal override {
        baseDecimals = 18;
        quoteDecimals = 18;
        step = 0.01 ether;
        price = 3000;

        weth = new MockWETH();
        quote = new MockToken("Dai Stablecoin (mock)", "DAI", 18);
        wethMarket = new WethMarket(weth, quote, 18, step, LOCK);
        baseToken = weth;
        market = wethMarket;
    }

    function _mintBase(address who, uint256 amount) internal override {
        vm.deal(who, who.balance + amount);
        vm.prank(who);
        weth.deposit{value: amount}();
    }

    function _placeEth(uint256 amount, uint256 price_) internal returns (uint256 id) {
        vm.prank(farmer);
        id = wethMarket.placeOrderEth{value: amount}(price_);
    }

    // ------------------------------------------------------------------
    // Pair-specific numbers
    // ------------------------------------------------------------------

    function test_pair_costInDai() public view {
        assertEq(market.SCALE_MUL(), 1);
        assertEq(market.SCALE_DIV(), 1);
        assertEq(market.quoteCost(1 ether, 3000), 3000 ether, "1 ETH @ 3000 = 3000 DAI");
        assertEq(market.quoteCost(0.01 ether, 3000), 30 ether, "0.01 ETH @ 3000 = 30 DAI");
    }

    function test_constructor_setsWeth() public view {
        assertEq(address(wethMarket.WETH()), address(weth));
    }

    function test_constructor_revertsOnZeroWeth() public {
        vm.expectRevert(Market.ZeroAddress.selector);
        new WethMarket(IERC20(address(0)), quote, 18, step, LOCK);
    }

    // ------------------------------------------------------------------
    // placeOrderEth
    // ------------------------------------------------------------------

    function test_placeOrderETH_wrapsEthIntoWeth() public {
        uint256 farmerEthBefore = farmer.balance;

        uint256 id = _placeEth(1 ether, price);

        assertEq(farmer.balance, farmerEthBefore - 1 ether, "farmer ETH spent");
        assertEq(address(market).balance, 0, "market holds no raw ETH");
        assertEq(address(weth).balance, 1 ether, "ETH sits in WETH contract");
        assertEq(weth.balanceOf(address(market)), 1 ether, "market holds WETH");
        assertEq(weth.balanceOf(farmer), 0, "farmer gets no WETH");

        Market.Order memory o = market.getOrder(id);
        assertEq(o.amount, 1 ether);
        assertEq(o.price, price);
        assertEq(o.farmer, farmer);
        assertEq(uint8(o.status), uint8(Market.OrderStatus.Open));
    }

    function test_placeOrderETH_emitsOrderPlaced() public {
        vm.expectEmit(address(market));
        emit Market.OrderPlaced(0, farmer, 1 ether, price, block.timestamp);
        _placeEth(1 ether, price);
    }

    function test_placeOrderETH_revertsOnZeroAmount() public {
        vm.expectRevert(Market.InvalidAmount.selector);
        _placeEth(0, price);
    }

    function test_placeOrderETH_revertsWhenAmountNotMultipleOfStep() public {
        vm.expectRevert(Market.InvalidAmount.selector);
        _placeEth(0.015 ether, price);
    }

    function test_placeOrderETH_revertsOnZeroPrice() public {
        vm.expectRevert(Market.InvalidPrice.selector);
        _placeEth(1 ether, 0);
    }

    function test_placeOrderETH_revertsWhenCostWouldOverflow() public {
        vm.expectRevert(Market.CostTooLarge.selector);
        _placeEth(1 ether, type(uint256).max / 1 ether + 1);
    }

    function test_placeOrderETH_orderCanBeFilled() public {
        uint256 id = _placeEth(1 ether, price);
        _fundQuote(buyer, market.costOf(id));

        vm.prank(buyer);
        market.fill(id);

        assertEq(weth.balanceOf(buyer), 1 ether);
        assertEq(quote.balanceOf(farmer), 3000 ether);
    }

    function test_cancel_returnsWethNotEth() public {
        uint256 farmerEthBefore = farmer.balance;
        uint256 id = _placeEth(1 ether, price);
        vm.warp(block.timestamp + market.CANCEL_LOCK());

        vm.prank(farmer);
        market.cancel(id);

        assertEq(weth.balanceOf(farmer), 1 ether, "farmer gets WETH back");
        assertEq(farmer.balance, farmerEthBefore - 1 ether, "no raw ETH sent");
    }

    function test_rawEthTransferIsRejected() public {
        vm.prank(farmer);
        (bool ok,) = address(market).call{value: 1 ether}("");
        assertFalse(ok);
    }
}
