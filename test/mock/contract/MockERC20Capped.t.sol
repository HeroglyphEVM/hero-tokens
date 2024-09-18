// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { DefaultERC20 } from "./DefaultERC20.t.sol";

contract MockERC20Capped is DefaultERC20 {
  error MaxSupplyReached();

  bool private ignoreLogic;
  uint256 private capped;

  constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 capped_)
    DefaultERC20(name_, symbol_, decimals_)
  {
    capped = capped_ == 0 ? type(uint256).max : capped_;
  }

  function transfer(address to, uint256 amount) public override returns (bool) {
    if (ignoreLogic) return true;

    _transfer(msg.sender, to, amount);

    return true;
  }

  function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
    if (ignoreLogic) return true;

    _transfer(from, to, amount);
    return true;
  }

  function mint(address account, uint256 amount) public override {
    if (capped < totalSupply() + amount) revert MaxSupplyReached();

    super.mint(account, amount);
  }

  function burn(address account, uint256 amount) public override {
    unchecked {
      capped -= amount;
    }

    super.burn(account, amount);
  }

  function changeCapped(uint256 value) external {
    capped = value;
  }

  function setIgnoreLogic(bool status) external {
    ignoreLogic = status;
  }

  function maxSupply() external view returns (uint256) {
    return capped;
  }
}
