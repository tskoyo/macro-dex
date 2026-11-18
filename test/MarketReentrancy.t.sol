// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Market} from "../src/Market.sol";

interface ITokenHook {
    function onTokenReceived() external;
}

/// @notice TEST ONLY. ERC-20 that calls the recipient back on every transfer (like ERC-777 hooks),
///         giving the recipient a chance to re-enter the market mid-fill.
contract HookToken is ERC20 {
    mapping(address => bool) public hooked;

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setHook(address who, bool on) external {
        hooked[who] = on;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (from != address(0) && hooked[to]) ITokenHook(to).onTokenReceived();
    }
}

/// @notice TEST ONLY. Plays buyer or farmer. When a hooked token arrives it runs the queued
///         re-entry calls, catching and recording each revert so the outer call can finish.
contract Attacker is ITokenHook {
    Market public immutable market;
    bytes[] internal _calls;
    bytes[] public results; // revert data of each re-entry attempt ("" = it succeeded)

    constructor(Market market_) {
        market = market_;
    }

    function queue(bytes calldata data) external {
        _calls.push(data);
    }

    function resultCount() external view returns (uint256) {
        return results.length;
    }

    function approve(IERC20 token, uint256 amount) external {
        token.approve(address(market), amount);
    }

    function placeOrder(uint256 amount, uint256 price) external returns (uint256) {
        return market.placeOrder(amount, price, 1 days);
    }

    function fill(uint256 id) external {
        market.fill(id);
    }

    function onTokenReceived() external {
        bytes[] memory calls = _calls;
        delete _calls; // run once
        for (uint256 i = 0; i < calls.length; i++) {
            (bool ok, bytes memory ret) = address(market).call(calls[i]);
            results.push(ok ? bytes("") : ret);
        }
    }
}

/// @notice F2 (MAC-15): fill() cannot be re-entered from either token transfer.
contract MarketReentrancyTest is Test {
    uint256 constant LOT = 0.01 ether;
    uint256 constant PRICE = 2500;
    uint256 constant AMOUNT = 1 ether;
    uint256 constant COST = AMOUNT * PRICE; // 18/18 decimals: no scaling

    HookToken base; // plays wETH
    HookToken quote; // plays DAI
    Market market;
    address farmer = makeAddr("farmer");
    address buyer = makeAddr("buyer");

    bytes REENTRANT = abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);

    function setUp() public {
        base = new HookToken("Hook wETH", "hWETH");
        quote = new HookToken("Hook DAI", "hDAI");
        market = new Market(base, quote, 18, 18, LOT);
    }

    function _place(address who, uint256 amount) internal returns (uint256 id) {
        base.mint(who, amount);
        vm.startPrank(who);
        base.approve(address(market), amount);
        id = market.placeOrder(amount, PRICE, 1 days);
        vm.stopPrank();
    }

    function _assertAllBlocked(Attacker a, uint256 expected) internal view {
        assertEq(a.resultCount(), expected, "every re-entry attempt ran");
        for (uint256 i = 0; i < expected; i++) {
            assertEq(a.results(i), REENTRANT, "re-entry was not blocked");
        }
    }

    /// Buyer re-enters while receiving wETH: double-fill, fill of another order,
    /// reclaim and placeOrder are all blocked; the outer fill pays out exactly once.
    function test_fill_buyerReentryOnBaseTransferIsBlocked() public {
        uint256 id = _place(farmer, AMOUNT);
        uint256 other = _place(farmer, AMOUNT);

        Attacker attacker = new Attacker(market);
        quote.mint(address(attacker), 3 * COST);
        attacker.approve(quote, type(uint256).max);
        attacker.approve(base, type(uint256).max);
        base.setHook(address(attacker), true);

        attacker.queue(abi.encodeCall(Market.fill, (id)));
        attacker.queue(abi.encodeCall(Market.fill, (other)));
        attacker.queue(abi.encodeCall(Market.reclaim, (id)));
        attacker.queue(abi.encodeCall(Market.placeOrder, (LOT, PRICE, 1 days)));

        attacker.fill(id);

        _assertAllBlocked(attacker, 4);
        assertEq(base.balanceOf(address(attacker)), AMOUNT, "buyer got wETH once");
        assertEq(quote.balanceOf(farmer), COST, "farmer paid once");
        assertEq(base.balanceOf(address(market)), AMOUNT, "other order still escrowed");
        assertEq(uint8(market.getOrder(id).status), uint8(Market.OrderStatus.Filled));
        assertEq(uint8(market.getOrder(other).status), uint8(Market.OrderStatus.Open));
    }

    /// Farmer re-enters while receiving DAI (before the buyer's wETH has left):
    /// reclaiming the order being filled, or filling it again, is blocked.
    function test_fill_farmerReentryOnQuoteTransferIsBlocked() public {
        Attacker attacker = new Attacker(market);
        base.mint(address(attacker), AMOUNT);
        attacker.approve(base, AMOUNT);
        uint256 id = attacker.placeOrder(AMOUNT, PRICE);
        vm.warp(block.timestamp + 2 days); // reclaim lock passed, so only the guard can stop it

        quote.setHook(address(attacker), true);
        attacker.queue(abi.encodeCall(Market.reclaim, (id)));
        attacker.queue(abi.encodeCall(Market.fill, (id)));

        quote.mint(buyer, COST);
        vm.startPrank(buyer);
        quote.approve(address(market), COST);
        market.fill(id);
        vm.stopPrank();

        _assertAllBlocked(attacker, 2);
        assertEq(base.balanceOf(buyer), AMOUNT, "buyer got wETH");
        assertEq(base.balanceOf(address(attacker)), 0, "farmer could not take wETH back");
        assertEq(quote.balanceOf(address(attacker)), COST, "farmer paid once");
        assertEq(base.balanceOf(address(market)), 0);
    }
}
