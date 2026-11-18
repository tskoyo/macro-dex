// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {WethMarket} from "../src/WethMarket.sol";

/// @notice SEPOLIA. Deploys a WethMarket for WETH/<quote token> and adds it to
///         ui/deployments.sepolia.json, keeping the pairs already listed there.
///
///         make deploy-sepolia QUOTE=0xCaC524BcA292aaade2DF8A05cC58F0a65B1B3bB9   # PYUSD
///         make deploy-sepolia QUOTE=0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238   # USDC (Circle)
///         make deploy-sepolia QUOTE=0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0   # USDT (Aave faucet)
///
///         File format: { "weth": "0x…", "markets": [{ "name": "WETH/USDC", "quote": "0x…", "market": "0x…" }] }
contract DeploySepolia is Script {
    IERC20 constant WETH = IERC20(0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14); // 18 decimals
    uint256 constant LOT_SIZE = 0.01 ether;
    string constant PATH = "./ui/deployments.sepolia.json";
    /// Written during the run; `make deploy-sepolia` moves it over PATH only if the broadcast succeeded.
    string constant NEXT = "./ui/deployments.sepolia.json.next";

    struct Entry {
        string name;
        address quote;
        address market;
    }

    function run(address quote) public {
        require(block.chainid == 11155111, "DeploySepolia: not on Sepolia");
        IERC20Metadata token = IERC20Metadata(quote);
        string memory name = string.concat("WETH/", token.symbol());
        uint8 decimals = token.decimals();

        Entry[] memory existing = _load();
        for (uint256 i; i < existing.length; i++) {
            if (existing[i].quote == quote && existing[i].market.code.length > 0) {
                revert(string.concat(name, " already deployed at ", vm.toString(existing[i].market)));
            }
        }

        vm.startBroadcast();
        WethMarket market = new WethMarket(WETH, IERC20(quote), decimals, LOT_SIZE);
        vm.stopBroadcast();

        // Rewrite the file: keep live markets for other tokens, then append the new one.
        string memory items;
        for (uint256 i; i < existing.length; i++) {
            Entry memory e = existing[i];
            if (e.quote == quote) continue; // stale entry for this token, replaced below
            if (e.market.code.length == 0) {
                console.log("dropping entry with no code on chain:", e.name);
                continue;
            }
            items = string.concat(items, _item(e), ",\n");
        }
        items = string.concat(items, _item(Entry(name, quote, address(market))));
        vm.writeFile(
            NEXT,
            string.concat('{\n  "weth": "', vm.toString(address(WETH)), '",\n  "markets": [\n', items, "\n  ]\n}\n")
        );

        console.log(name, "->", address(market));
    }

    /// Reads the current list. Also accepts the old single-market file ({ weth, quote, market }).
    function _load() internal view returns (Entry[] memory list) {
        if (!vm.exists(PATH)) return list;
        string memory json = vm.readFile(PATH);
        if (vm.keyExistsJson(json, ".markets")) {
            uint256 n;
            while (vm.keyExistsJson(json, string.concat(".markets[", vm.toString(n), "]"))) n++;
            list = new Entry[](n);
            for (uint256 i; i < n; i++) {
                string memory k = string.concat(".markets[", vm.toString(i), "]");
                list[i] = Entry(
                    vm.parseJsonString(json, string.concat(k, ".name")),
                    vm.parseJsonAddress(json, string.concat(k, ".quote")),
                    vm.parseJsonAddress(json, string.concat(k, ".market"))
                );
            }
        } else if (vm.keyExistsJson(json, ".market")) {
            address quote = vm.parseJsonAddress(json, ".quote");
            list = new Entry[](1);
            list[0] = Entry(
                string.concat("WETH/", IERC20Metadata(quote).symbol()), quote, vm.parseJsonAddress(json, ".market")
            );
        }
    }

    function _item(Entry memory e) internal pure returns (string memory) {
        return string.concat(
            '    { "name": "',
            e.name,
            '", "quote": "',
            vm.toString(e.quote),
            '", "market": "',
            vm.toString(e.market),
            '" }'
        );
    }
}
