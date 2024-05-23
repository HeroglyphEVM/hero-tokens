// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "../../base/BaseTest.t.sol";

import { GenesisHub, IGenesisHub } from "src/game/GenesisHub.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { MockERC20 } from "test/mock/contract/MockERC20.t.sol";

import { IGenesisToken } from "src/game/interface/IGenesisToken.sol";

contract GenesisHubTest is BaseTest {
  uint256 public constant MAX_DIFFICULTY = 1e18;
  uint256 public constant REDEEM_RATE = 1e18;

  address private owner;
  address private user;
  address private genesisToken;
  MockERC20 inputToken;

  GenesisHub private underTest;

  IGenesisHub.RedeemSettings private DEFAULT_REDEEM;

  function setUp() external {
    _prepareEnvironment();
    vm.mockCall(genesisToken, abi.encodeWithSelector(IGenesisToken.redeem.selector), abi.encode(true));

    underTest = new GenesisHub(owner);

    vm.prank(owner);
    underTest.setRedeemSetting(genesisToken, DEFAULT_REDEEM);
  }

  function _prepareEnvironment() internal {
    owner = generateAddress("Owner");
    user = generateAddress("User");
    genesisToken = generateAddress("GenesisToken");

    inputToken = new MockERC20("A", "A", 18);
    inputToken.mint(user, 100e18);

    DEFAULT_REDEEM = IGenesisHub.RedeemSettings({ tokenInput: address(inputToken), ratePerRedeem: REDEEM_RATE });
  }

  function test_constructor_thenSetups() external {
    underTest = new GenesisHub(owner);
    assertEq(underTest.owner(), owner);

    assertEq(underTest.MAX_DIFFICULTY(), MAX_DIFFICULTY);
  }

  function test_applyDifficulty_thenApplies() external prankAs(owner) {
    uint256 value = 93_212.32e18;
    uint256 difficulty = 0;

    difficulty = 0.25e18;
    underTest.updateGlobalDifficulty(difficulty);
    assertEq(underTest.applyDifficulty(value), Math.mulDiv(value, MAX_DIFFICULTY - difficulty, MAX_DIFFICULTY));

    difficulty = 0.33e18;
    underTest.updateGlobalDifficulty(difficulty);
    assertEq(underTest.applyDifficulty(value), Math.mulDiv(value, MAX_DIFFICULTY - difficulty, MAX_DIFFICULTY));

    difficulty = 0.5e18;
    underTest.updateGlobalDifficulty(difficulty);
    assertEq(underTest.applyDifficulty(value), Math.mulDiv(value, MAX_DIFFICULTY - difficulty, MAX_DIFFICULTY));
    assertEq(underTest.applyDifficulty(value), value / 2);

    difficulty = 0.75e18;
    underTest.updateGlobalDifficulty(difficulty);
    assertEq(underTest.applyDifficulty(value), Math.mulDiv(value, MAX_DIFFICULTY - difficulty, MAX_DIFFICULTY));

    difficulty = 1e18;
    underTest.updateGlobalDifficulty(difficulty);
    assertEq(underTest.applyDifficulty(value), 0);
  }

  function test_redeem_givenOneMultiplier_thenCallsRedeem() external prankAs(user) {
    uint256 balanceBefore = inputToken.balanceOf(user);

    vm.expectCall(genesisToken, abi.encodeWithSelector(IGenesisToken.redeem.selector, user, 1));
    underTest.redeem(genesisToken, 1);

    assertEq(balanceBefore - inputToken.balanceOf(user), REDEEM_RATE);
  }

  function test_redeem_givenMultipleMultiplier_thenCallsRedeem() external prankAs(user) {
    uint256 redeemMultiplier = 8;
    uint256 balanceBefore = inputToken.balanceOf(user);

    vm.expectCall(genesisToken, abi.encodeWithSelector(IGenesisToken.redeem.selector, user, redeemMultiplier));
    underTest.redeem(genesisToken, redeemMultiplier);

    assertEq(balanceBefore - inputToken.balanceOf(user), REDEEM_RATE * redeemMultiplier);
  }

  function test_redeem_givenDifferentRate_thenUseCorrectRate() external pranking {
    uint256 newRate = 0.25e18;
    DEFAULT_REDEEM.ratePerRedeem = newRate;
    uint256 balanceBefore = inputToken.balanceOf(user);

    changePrank(owner);
    underTest.setRedeemSetting(genesisToken, DEFAULT_REDEEM);

    changePrank(user);
    underTest.redeem(genesisToken, 1);

    assertEq(balanceBefore - inputToken.balanceOf(user), newRate);
  }

  function test_setRedeemSettings_asUser_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.setRedeemSettings(new address[](0), new IGenesisHub.RedeemSettings[](0));
  }

  function test_setRedeemSettings_thenUpdates() external prankAs(owner) {
    address[] memory genesis = new address[](2);
    genesis[0] = genesisToken;
    genesis[1] = generateAddress();

    IGenesisHub.RedeemSettings[] memory redeems = new IGenesisHub.RedeemSettings[](2);
    redeems[0] = DEFAULT_REDEEM;
    redeems[1] = DEFAULT_REDEEM;

    expectExactEmit();
    emit IGenesisHub.RedeemSettingUpdated(genesis[0], DEFAULT_REDEEM);
    expectExactEmit();
    emit IGenesisHub.RedeemSettingUpdated(genesis[1], DEFAULT_REDEEM);
    underTest.setRedeemSettings(genesis, redeems);

    assertEq(abi.encode(underTest.getRedeemSettings(genesisToken)), abi.encode(DEFAULT_REDEEM));
  }

  function test_setRedeemSetting_asUser_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.setRedeemSetting(genesisToken, DEFAULT_REDEEM);
  }

  function test_setRedeemSetting_thenUpdates() external prankAs(owner) {
    expectExactEmit();
    emit IGenesisHub.RedeemSettingUpdated(genesisToken, DEFAULT_REDEEM);
    underTest.setRedeemSetting(genesisToken, DEFAULT_REDEEM);

    assertEq(abi.encode(underTest.getRedeemSettings(genesisToken)), abi.encode(DEFAULT_REDEEM));
  }

  function test_updateGlobalDifficulty_asUser_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.updateGlobalDifficulty(1e18);
  }

  function test_updateGlobalDifficulty_givenHigherThanMaximum_thenReverts() external prankAs(owner) {
    vm.expectRevert(IGenesisHub.InvalidDifficulty.selector);
    underTest.updateGlobalDifficulty(1e18 + 1);
  }

  function test_updateGlobalDifficulty_thenUpdates() external prankAs(owner) {
    uint256 difficulty = 0.822e18;

    expectExactEmit();
    emit IGenesisHub.GlobalDifficultyUpdated(difficulty);
    underTest.updateGlobalDifficulty(difficulty);

    assertEq(underTest.difficulty(), difficulty);
  }
}
