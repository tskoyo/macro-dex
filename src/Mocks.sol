// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice TEST ONLY. A fake wETH so we can try FarmersMarket in Remix.
contract MockWETH is ERC20 {
    constructor() ERC20("Wrapped Ether (mock)", "WETH") {}

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "ETH send failed");
    }
}

/// @notice TEST ONLY. A fake DAI with 18 decimals. Anyone can mint, so never use on mainnet.
contract MockDAI is ERC20 {
    constructor() ERC20("Dai (mock)", "DAI") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
