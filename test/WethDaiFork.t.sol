// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Market} from "../src/Market.sol";
import {WethMarket} from "../src/WethMarket.sol";

interface IWETH9 is IERC20 {
    function deposit() external payable;
}

/// @notice fill() against the real mainnet DAI and wETH contracts, on a fork.
/// @dev Needs MAINNET_RPC_URL. Without it, every test here is skipped so the normal suite still runs.
///      Pinned to a block so results are repeatable and Foundry can cache the fetched state.
contract WethDaiForkTest is Test {
    IWETH9 constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    uint256 constant FORK_BLOCK = 21_000_000;

    uint256 constant LOT_SIZE = 0.01 ether;
    uint256 constant PRICE = 3000; // DAI per wETH
    uint40 constant LOCK = 24 hours;

    WethMarket market;

    address farmer = makeAddr("farmer");
    address buyer = makeAddr("buyer");

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true, "MAINNET_RPC_URL not set");
            return;
        }
        vm.createSelectFork(rpc, FORK_BLOCK);

        market = new WethMarket(WETH, DAI, 18, LOT_SIZE);
        vm.deal(farmer, 100 ether);
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    /// @dev Farmer wraps real ETH through the real wETH contract, then places an order.
    function _placeOrder(uint256 amount, uint256 price) internal returns (uint256 id) {
        vm.startPrank(farmer);
        WETH.deposit{value: amount}();
        WETH.approve(address(market), amount);
        id = market.placeOrder(amount, price, LOCK);
        vm.stopPrank();
    }

    /// @dev Give `who` real DAI (by writing its balance slot) and approve `allowance` to the market.
    function _fundDai(address who, uint256 balance, uint256 allowance) internal {
        deal(address(DAI), who, balance);
        vm.prank(who);
        DAI.approve(address(market), allowance);
    }

    // ------------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------------

    function test_fork_fill_swapsRealTokens() public {
        uint256 amount = 1 ether;
        uint256 id = _placeOrder(amount, PRICE);
        uint256 cost = market.costOf(id);
        assertEq(cost, 3000 ether, "1 wETH @ 3000 = 3000 DAI");
        _fundDai(buyer, cost, cost);

        uint256 daiSupply = DAI.totalSupply();
        uint256 wethSupply = WETH.totalSupply();

        vm.prank(buyer);
        market.fill(id);

        assertEq(DAI.balanceOf(farmer), cost, "farmer paid in DAI");
        assertEq(DAI.balanceOf(buyer), 0, "buyer spent exactly the cost");
        assertEq(DAI.balanceOf(address(market)), 0, "DAI never held by the market");
        assertEq(WETH.balanceOf(buyer), amount, "buyer received wETH");
        assertEq(WETH.balanceOf(address(market)), 0, "market emptied");
        assertEq(DAI.totalSupply(), daiSupply, "no DAI minted or burned");
        assertEq(WETH.totalSupply(), wethSupply, "no wETH minted or burned");
        assertEq(uint8(market.getOrder(id).status), uint8(Market.OrderStatus.Filled));
    }

    function test_fork_fill_oddLotIsExact() public {
        uint256 amount = 0.37 ether; // 37 lots
        uint256 price = 2513;
        uint256 id = _placeOrder(amount, price);
        uint256 cost = market.costOf(id);
        assertEq(cost, 929.81 ether, "0.37 wETH @ 2513 = 929.81 DAI, no rounding");
        _fundDai(buyer, cost, cost);

        vm.prank(buyer);
        market.fill(id);

        assertEq(DAI.balanceOf(farmer), cost);
        assertEq(DAI.balanceOf(buyer), 0);
        assertEq(WETH.balanceOf(buyer), amount);
    }

    function test_fork_fill_emitsOrderFilled() public {
        uint256 id = _placeOrder(1 ether, PRICE);
        uint256 cost = market.costOf(id);
        _fundDai(buyer, cost, cost);

        vm.expectEmit(address(market));
        emit Market.OrderFilled(id, farmer, buyer, 1 ether, PRICE, cost, block.timestamp);
        vm.prank(buyer);
        market.fill(id);
    }

    function test_fork_fill_afterPlaceOrderEth() public {
        vm.prank(farmer);
        uint256 id = market.placeOrderEth{value: 2 ether}(PRICE, LOCK);
        assertEq(WETH.balanceOf(address(market)), 2 ether, "real wETH wrapped and escrowed");

        uint256 cost = market.costOf(id);
        _fundDai(buyer, cost, cost);
        vm.prank(buyer);
        market.fill(id);

        assertEq(DAI.balanceOf(farmer), cost);
        assertEq(WETH.balanceOf(buyer), 2 ether);
        assertEq(WETH.balanceOf(address(market)), 0);
    }

    /// @dev Real DAI reverts with its own string, not OpenZeppelin's custom error.
    function test_fork_fill_revertsOnShortDaiAllowance_andOrderStaysOpen() public {
        uint256 id = _placeOrder(1 ether, PRICE);
        uint256 cost = market.costOf(id);
        _fundDai(buyer, cost, cost - 1);

        vm.expectRevert(bytes("Dai/insufficient-allowance"));
        vm.prank(buyer);
        market.fill(id);

        assertEq(uint8(market.getOrder(id).status), uint8(Market.OrderStatus.Open), "status rolled back");
        assertEq(WETH.balanceOf(address(market)), 1 ether, "wETH still escrowed");
        assertEq(DAI.balanceOf(buyer), cost, "buyer kept their DAI");
    }

    function test_fork_fill_revertsOnShortDaiBalance() public {
        uint256 id = _placeOrder(1 ether, PRICE);
        uint256 cost = market.costOf(id);
        _fundDai(buyer, cost - 1, cost);

        vm.expectRevert(bytes("Dai/insufficient-balance"));
        vm.prank(buyer);
        market.fill(id);

        assertEq(uint8(market.getOrder(id).status), uint8(Market.OrderStatus.Open));
    }
}
