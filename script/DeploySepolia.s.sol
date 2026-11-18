// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {WethMarket} from "../src/WethMarket.sol";

/// @notice SEPOLIA. Deploys a WethMarket that sells real Sepolia wETH for PYUSD,
///         and writes addresses to ui/deployments.sepolia.json for the UI.
contract DeploySepolia is Script {
    IERC20 constant WETH = IERC20(0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14); // 18 decimals
    IERC20 constant PYUSD = IERC20(0xCaC524BcA292aaade2DF8A05cC58F0a65B1B3bB9); // 6 decimals
    uint8 constant PYUSD_DECIMALS = 6;
    uint256 constant LOT_SIZE = 0.01 ether;

    function run() public {
        require(block.chainid == 11155111, "DeploySepolia: not on Sepolia");

        vm.startBroadcast();
        WethMarket market = new WethMarket(WETH, PYUSD, PYUSD_DECIMALS, LOT_SIZE);
        vm.stopBroadcast();

        string memory json = "deployments";
        vm.serializeAddress(json, "weth", address(WETH));
        vm.serializeAddress(json, "quote", address(PYUSD));
        string memory out = vm.serializeAddress(json, "market", address(market));
        vm.writeJson(out, "./ui/deployments.sepolia.json");

        console.log("WETH      ", address(WETH));
        console.log("PYUSD     ", address(PYUSD));
        console.log("WethMarket", address(market));
    }
}
