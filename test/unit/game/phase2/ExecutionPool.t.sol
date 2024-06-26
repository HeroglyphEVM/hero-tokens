// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "../../../base/BaseTest.t.sol";

import { ExecutionPool } from "src/game/phase2/ExecutionPool.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract ExecutionPoolTest is BaseTest {
  address private owner = generateAddress("Owner");
  address private wallet = generateAddress("Wallet");
  address private operator = generateAddress("operator");

  ExecutionPool private underTest;

  function setUp() external prankAs(owner) {
    underTest = new ExecutionPool(owner);
    underTest.setAccessTo(operator, true);

    vm.deal(address(underTest), 1000e18);
  }

  function test_constructor_thenSetupCorrectly() external {
    underTest = new ExecutionPool(owner);
    assertEq(underTest.owner(), owner);
  }

  function test_payTo_whenNoAccess_thenReverts() external {
    vm.expectRevert(ExecutionPool.NoPermission.selector);
    underTest.payTo(wallet, 0);
  }

  function test_payTo_thenSends() external prankAs(operator) {
    uint256 sending = 12.3e18;
    uint256 balanceBefore = address(underTest).balance;

    expectExactEmit();
    emit ExecutionPool.Paid(operator, wallet, sending);
    underTest.payTo(wallet, sending);

    assertEq(wallet.balance, sending);
    assertEq(balanceBefore - address(underTest).balance, sending);
  }

  function test_setAccessTo_asUser_thenReverts() external prankAs(wallet) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, wallet));
    underTest.setAccessTo(wallet, true);
  }

  function test_setAccessTo_thenUpdateAccess() external prankAs(owner) {
    expectExactEmit();
    emit ExecutionPool.AccessUpdated(wallet, true);
    underTest.setAccessTo(wallet, true);

    assertTrue(underTest.hasAccess(wallet));

    expectExactEmit();
    emit ExecutionPool.AccessUpdated(wallet, false);
    underTest.setAccessTo(wallet, false);

    assertFalse(underTest.hasAccess(wallet));
  }

  function test_retrieveNative_asUser_thenReverts() external prankAs(wallet) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, wallet));
    underTest.retrieveNative(wallet);
  }

  function test_retrieveNative_thenUpdateAccess() external prankAs(owner) {
    uint256 balance = 218.32e18;
    address to = generateAddress();

    vm.deal(address(underTest), balance);

    underTest.retrieveNative(to);

    assertEq(to.balance, balance);
  }
}
