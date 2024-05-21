// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "../../../base/BaseTest.t.sol";

import { HeroLinearToken20 } from "src/tokens/ERC20/HeroLinearToken20.sol";
import { IHeroOFTXOperator } from "src/tokens/extension/IHeroOFTXOperator.sol";
import { MockERC20 } from "test/mock/contract/MockERC20.t.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract HeroLinearToken20Test is BaseTest {
  string private constant NAME = "MO";
  string private constant SYMBOL = "DU";
  uint256 private constant MAX_SUPPLY = 1_000_000e18;
  uint256 private constant PRE_MINT_AMOUNT = 100e18;
  uint256 private constant TOKEN_PER_SECONDS = 0.005e18;
  uint32 private constant LZ_ENDPOINT_CHAIN_ID = 1;
  uint32 private constant CROSS_CHAIN_FEE = 100;

  address private preMintTo;
  address private heroglyphRelay;
  address private lzEndpoint;
  address private owner;
  address private user;
  address private feeCollector;
  address private redeemHub;
  MockERC20 private redeem;
  MockERC20 private key;

  IHeroOFTXOperator.HeroOFTXOperatorArgs parameters;

  HeroLinearToken20Harness private underTest;

  function setUp() external {
    generateAddresses();

    redeem = new MockERC20("R", "R", 18);
    redeem.mint(user, 100e18);

    key = new MockERC20("A", "A", 18);
    key.mint(user, 1e18);

    vm.mockCall(lzEndpoint, abi.encodeWithSignature("delegate(address)"), abi.encode(owner));
    vm.mockCall(heroglyphRelay, abi.encodeWithSignature("getExecutionNativeFee(uint128)"), abi.encode(0));

    parameters = IHeroOFTXOperator.HeroOFTXOperatorArgs({
      wrappedNative: address(0),
      key: address(key),
      owner: owner,
      treasury: address(0),
      feePayer: address(0),
      heroglyphRelay: heroglyphRelay,
      localLzEndpoint: lzEndpoint,
      localLzEndpointID: LZ_ENDPOINT_CHAIN_ID,
      lzGasLimit: 200_000,
      maxSupply: MAX_SUPPLY
    });

    underTest = new HeroLinearToken20Harness(
      NAME,
      SYMBOL,
      feeCollector,
      CROSS_CHAIN_FEE,
      PRE_MINT_AMOUNT,
      preMintTo,
      TOKEN_PER_SECONDS,
      address(redeem),
      redeemHub,
      parameters
    );
  }

  function generateAddresses() internal {
    user = generateAddress("User");
    preMintTo = generateAddress("preMintTo");
    heroglyphRelay = generateAddress("heroglyphRelay");
    lzEndpoint = generateAddress("lzEndpoint");
    owner = generateAddress("owner");
    feeCollector = generateAddress("feeCollector");
    redeemHub = generateAddress("Hub Redeem");
  }

  function test_constructor_whenPreMintOrPreMintToIsEmpty_thenDontPreMit() external {
    underTest = new HeroLinearToken20Harness(
      NAME,
      SYMBOL,
      feeCollector,
      CROSS_CHAIN_FEE,
      0,
      preMintTo,
      TOKEN_PER_SECONDS,
      address(redeem),
      redeemHub,
      parameters
    );
    assertEq(underTest.totalSupply(), 0);

    underTest = new HeroLinearToken20Harness(
      NAME,
      SYMBOL,
      feeCollector,
      CROSS_CHAIN_FEE,
      0,
      address(0),
      TOKEN_PER_SECONDS,
      address(redeem),
      redeemHub,
      parameters
    );
    assertEq(underTest.totalSupply(), 0);
  }

  function test_constructor_thenValidatesSettings() external {
    underTest = new HeroLinearToken20Harness(
      NAME,
      SYMBOL,
      feeCollector,
      CROSS_CHAIN_FEE,
      PRE_MINT_AMOUNT,
      preMintTo,
      TOKEN_PER_SECONDS,
      address(redeem),
      redeemHub,
      parameters
    );

    assertEq(underTest.name(), NAME);
    assertEq(underTest.symbol(), SYMBOL);
    assertEq(underTest.maxSupply(), MAX_SUPPLY);
    assertEq(underTest.tokenPerSecond(), TOKEN_PER_SECONDS);
    assertEq(address(underTest.heroglyphRelay()), heroglyphRelay);
    assertEq(address(underTest.endpoint()), lzEndpoint);
    assertEq(underTest.owner(), owner);
    assertEq(underTest.feeCollector(), feeCollector);
    assertEq(underTest.redeemHub(), redeemHub);
    assertEq(underTest.totalMintedSupply(), PRE_MINT_AMOUNT);

    assertEq(underTest.balanceOf(preMintTo), PRE_MINT_AMOUNT);
  }

  function test_onValidationCrossChain_wheNoRewards_thenReturnsZero() external {
    skip(1000 days);
    underTest.exposed_executeMint(generateAddress(), false);

    address validator = generateAddress();

    uint256 answer = underTest.exposed_onValidatorSameChain(validator);

    assertEq(underTest.lastMintTriggered(), block.timestamp);
    assertEq(underTest.balanceOf(validator), 0);
    assertEq(answer, 0);
    assertEq(underTest.getNextReward(), 0);
  }

  function test_onValidationSameChain_thenReturnsReward() external {
    uint256 dayReward = _estimateReward(block.timestamp - 1 days, block.timestamp);
    address validator = generateAddress();

    skip(1 days);

    uint256 answer = underTest.exposed_onValidatorSameChain(validator);

    assertEq(underTest.lastMintTriggered(), block.timestamp);
    assertEq(underTest.balanceOf(validator), dayReward);
    assertEq(answer, dayReward);
    assertEq(underTest.getNextReward(), 0);
  }

  function test_onValidationSameChain_whenExtraReward_thenReturnsReward() external {
    uint256 dayReward = _estimateReward(block.timestamp - 1 days, block.timestamp);
    address validator = generateAddress();
    uint256 extra = 92.1e18;

    skip(1 days);

    underTest.exposed_extraToMinter(extra);

    uint256 answer = underTest.exposed_onValidatorSameChain(validator);

    assertEq(underTest.lastMintTriggered(), block.timestamp);
    assertEq(underTest.balanceOf(validator), dayReward + extra);
    assertEq(answer, dayReward + extra);
    assertEq(underTest.getNextReward(), 0);
    assertEq(underTest.extraRewardForMiner(), 0);
  }

  function test_onValidationCrossChain_wheNoRewards_thenReturnsFailed() external {
    skip(1000 days);
    underTest.exposed_executeMint(generateAddress(), false);

    address validator = generateAddress();

    (uint256 tokenIdOrAmount_, uint256 totalMinted_, bool success_) = underTest.exposed_onValidatorCrossChain(validator);

    assertEq(underTest.lastMintTriggered(), block.timestamp);
    assertEq(underTest.balanceOf(validator), 0);
    assertEq(tokenIdOrAmount_, 0);
    assertEq(totalMinted_, 0);
    assertEq(underTest.getNextReward(), 0);
    assertFalse(success_);
  }

  function test_onValidationCrossChain_thenReturnsCorrectlyInfo() external {
    uint256 dayReward = _estimateReward(block.timestamp - 1 days, block.timestamp);
    address validator = generateAddress();

    skip(1 days);

    (uint256 tokenIdOrAmount_, uint256 totalMinted_, bool success_) = underTest.exposed_onValidatorCrossChain(validator);

    assertEq(underTest.lastMintTriggered(), block.timestamp);
    assertEq(underTest.balanceOf(validator), 0);
    assertEq(tokenIdOrAmount_, dayReward);
    assertEq(totalMinted_, dayReward);
    assertEq(underTest.getNextReward(), 0);
    assertTrue(success_);
  }

  function test_onValidationCrossChain_givenExtraToMiner_thenReturnsCorrectlyInfo() external {
    uint256 dayReward = _estimateReward(block.timestamp - 1 days, block.timestamp);
    address validator = generateAddress();
    uint256 extra = 92.32e18;

    skip(1 days);

    underTest.exposed_extraToMinter(extra);

    (uint256 tokenIdOrAmount_, uint256 totalMinted_, bool success_) = underTest.exposed_onValidatorCrossChain(validator);

    assertEq(underTest.lastMintTriggered(), block.timestamp);
    assertEq(underTest.balanceOf(validator), 0);
    assertEq(tokenIdOrAmount_, dayReward + extra);
    assertEq(totalMinted_, dayReward + extra);
    assertEq(underTest.getNextReward(), 0);
    assertEq(underTest.extraRewardForMiner(), 0);
    assertTrue(success_);
  }

  function test_executeMint_whenNoRewards_thenReturns() external prankAs(heroglyphRelay) {
    address validator = generateAddress();

    vm.mockCallRevert(
      heroglyphRelay, abi.encodeWithSignature("getExecutionNativeFee(uint128)"), abi.encode("Should not be called")
    );

    underTest.exposed_executeMint(validator, false);
  }

  function test_redeem_whenNoRedeemToken_thenReverts() external {
    underTest = new HeroLinearToken20Harness(
      NAME,
      SYMBOL,
      feeCollector,
      CROSS_CHAIN_FEE,
      PRE_MINT_AMOUNT,
      preMintTo,
      TOKEN_PER_SECONDS,
      address(0),
      redeemHub,
      parameters
    );

    vm.expectRevert(HeroLinearToken20.NoRedeemTokenDectected.selector);
    underTest.redeem(0);
  }

  function test_redeem_whenNoKeyInWallet_thenReverts() external prankAs(user) {
    key.burn(user, 1e18);
    vm.expectRevert(HeroLinearToken20.NoKeyDetected.selector);
    underTest.redeem(0);
  }

  function test_redeem_whenNoReward_thenReverts() external prankAs(user) {
    vm.expectRevert(HeroLinearToken20.NoRewardCurrently.selector);
    underTest.redeem(0);
  }

  function test_redeem_whenRewardSmallerThanMinimum_thenReverts() external prankAs(user) {
    skip(1 days);

    uint256 reward = underTest.getNextReward();

    vm.expectRevert(HeroLinearToken20.RewardLowerThanMinimumAllowed.selector);
    underTest.redeem(reward + 1);
  }

  function test_redeem_whenContainsReward_thenClaims() external prankAs(user) {
    skip(1 days);

    uint256 reward = underTest.getNextReward();
    expectExactEmit();
    emit HeroLinearToken20.TokenRedeemed(user, reward);
    underTest.redeem(reward);

    assertEq(underTest.balanceOf(user), reward);
    assertEq(underTest.totalMintedSupply(), reward + PRE_MINT_AMOUNT);
    assertEq(underTest.getNextReward(), 0);
  }

  function test_redeem_whenMultipleRedeemBefore_thenApplyDecayPenalty() external prankAs(user) {
    skip(1 days);
    address randomMiner = generateAddress();
    uint256 dailyReward = underTest.getNextReward();
    uint256 expectedReward;
    uint256 toMiner;
    uint256 totalSent;

    uint32 penalty = 0;

    for (uint32 i = 0; i < 20; ++i) {
      penalty = i * 500;
      expectedReward = dailyReward - Math.mulDiv(dailyReward, penalty, 10_000);
      toMiner += dailyReward - expectedReward;

      totalSent += expectedReward;

      assertEq(underTest.getRedeemPenaltyBPS(), penalty);
      assertEq(underTest.redeem(0), expectedReward);
      skip(1 days);
    }

    assertEq(underTest.extraRewardForMiner(), toMiner);

    vm.expectRevert(HeroLinearToken20.RedeemDecayTooHigh.selector);
    underTest.redeem(0);

    skip(53 hours);
    assertEq(underTest.getRedeemPenaltyBPS(), 0);

    uint256 newRewardsLoot = underTest.getNextReward();
    totalSent += newRewardsLoot;

    assertEq(underTest.redeem(0), newRewardsLoot);
    assertEq(underTest.extraRewardForMiner(), toMiner);
    assertEq(underTest.totalReedemCalls(), 1);

    assertEq(underTest.balanceOf(user), totalSent);
    assertEq(underTest.totalMintedSupply(), totalSent + PRE_MINT_AMOUNT);

    skip(1 days);
    underTest.exposed_onValidatorSameChain(randomMiner);
    assertEq(underTest.balanceOf(randomMiner), toMiner + dailyReward);

    assertEq(underTest.totalMintedSupply(), toMiner + dailyReward + totalSent + PRE_MINT_AMOUNT);
  }

  function test_redeemFromHub_asNotHub_thenReverts() external {
    vm.expectRevert(HeroLinearToken20.NotRedeemHub.selector);
    underTest.redeemFromHub(user, 0);
  }

  function test_redeemFromHub_whenContainsReward_thenClaims() external prankAs(redeemHub) {
    skip(1 days);

    uint256 reward = underTest.getNextReward();
    expectExactEmit();
    emit HeroLinearToken20.TokenRedeemed(user, reward);
    underTest.redeemFromHub(user, reward);

    assertEq(underTest.balanceOf(user), reward);
    assertEq(underTest.totalMintedSupply(), reward + PRE_MINT_AMOUNT);
    assertEq(underTest.getNextReward(), 0);
  }

  function test_executeMint_thenExecutes() external prankAs(heroglyphRelay) {
    uint256 reachMaxSupply = (MAX_SUPPLY - PRE_MINT_AMOUNT) / TOKEN_PER_SECONDS;
    uint256 dayReward = _estimateReward(block.timestamp - 1 days, block.timestamp);
    address validator = generateAddress();

    skip(1 days);

    underTest.exposed_executeMint(validator, false);

    assertEq(underTest.lastMintTriggered(), block.timestamp);
    assertEq(underTest.balanceOf(validator), dayReward);
    assertEq(underTest.getNextReward(), 0);

    skip(1 days);

    underTest.exposed_executeMint(validator, false);

    assertEq(underTest.lastMintTriggered(), block.timestamp);
    assertEq(underTest.balanceOf(validator), dayReward * 2);
    assertEq(underTest.getNextReward(), 0);

    skip(reachMaxSupply);
    underTest.exposed_executeMint(validator, false);

    assertEq(underTest.balanceOf(validator), MAX_SUPPLY - PRE_MINT_AMOUNT);
  }

  function test_executeMint_whenMiner_givenExtraReward_thenExecutes() external prankAs(heroglyphRelay) {
    uint256 dayReward = _estimateReward(block.timestamp - 1 days, block.timestamp);
    address validator = generateAddress();
    uint256 extraReward = 99.23e18;

    skip(1 days);
    underTest.exposed_extraToMinter(extraReward);
    assertEq(underTest.extraRewardForMiner(), extraReward);

    underTest.exposed_executeMint(validator, true);

    assertEq(underTest.lastMintTriggered(), block.timestamp);
    assertEq(underTest.balanceOf(validator), dayReward + extraReward);
    assertEq(underTest.getNextReward(), 0);
    assertEq(underTest.extraRewardForMiner(), 0);
  }

  function test_getNextReward_thenReturnsCorrectValues() external {
    uint256 dayReward = _estimateReward(block.timestamp - 1 days, block.timestamp);
    skip(1 days);

    assertEq(underTest.getNextReward(), dayReward);

    uint256 reachMaxSupply = (MAX_SUPPLY - PRE_MINT_AMOUNT) / TOKEN_PER_SECONDS;
    skip(reachMaxSupply - 2 days);

    assertEq(underTest.getNextReward(), MAX_SUPPLY - PRE_MINT_AMOUNT - dayReward);

    skip(1 days);
    assertEq(underTest.getNextReward(), MAX_SUPPLY - PRE_MINT_AMOUNT);

    underTest.exposed_executeMint(msg.sender, false);

    skip(1 days);
    assertEq(underTest.getNextReward(), 0);
  }

  function _estimateReward(uint256 from, uint256 to) private pure returns (uint256) {
    return (to - from) * TOKEN_PER_SECONDS;
  }
}

