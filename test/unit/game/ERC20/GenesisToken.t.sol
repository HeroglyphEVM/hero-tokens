// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "../../../base/BaseTest.t.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { GenesisToken, IGenesisToken } from "src/game/ERC20/GenesisToken.sol";
import { IGenesisHub } from "src/game/IGenesisHub.sol";

import { IHeroOFTXOperator } from "src/tokens/extension/IHeroOFTXOperator.sol";

import { MockERC20 } from "test/mock/contract/MockERC20.t.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract GenesisTokenTest is BaseTest {
  IGenesisToken.GenesisConfiguration private genesisTokenData;
  IGenesisToken.GenesisConstructor private genesisConstructor;
  IHeroOFTXOperator.HeroOFTXOperatorArgs private heroOFTXOperatorArgs;

  address private owner;
  address private user;
  address private treasury;
  address private feePayer;
  address private heroglyphRelay;
  address private localLzEndpoint;
  address private genesisHub;
  uint32 private constant LOCAL_LZ_ENDPOINT_ID = 1;
  uint32 private constant LZ_GAS_LIMIT = 200_000;
  uint256 private constant MAX_SUPPLY = 1_099_245e18;
  uint256 private constant FIXED_RATE = 5.45e18;
  uint256 private constant MAX_BONUS_FULL_DAY = 11.33e18;

  MockERC20 private key;
  GenesisTokenHarness private underTest;

  function setUp() external {
    skip(1_832_719);

    generateVariables();

    vm.mockCall(localLzEndpoint, abi.encodeWithSignature("delegate(address)"), abi.encode(owner));

    heroOFTXOperatorArgs = IHeroOFTXOperator.HeroOFTXOperatorArgs({
      wrappedNative: address(0),
      key: address(key),
      owner: owner,
      treasury: treasury,
      feePayer: feePayer,
      heroglyphRelay: heroglyphRelay,
      localLzEndpoint: localLzEndpoint,
      localLzEndpointID: LOCAL_LZ_ENDPOINT_ID,
      lzGasLimit: LZ_GAS_LIMIT,
      maxSupply: MAX_SUPPLY
    });

    genesisTokenData =
      IGenesisToken.GenesisConfiguration({ fixedRate: FIXED_RATE, maxBonusFullDay: MAX_BONUS_FULL_DAY });

    genesisConstructor = IGenesisToken.GenesisConstructor({
      name: "Genesis Token",
      symbol: "GT",
      crossChainFee: 0,
      preMintAmount: 0,
      genesisHub: genesisHub,
      configuration: genesisTokenData
    });

    underTest = new GenesisTokenHarness(genesisConstructor, heroOFTXOperatorArgs);

    _mockApplyDifficulty(FIXED_RATE);
  }

  function generateVariables() internal {
    owner = generateAddress("Owner");
    user = generateAddress("User");
    treasury = generateAddress("Treasury");
    feePayer = generateAddress("FeePayer");
    heroglyphRelay = generateAddress("HeroGlyphRelay");
    localLzEndpoint = generateAddress("LocalLzEndpoint");
    genesisHub = generateAddress("genesisHub");

    key = new MockERC20("Key", "KEY", 18);

    key.mint(user, 1e18);
  }

  function test_constructor_whenNoPremit_thenSetups() external {
    underTest = new GenesisTokenHarness(genesisConstructor, heroOFTXOperatorArgs);

    assertEq(underTest.lastMintTriggered(), block.timestamp);
    assertEq(underTest.genesisHub(), genesisHub);
    assertEq(abi.encode(genesisTokenData), abi.encode(underTest.getConfiguration()));

    assertEq(underTest.owner(), owner);
    assertEq(underTest.treasury(), treasury);
    assertEq(underTest.getFeePayer(), feePayer);
    assertEq(address(underTest.heroglyphRelay()), address(heroglyphRelay));
    assertEq(address(underTest.key()), address(key));
  }

  function test_constructor_withPermit_thenSetups() external {
    uint256 premitAmount = 12.3e18;
    genesisConstructor.preMintAmount = premitAmount;

    underTest = new GenesisTokenHarness(genesisConstructor, heroOFTXOperatorArgs);

    assertEq(underTest.totalMintedSupply(), premitAmount);
    assertEq(underTest.balanceOf(treasury), premitAmount);
  }

  function test_onValidatorSameChaine_thenExecuteMintWithBonus() external {
    skip(1 days);
    uint256 reward = underTest.exposed_onValidatorSameChain(user);

    assertEq(underTest.balanceOf(user), reward);
    assertGt(reward, underTest.getConfiguration().fixedRate);
  }

  function test_onValidatorCrossChain_thenExecuteCrossChainWithBonus() external {
    skip(1 days);
    (uint256 _amount, uint256 totalMinted_, bool success_) = underTest.exposed_onValidatorCrossChain(user);

    assertEq(underTest.balanceOf(user), 0);
    assertEq(underTest.balanceOf(address(underTest)), 0);

    assertEq(_amount, totalMinted_);
    assertGt(totalMinted_, underTest.getConfiguration().fixedRate);
    assertTrue(success_);
  }

  function test_onValidatorCrossChain_whenNoReward_thenReturnsZeroAndFalse() external {
    underTest.exposed_totalMintedSupply(MAX_SUPPLY);
    (uint256 tokenIdOrAmount_, uint256 totalMinted_, bool success_) = underTest.exposed_onValidatorCrossChain(user);

    assertEq(tokenIdOrAmount_, 0);
    assertEq(totalMinted_, 0);
    assertFalse(success_);
  }

  function test_redeem_asNongenesisHub_thenReverts() external {
    vm.expectRevert(IGenesisToken.NotgenesisHub.selector);
    underTest.redeem(user, 1);
  }

  function test_redeem_whenWalletHasNoKey_thenReverts() external prankAs(genesisHub) {
    address to = generateAddress();

    vm.expectRevert(IGenesisToken.NoKeyDetected.selector);
    underTest.redeem(to, 1);
  }

  function test_redeem_whenWalletHasKey_thenRedeemsWithoutBonus() external prankAs(genesisHub) {
    skip(1 days);
    (uint256 redeemReward, uint256 mintingReward) = underTest.getNextReward();

    expectExactEmit();
    emit IGenesisToken.TokenRedeemed(user, redeemReward);

    uint256 reward = underTest.redeem(user, 1);

    assertEq(underTest.balanceOf(user), reward);
    assertEq(reward, underTest.getConfiguration().fixedRate);
    assertEq(reward, redeemReward);
    assertLt(reward, mintingReward);
  }

  function test_redeem_whenNoKeyNeeded_thenRedeemsWithoutBonus() external prankAs(genesisHub) {
    heroOFTXOperatorArgs.key = address(0);
    underTest = new GenesisTokenHarness(genesisConstructor, heroOFTXOperatorArgs);

    address to = generateAddress();

    skip(1 days);
    (uint256 redeemReward, uint256 mintingReward) = underTest.getNextReward();

    expectExactEmit();
    emit IGenesisToken.TokenRedeemed(to, redeemReward);

    uint256 reward = underTest.redeem(to, 1);

    assertEq(underTest.balanceOf(to), reward);
    assertEq(reward, underTest.getConfiguration().fixedRate);
    assertEq(reward, redeemReward);
    assertLt(reward, mintingReward);
  }

  function test_redeem_whenMultipleRedeem_thenRedeems() external prankAs(genesisHub) {
    uint256 multiplier = 3;

    _mockApplyDifficulty(FIXED_RATE * 3);

    underTest.redeem(user, multiplier);
    assertEq(underTest.balanceOf(user), multiplier * FIXED_RATE);
  }

  function test_executeMint_whenNoAddressGiven_thenDoesNotMint() external {
    skip(1 days);
    underTest.exposed_executeMint(address(0), true, 1);

    assertEq(underTest.totalSupply(), 0);
    assertEq(underTest.lastMintTriggered(), block.timestamp);
  }

  function test_executeMint_whenAddressGiven_thenMints() external {
    skip(1 days);
    uint256 reward = underTest.exposed_executeMint(user, true, 1);

    assertEq(underTest.balanceOf(user), reward);
    assertEq(underTest.totalSupply(), reward);
    assertEq(underTest.lastMintTriggered(), block.timestamp);
  }

  function test_executeMint_whenIsMiningFalse_thenReturnsRedeemReward() external {
    skip(1 days);
    (uint256 redeemReward,) = underTest.getNextReward();

    uint256 returned = underTest.exposed_executeMint(user, false, 1);
    assertEq(returned, redeemReward);
    assertEq(underTest.lastMintTriggered(), block.timestamp);
  }

  function test_executeMint_whenIsMiningTrue_thenReturnsBlockProducingReward() external {
    skip(2 days);
    (, uint256 blockProducingReward) = underTest.getNextReward();

    uint256 returned = underTest.exposed_executeMint(user, true, 1);
    assertEq(returned, blockProducingReward);
    assertEq(underTest.lastMintTriggered(), block.timestamp);
  }

  function test_calculateTokensToEmit_whenWithoutBonus_thenReturnsWithoutBonus() external {
    skip(1 days);
    uint256 reward = underTest.exposed_calculateTokensToEmit(uint32(block.timestamp), false, 1);

    assertEq(reward, FIXED_RATE);
  }

  function test_calculateTokensToEmit_whenWithBonus_thenReturnsWithBonus() external {
    skip(1.1 days);
    uint256 reward = underTest.exposed_calculateTokensToEmit(uint32(block.timestamp), true, 1);

    assertEq(reward, FIXED_RATE + MAX_BONUS_FULL_DAY);
  }

  function test_calculateTokensToEmit_whenMultipleDays_thenReturnsCappedBonus() external {
    skip(5 days);
    uint256 reward = underTest.exposed_calculateTokensToEmit(uint32(block.timestamp), true, 1);

    assertEq(reward, FIXED_RATE + MAX_BONUS_FULL_DAY);
  }

  function test_calculateTokensToEmit_whenBonusExceedMaxSupply_thenReturnsMinusBonus() external {
    skip(1.1 days);
    underTest.exposed_totalMintedSupply(MAX_SUPPLY - FIXED_RATE);

    _mockApplyDifficulty(FIXED_RATE * 2);

    uint256 reward = underTest.exposed_calculateTokensToEmit(uint32(block.timestamp), true, 1);

    assertEq(reward, FIXED_RATE);
  }

  function test_calculateTokensToEmit_whenPieceMissingBeforeMaxSupply_thenReturnsPieces() external {
    uint256 pieces = 0.0023e18;
    _mockApplyDifficulty(pieces);

    underTest.exposed_totalMintedSupply(MAX_SUPPLY - pieces);

    uint256 reward = underTest.exposed_calculateTokensToEmit(uint32(block.timestamp), true, 1);
    assertEq(reward, pieces);
  }

  function test_calculateTokensToEmit_whenMaxSupplyExceeded_thenReturnsZero() external {
    underTest.exposed_totalMintedSupply(MAX_SUPPLY);

    uint256 reward = underTest.exposed_calculateTokensToEmit(uint32(block.timestamp), true, 1);
    assertEq(reward, 0);
  }

  function test_updateConfiguration_asUser_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.updateConfiguration(genesisTokenData);
  }

  function test_updateConfiguration_asOwner_thenUpdates() external prankAs(owner) {
    genesisTokenData.fixedRate = 11e18;
    genesisTokenData.maxBonusFullDay = 992e18;

    expectExactEmit();
    emit IGenesisToken.ConfigurationUpdated(genesisTokenData);
    underTest.updateConfiguration(genesisTokenData);

    assertEq(abi.encode(genesisTokenData), abi.encode(underTest.getConfiguration()));
  }

  function test_updateGenesisHub_asUser_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.updateGenesisHub(genesisHub);
  }

  function test_updateGenesisHub_asOwner_thenUpdates() external prankAs(owner) {
    expectExactEmit();
    emit IGenesisToken.genesisHubUpdated(genesisHub);
    underTest.updateGenesisHub(genesisHub);

    assertEq(underTest.genesisHub(), genesisHub);
  }

  function _mockApplyDifficulty(uint256 _amountIn) private {
    vm.mockCall(genesisHub, abi.encodeWithSelector(IGenesisHub.applyDifficulty.selector), abi.encode(_amountIn));
  }
}

contract GenesisTokenHarness is GenesisToken {
  constructor(GenesisConstructor memory _constructorArgs, HeroOFTXOperatorArgs memory _operatorArgs)
    GenesisToken(_constructorArgs, _operatorArgs)
  { }

  function exposed_onValidatorSameChain(address _to) external returns (uint256) {
    return _onValidatorSameChain(_to);
  }

  function exposed_onValidatorCrossChain(address _to) external returns (uint256, uint256, bool) {
    return _onValidatorCrossChain(_to);
  }

  function exposed_executeMint(address _to, bool _isMining, uint256 _multiplier) external returns (uint256 reward_) {
    reward_ = _executeMint(_to, _isMining, _multiplier);
  }

  function exposed_totalMintedSupply(uint256 _amount) external {
    totalMintedSupply += _amount;
  }

  function exposed_calculateTokensToEmit(uint32 _timestamp, bool _withBonus, uint256 _multiplier)
    external
    view
    returns (uint256)
  {
    return _calculateTokensToEmit(_timestamp, _withBonus, _multiplier);
  }
}
