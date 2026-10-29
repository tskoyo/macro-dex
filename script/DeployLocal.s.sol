// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {WethMarket} from "../src/WethMarket.sol";
import {MockWETH, MockToken} from "../src/Mocks.sol";

/// @notice LOCAL ONLY. Deploys mocks + WethMarket to anvil, funds test accounts with DAI,
///         and writes addresses to ui/deployments.json for the UI.
contract DeployLocal is Script {
    function run() public {
        vm.startBroadcast();

        MockWETH weth = new MockWETH();
        MockToken dai = new MockToken("Dai Stablecoin (mock)", "DAI", 18);
        WethMarket market = new WethMarket(weth, dai, 18, 0.01 ether);

        // Give the first 5 anvil accounts 1,000,000 DAI each.
        address[5] memory accounts = [
            0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            0x70997970C51812dc3A010C7d01b50e0d17dc79C8,
            0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC,
            0x90F79bf6EB2c4f870365E785982E1f101E93b906,
            0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65
        ];
        for (uint256 i; i < accounts.length; i++) {
            dai.mint(accounts[i], 1_000_000 ether);
        }

        vm.stopBroadcast();

        string memory json = "deployments";
        vm.serializeAddress(json, "weth", address(weth));
        vm.serializeAddress(json, "dai", address(dai));
        string memory out = vm.serializeAddress(json, "market", address(market));
        vm.writeJson(out, "./ui/deployments.json");

        console.log("MockWETH  ", address(weth));
        console.log("MockDAI   ", address(dai));
        console.log("WethMarket", address(market));
    }
}
