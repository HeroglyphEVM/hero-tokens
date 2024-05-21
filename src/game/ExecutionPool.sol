// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IGasPool } from "heroglyph-library/src/ITickerOperator.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract ExecutionPool is IGasPool, Ownable {
  error NoPermission();
  error FailedToSendETH();

  event AccessUpdated(address indexed who, bool isEnable);
  event Paid(address indexed caller, address indexed to, uint256 amount);
  event NativeRetrieved(address indexed to, uint256 amount);

  mapping(address => bool) private accesses;

  modifier onlyAccess() {
    if (!accesses[msg.sender]) revert NoPermission();

    _;
  }

  constructor(address _owner) Ownable(_owner) { }

  function payTo(address _to, uint256 _amount) external onlyAccess {
    (bool success,) = _to.call{ value: _amount }("");

    if (!success) revert FailedToSendETH();

    emit Paid(msg.sender, _to, _amount);
  }

  function setAccessTo(address _to, bool _enable) external onlyOwner {
    accesses[_to] = _enable;

    emit AccessUpdated(_to, _enable);
  }

  function hasAccess(address _who) external view returns (bool) {
    return accesses[_who];
  }

  function retrieveNative(address _to) external onlyOwner {
    uint256 balance = address(this).balance;
    (bool success,) = _to.call{ value: balance }("");
    if (!success) revert FailedToSendETH();

    emit NativeRetrieved(_to, balance);
  }

  receive() external payable { }
}