contract HeroLinearToken20Harness is HeroLinearToken20 {
  constructor(
    string memory _name,
    string memory _symbol,
    address _feeCollector,
    uint32 _crossChainFee,
    uint256 _preMintAmount,
    address _preMintTo,
    uint256 _tokenPerSecond,
    address _redeem,
    address _HubRedeem,
    HeroOFTXOperatorArgs memory _heroArgs
  )
    HeroLinearToken20(
      _name,
      _symbol,
      _feeCollector,
      _crossChainFee,
      _preMintAmount,
      _preMintTo,
      _tokenPerSecond,
      _redeem,
      _HubRedeem,
      _heroArgs
    )
  { }

  function exposed_onValidatorSameChain(address _to) external returns (uint256 minted_) {
    minted_ = _onValidatorSameChain(_to);
    totalMintedSupply += minted_;

    return minted_;
  }

  function exposed_onValidatorCrossChain(address _to)
    external
    returns (uint256 tokenIdOrAmount_, uint256 totalMinted_, bool success_)
  {
    (tokenIdOrAmount_, totalMinted_, success_) = _onValidatorCrossChain(_to);
    totalMintedSupply += totalMinted_;

    return (tokenIdOrAmount_, totalMinted_, success_);
  }

  function exposed_executeMint(address _to, bool isMiner) external returns (uint256 reward_) {
    uint256 minted = _executeMint(_to, isMiner);
    totalMintedSupply += minted;
    return minted;
  }

  function exposed_extraToMinter(uint256 _extra) external {
    extraRewardForMiner += _extra;
  }
}
