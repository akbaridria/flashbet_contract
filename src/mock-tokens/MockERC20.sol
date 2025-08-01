// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockERC20 is ERC20, Ownable, ERC20Permit {
    uint8 public immutable DECIMALS;

    constructor(address recipient, address initialOwner, string memory name, string memory symbol, uint8 _decimals)
        ERC20(name, symbol)
        Ownable(initialOwner)
        ERC20Permit(name)
    {
        DECIMALS = _decimals;
        _mint(recipient, 10000000 * 10 ** _decimals);
    }

    function mint() public {
        uint256 amount = 100 * 10 ** DECIMALS;
        _mint(msg.sender, amount);
    }

    function decimals() public view override returns (uint8) {
        return DECIMALS;
    }
}
