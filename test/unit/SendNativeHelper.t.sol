// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "../base/BaseTest.t.sol";
import { SendNativeHelper } from "src/SendNativeHelper.sol";

contract SendNativeHelperTest is BaseTest {
  uint256 private COST = 0.23e18;

  address private owner = generateAddress("owner", false);
  address private treasury = generateAddress("Treasury", false);
  address private user = generateAddress("user", false);

  SendNativeHelperHarness private underTest;

  function setUp() public {
    underTest = new SendNativeHelperHarness();
  }

  function test_claimFund_givenNoFund_thenReverts() external pranking {
    vm.expectRevert(SendNativeHelper.NotEnough.selector);
    underTest.claimFund();
  }

  function test_claimFund_whenTransferFails_thenReverts() external pranking {
    vm.etch(user, type(FailOnEth).creationCode);

    changePrank(user);
    underTest.exposed_sendNative(user, 1e18, false);

    vm.expectRevert(SendNativeHelper.FailedToSendETH.selector);
    underTest.claimFund();
  }

  function test_claimFund_thenClaims() external pranking {
    changePrank(user);
    uint256 claiming = 9.832e18;
    uint256 balanceBefore = user.balance;

    vm.etch(user, type(FailOnEth).creationCode);

    vm.deal(address(underTest), claiming);
    underTest.exposed_sendNative(user, claiming, false);

    vm.etch(user, "");

    underTest.claimFund();

    assertEq(user.balance - balanceBefore, claiming);
  }

  function test_sendNative_givenRevertOption_thenReverts() external pranking {
    changePrank(user);
    uint256 claiming = 9.832e18;

    vm.etch(user, type(FailOnEth).creationCode);

    vm.expectRevert(SendNativeHelper.FailedToSendETH.selector);
    underTest.exposed_sendNative(user, claiming, true);
  }

  function test_sendNative_givenNoRevertOption_thenStoresWhenReverts() external pranking {
    changePrank(user);
    uint256 claiming = 9.832e18;

    vm.etch(user, type(FailOnEth).creationCode);

    underTest.exposed_sendNative(user, claiming, false);

    assertEq(underTest.getPendingToClaim(user), claiming);
  }

  function test_sendNative_whenNoFails_thenSends() external pranking {
    changePrank(user);
    uint256 claiming = 9.832e18;
    uint256 balanceBefore = user.balance;

    vm.deal(address(underTest), claiming);
    underTest.exposed_sendNative(user, claiming, false);

    assertEq(user.balance - balanceBefore, claiming);
  }

  function test_sendNative_DSADSA_thenSends() external pranking {
    user = address(new BadGuy());

    changePrank(user);
    uint256 claiming = 9.832e18;
    uint256 balanceBefore = user.balance;

    vm.deal(address(underTest), claiming);
    underTest.exposed_sendNative(user, claiming, false);

    assertEq(underTest.getPendingToClaim(user), claiming);

    // assertEq(user.balance - balanceBefore, claiming);
  }
}

contract SendNativeHelperHarness is SendNativeHelper {
  function exposed_sendNative(address _to, uint256 _amount, bool _revertIfFails) external {
    _sendNative(_to, _amount, _revertIfFails);
  }
}

contract FailOnEth {
  receive() external payable {
    revert("No!");
  }
}

contract BadGuy {
  fallback(bytes calldata) external payable returns (bytes memory) {
    assembly {
      revert(0, 1000000000) // (gas: 8937393460516745140)
        // revert(0, 1000000) // (gas: 4_425_389)
        // revert(0, 0) // (gas: 326_511)
    }
  }
}
