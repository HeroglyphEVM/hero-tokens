// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "../../../base/BaseTest.t.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { GenesisToken, IGenesisToken } from "src/game/ERC20/GenesisToken.sol";

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
  address private redeemHub;
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
      redeemHub: redeemHub,
      configuration: genesisTokenData
    });

    underTest = new GenesisTokenHarness(genesisConstructor, heroOFTXOperatorArgs);
  }

  function generateVariables() internal {
    owner = generateAddress("Owner");
    user = generateAddress("User");
    treasury = generateAddress("Treasury");
    feePayer = generateAddress("FeePayer");
    heroglyphRelay = generateAddress("HeroGlyphRelay");
    localLzEndpoint = generateAddress("LocalLzEndpoint");
    redeemHub = generateAddress("RedeemHub");

    key = new MockERC20("Key", "KEY", 18);

    key.mint(user, 1e18);
  }

  function test_constructor_whenNoPremit_thenSetups() external {
    underTest = new GenesisTokenHarness(genesisConstructor, heroOFTXOperatorArgs);

    assertEq(underTest.lastMintTriggered(), block.timestamp);
    assertEq(underTest.redeemHub(), redeemHub);
    assertEq(abi.encode(genesisTokenData), abi.encode(underTest.getConfiguration()));

    assertEq(underTest.owner(), owner);
    assertEq(underTest.treasury(), treasury);
    assertEq(underTest.feePayer(), feePayer);
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

  function test_redeem_asNonRedeemHub_thenReverts() external {
    vm.expectRevert(IGenesisToken.NotRedeemHub.selector);
    underTest.redeem(user);
  }

  function test_redeem_whenWalletHasNoKey_thenReverts() external prankAs(redeemHub) {
    address to = generateAddress();

    vm.expectRevert(IGenesisToken.NoKeyDetected.selector);
    underTest.redeem(to);
  }

  function test_redeem_whenWalletHasKey_thenRedeemsWithoutBonus() external prankAs(redeemHub) {
    skip(1 days);
    (uint256 redeemReward, uint256 mintingReward) = underTest.getNextReward();

    expectExactEmit();
    emit IGenesisToken.TokenRedeemed(user, redeemReward);

    uint256 reward = underTest.redeem(user);

    assertEq(underTest.balanceOf(user), reward);
    assertEq(reward, underTest.getConfiguration().fixedRate);
    assertEq(reward, redeemReward);
    assertLt(reward, mintingReward);
  }

  function test_redeem_whenNoKeyNeeded_thenRedeemsWithoutBonus() external prankAs(redeemHub) {
    heroOFTXOperatorArgs.key = address(0);
    underTest = new GenesisTokenHarness(genesisConstructor, heroOFTXOperatorArgs);

    address to = generateAddress();

    skip(1 days);
    (uint256 redeemReward, uint256 mintingReward) = underTest.getNextReward();

    expectExactEmit();
    emit IGenesisToken.TokenRedeemed(to, redeemReward);

    uint256 reward = underTest.redeem(to);

    assertEq(underTest.balanceOf(to), reward);
    assertEq(reward, underTest.getConfiguration().fixedRate);
    assertEq(reward, redeemReward);
    assertLt(reward, mintingReward);
  }

  function test_executeMint_whenNoAddressGiven_thenDoesNotMint() external {
    skip(1 days);
    underTest.exposed_executeMint(address(0), true);

    assertEq(underTest.totalSupply(), 0);
    assertEq(underTest.lastMintTriggered(), block.timestamp);
  }

  function test_executeMint_whenAddressGiven_thenMints() external {
    skip(1 days);
    uint256 reward = underTest.exposed_executeMint(user, true);

    assertEq(underTest.balanceOf(user), reward);
    assertEq(underTest.totalSupply(), reward);
    assertEq(underTest.lastMintTriggered(), block.timestamp);
  }

  function test_executeMint_whenIsMiningFalse_thenReturnsRedeemReward() external {
    skip(1 days);
    (uint256 redeemReward,) = underTest.getNextReward();

    uint256 returned = underTest.exposed_executeMint(user, false);
    assertEq(returned, redeemReward);
    assertEq(underTest.lastMintTriggered(), block.timestamp);
  }

  function test_executeMint_whenIsMiningTrue_thenReturnsBlockProducingReward() external {
    skip(2 days);
    (, uint256 blockProducingReward) = underTest.getNextReward();

    uint256 returned = underTest.exposed_executeMint(user, true);
    assertEq(returned, blockProducingReward);
    assertEq(underTest.lastMintTriggered(), block.timestamp);
  }

  function test_calculateTokensToEmit_whenWithoutBonus_thenReturnsWithoutBonus() external {
    skip(1 days);
    uint256 reward = underTest.exposed_calculateTokensToEmit(uint32(block.timestamp), false);

    assertEq(reward, FIXED_RATE);
  }

  function test_calculateTokensToEmit_whenWithBonus_thenReturnsWithBonus() external {
    skip(1.1 days);
    uint256 reward = underTest.exposed_calculateTokensToEmit(uint32(block.timestamp), true);

    assertEq(reward, FIXED_RATE + MAX_BONUS_FULL_DAY);
  }

  function test_calculateTokensToEmit_whenMultipleDays_thenReturnsCappedBonus() external {
    skip(5 days);
    uint256 reward = underTest.exposed_calculateTokensToEmit(uint32(block.timestamp), true);

    assertEq(reward, FIXED_RATE + MAX_BONUS_FULL_DAY);
  }

  function test_calculateTokensToEmit_whenBonusExceedMaxSupply_thenReturnsMinusBonus() external {
    skip(1.1 days);
    underTest.exposed_totalMintedSupply(MAX_SUPPLY - FIXED_RATE);

    uint256 reward = underTest.exposed_calculateTokensToEmit(uint32(block.timestamp), true);

    assertEq(reward, FIXED_RATE);
  }

  function test_calculateTokensToEmit_whenPieceMissingBeforeMaxSupply_thenReturnsPieces() external {
    uint256 pieces = 0.0023e18;

    underTest.exposed_totalMintedSupply(MAX_SUPPLY - pieces);

    uint256 reward = underTest.exposed_calculateTokensToEmit(uint32(block.timestamp), true);
    assertEq(reward, pieces);
  }

  function test_calculateTokensToEmit_whenMaxSupplyExceeded_thenReturnsZero() external {
    underTest.exposed_totalMintedSupply(MAX_SUPPLY);

    uint256 reward = underTest.exposed_calculateTokensToEmit(uint32(block.timestamp), true);
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

  function test_updateRedeemHub_asUser_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.updateRedeemHub(redeemHub);
  }

  function test_updateRedeemHub_asOwner_thenUpdates() external prankAs(owner) {
    expectExactEmit();
    emit IGenesisToken.RedeemHubUpdated(redeemHub);
    underTest.updateRedeemHub(redeemHub);

    assertEq(underTest.redeemHub(), redeemHub);
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

  function exposed_executeMint(address _to, bool _isMining) external returns (uint256 reward_) {
    reward_ = _executeMint(_to, _isMining);
  }

  function exposed_totalMintedSupply(uint256 _amount) external {
    totalMintedSupply += _amount;
  }

  function exposed_calculateTokensToEmit(uint32 _timestamp, bool _withBonus) external view returns (uint256) {
    return _calculateTokensToEmit(_timestamp, _withBonus);
  }
}
