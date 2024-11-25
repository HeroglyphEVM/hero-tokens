// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import "../../../base/BaseTest.t.sol";
import { Icedrop, IIcedrop, IERC20 } from "src/game/phase3/module/Icedrop.sol";
import { IRandomizer } from "src/game/phase3/vendor/IRandomizer.sol";

import { ISablierV2LockupLinear } from "@sablier/v2-core/src/interfaces/ISablierV2LockupLinear.sol";
import { Broker, LockupLinear } from "@sablier/v2-core/src/types/DataTypes.sol";
import { ud60x18 } from "@prb-math/src/UD60x18.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { MockERC20Capped } from "hero-tokens/test/mock/contract/MockERC20Capped.t.sol";
import { MockERC20 } from "hero-tokens/test/mock/contract/MockERC20.t.sol";
import { FailOnReceive } from "hero-tokens/test/mock/contract/FailOnReceive.t.sol";

contract IcedropTest is BaseTest {
  address private owner;
  address private user;
  address private sablier;
  address private randomizer;
  address private holder;

  address private keyA_NotCapped;
  address private keyB_Capped;
  address private treasury;
  MockERC20 private token_reward_A;
  MockERC20 private token_reward_B;

  uint128 private constant MAX_REWARD_A = 332_813e18;
  uint128 private constant MAX_REWARD_B = 42_813e18;
  uint128 private constant MAX_SUPPLY = 333;
  uint128 private constant RANDOMIZER_FEE = 0.005 ether;
  bytes32 private KEY_B_1_HASH;

  IcedropHarness private underTest;
  uint256 private gamblingCost;

  IIcedrop.SupportedTokenData[] private DEFAULT_CONFIGURATION;

  function setUp() external {
    _prepareTests();
    underTest = new IcedropHarness(owner, treasury, sablier, randomizer, DEFAULT_CONFIGURATION);

    token_reward_A.mint(address(underTest), MAX_REWARD_A);
    token_reward_B.mint(address(underTest), MAX_REWARD_B);

    vm.mockCall(
      randomizer,
      abi.encodeWithSelector(IRandomizer.estimateFee.selector, underTest.MAX_GAS_RANDOMIZER()),
      abi.encode(RANDOMIZER_FEE)
    );

    vm.mockCall(
      randomizer,
      RANDOMIZER_FEE,
      abi.encodeWithSelector(IRandomizer.clientDeposit.selector, address(underTest)),
      abi.encode(true)
    );

    gamblingCost = underTest.gamblingCost();
  }

  function _prepareTests() internal {
    owner = generateAddress("Owner");
    user = generateAddress("User", 100e18);
    treasury = generateAddress("Treasury");
    sablier = generateAddress("Sablier");
    randomizer = generateAddress("Radomizer");
    holder = generateAddress("Holder");

    keyA_NotCapped = address(new MockERC20Capped("Key", "A", 18, MAX_SUPPLY));
    keyB_Capped = address(new MockERC20Capped("Key", "A", 18, MAX_SUPPLY));

    MockERC20Capped(keyA_NotCapped).mint(holder, MAX_SUPPLY - 10);
    MockERC20Capped(keyB_Capped).mint(holder, MAX_SUPPLY);

    token_reward_A = new MockERC20("Reward", "A", 18);
    token_reward_B = new MockERC20("Reward", "B", 18);

    KEY_B_1_HASH = keccak256(abi.encode(keyB_Capped, 1));

    DEFAULT_CONFIGURATION.push(
      IIcedrop.SupportedTokenData({
        genesisKey: keyA_NotCapped,
        output: address(token_reward_A),
        maxOutputToken: MAX_REWARD_A,
        started: false
      })
    );

    DEFAULT_CONFIGURATION.push(
      IIcedrop.SupportedTokenData({
        genesisKey: keyB_Capped,
        output: address(token_reward_B),
        maxOutputToken: MAX_REWARD_B,
        started: false
      })
    );
  }

  function test_constructor_thenSetupCorrectly() external {
    underTest = new IcedropHarness(owner, treasury, sablier, randomizer, DEFAULT_CONFIGURATION);
    assertEq(underTest.owner(), owner);
    assertEq(address(underTest.sablier()), sablier);
    assertEq(address(underTest.randomizer()), randomizer);
    assertEq(underTest.treasury(), treasury);
    assertGt(underTest.gamblingCost(), 0);

    assertEq(abi.encode(underTest.getGenesisKeySupport(keyA_NotCapped)), abi.encode(DEFAULT_CONFIGURATION[0]));
    assertEq(abi.encode(underTest.getGenesisKeySupport(keyB_Capped)), abi.encode(DEFAULT_CONFIGURATION[1]));
  }

  function test_initializeIcedrop_whenSupplyIsNotCappedYet_thenReverts() external {
    vm.expectRevert(IIcedrop.KeyIsNotSoldOut.selector);
    underTest.initializeIcedrop(keyA_NotCapped);
  }

  function test_initializeIcedrop_whenNotSupported_thenReverts() external {
    MockERC20Capped unsupported = new MockERC20Capped("C", "C", 18, 100);
    unsupported.mint(holder, 100);

    vm.expectRevert(IIcedrop.NotSupported.selector);
    underTest.initializeIcedrop(address(unsupported));
  }

  function test_initializeIcedrop_whenNotConfigured_thenReverts() external {
    DEFAULT_CONFIGURATION[1].maxOutputToken = 0;

    vm.prank(owner);
    underTest.updateSupportedToken(DEFAULT_CONFIGURATION[1]);

    vm.expectRevert(IIcedrop.Misconfiguration.selector);
    underTest.initializeIcedrop(keyB_Capped);
  }

  function test_initializeIcedrop_whenNotEnoughTokenInContract_thenReverts() external {
    token_reward_B.burn(address(underTest), 1);
    vm.expectRevert(IIcedrop.NotEnoughTokenInContract.selector);
    underTest.initializeIcedrop(keyB_Capped);
  }

  function test_initializeIcedrop_whenAlreadyStarted_thenReverts() external {
    underTest.initializeIcedrop(keyB_Capped);
    vm.expectRevert(IIcedrop.IcedropAlreadyStarted.selector);
    underTest.initializeIcedrop(keyB_Capped);
  }

  function test_initializeIcedrop_thenInitalizesIcedrop() external {
    vm.prank(treasury);
    token_reward_A.approve(address(underTest), MAX_REWARD_A + 1);

    MockERC20(keyA_NotCapped).mint(holder, 10);

    expectExactEmit();
    emit IIcedrop.IcedropStarted(keyA_NotCapped, address(token_reward_A), MAX_REWARD_A);
    underTest.initializeIcedrop(keyA_NotCapped);

    expectExactEmit();
    emit IIcedrop.IcedropStarted(keyB_Capped, address(token_reward_B), MAX_REWARD_B);
    underTest.initializeIcedrop(keyB_Capped);

    assertEq(token_reward_A.balanceOf(address(underTest)), MAX_REWARD_A);
    assertEq(token_reward_B.balanceOf(address(underTest)), MAX_REWARD_B);
    assertEq(token_reward_A.allowance(address(underTest), sablier), MAX_REWARD_A);
    assertEq(token_reward_B.allowance(address(underTest), sablier), MAX_REWARD_B);

    assertTrue(underTest.getGenesisKeySupport(keyA_NotCapped).started);
    assertTrue(underTest.getGenesisKeySupport(keyB_Capped).started);
  }

  function test_startVesting_whenNotGambling_givenMsgValue_thenReverts() external prankAs(user) {
    underTest.initializeIcedrop(keyB_Capped);

    vm.expectRevert(IIcedrop.RemoveMsgValueIfNotGambling.selector);
    underTest.startVesting{ value: 1e18 }(keyB_Capped, 1, false);
  }

  function test_startVesting_whenGambling_givenNotEnoughETH_thenReverts() external prankAs(user) {
    underTest.initializeIcedrop(keyB_Capped);

    vm.expectRevert(IIcedrop.NotEnoughToGamble.selector);
    underTest.startVesting{ value: (gamblingCost - 1) }(keyB_Capped, 1, true);
  }

  function test_startVesting_whenNotKeyOwner_thenReverts() external prankAs(user) {
    mockKeyOwner(keyB_Capped, 1, generateAddress());
    underTest.initializeIcedrop(keyB_Capped);

    vm.expectRevert(IIcedrop.NotKeyOwner.selector);
    underTest.startVesting(keyB_Capped, 1, false);
  }

  function test_startVesting_whenAlreadyClaimed_thenReverts() external prankAs(user) {
    mockKeyOwner(keyB_Capped, 1, user);

    vm.mockCall(sablier, abi.encodeWithSelector(ISablierV2LockupLinear.createWithDurations.selector), abi.encode(1));
    vm.expectCall(sablier, abi.encodeWithSelector(ISablierV2LockupLinear.createWithDurations.selector));

    underTest.initializeIcedrop(keyB_Capped);

    underTest.startVesting(keyB_Capped, 1, false);
    vm.expectRevert(IIcedrop.AlreadyCalledIcedrop.selector);
    underTest.startVesting(keyB_Capped, 1, false);
  }

  function test_startVesting_whenNotStarted_thenStartsAndCreatesSablierVesting() external prankAs(user) {
    uint256 keyId = 2;
    uint256 streamingId = 99;
    bytes32 keyHash = keccak256(abi.encode(keyB_Capped, keyId));
    mockKeyOwner(keyB_Capped, keyId, user);

    LockupLinear.CreateWithDurations memory params =
      generateSablierParams(user, MAX_REWARD_B / MAX_SUPPLY, address(token_reward_B));

    vm.mockCall(
      sablier,
      abi.encodeWithSelector(ISablierV2LockupLinear.createWithDurations.selector, params),
      abi.encode(streamingId)
    );
    vm.expectCall(sablier, abi.encodeWithSelector(ISablierV2LockupLinear.createWithDurations.selector, params));

    expectExactEmit();
    emit IIcedrop.IcedropStarted(keyB_Capped, address(token_reward_B), MAX_REWARD_B);
    expectExactEmit();
    emit IIcedrop.IcedropCalled(user, keyB_Capped, keyId, keyHash);
    expectExactEmit();
    emit IIcedrop.StreamStarted(user, keyHash, streamingId);
    underTest.startVesting(keyB_Capped, keyId, false);
  }

  function test_startVesting_givenNoGambling_thenCreatesSablierVesting() external prankAs(user) {
    uint256 keyId = 2;
    uint256 streamingId = 99;
    bytes32 keyHash = keccak256(abi.encode(keyB_Capped, keyId));
    mockKeyOwner(keyB_Capped, keyId, user);

    LockupLinear.CreateWithDurations memory params =
      generateSablierParams(user, MAX_REWARD_B / MAX_SUPPLY, address(token_reward_B));

    IIcedrop.StreamingData memory expectedStreamingData = IIcedrop.StreamingData({
      start: uint32(block.timestamp),
      end: uint32(block.timestamp + underTest.CLIFF_DURATION() + underTest.DEFAULT_DURATION()),
      amount: MAX_REWARD_B / MAX_SUPPLY,
      streamId: streamingId
    });

    vm.mockCall(
      sablier,
      abi.encodeWithSelector(ISablierV2LockupLinear.createWithDurations.selector, params),
      abi.encode(streamingId)
    );
    vm.expectCall(sablier, abi.encodeWithSelector(ISablierV2LockupLinear.createWithDurations.selector, params));

    underTest.initializeIcedrop(keyB_Capped);

    expectExactEmit();
    emit IIcedrop.IcedropCalled(user, keyB_Capped, keyId, keyHash);
    expectExactEmit();
    emit IIcedrop.StreamStarted(user, keyHash, streamingId);
    underTest.startVesting(keyB_Capped, keyId, false);

    assertEq(abi.encode(underTest.getKeyStreamingData(keyHash)), abi.encode(expectedStreamingData));
  }

  function test_startVesting_whenGambling_thenSendsGamblingRequest() external prankAs(user) {
    uint256 keyId = 2;
    uint256 randomizerId = 199;
    bytes32 keyHash = keccak256(abi.encode(keyB_Capped, keyId));

    IIcedrop.GamblingData memory expectingGambling = generateGamblingData(user, keyHash);

    mockKeyOwner(keyB_Capped, keyId, user);
    mockRandomizerRequest(randomizerId);

    vm.mockCallRevert(
      sablier, abi.encodeWithSelector(ISablierV2LockupLinear.createWithDurations.selector), "Should Not be called"
    );

    underTest.initializeIcedrop(keyB_Capped);

    expectExactEmit();
    emit IIcedrop.IcedropCalled(user, keyB_Capped, keyId, keyHash);
    expectExactEmit();
    emit IIcedrop.GamblingRequestSent(keyHash, randomizerId);
    underTest.startVesting{ value: gamblingCost + RANDOMIZER_FEE }(keyB_Capped, keyId, true);

    assertEq(abi.encode(underTest.getGamblingRequest(randomizerId)), abi.encode(expectingGambling));
  }

  function test_acceptGamblingResult_whenNotKeyOwner_thenReverts() external prankAs(user) {
    IIcedrop.GamblingData memory gamblingData = generateGamblingData(generateAddress(), KEY_B_1_HASH);
    underTest.exposed_injectGamblingData(100, KEY_B_1_HASH, gamblingData);

    vm.expectRevert(IIcedrop.NotKeyOwner.selector);
    underTest.acceptGamblingResult(KEY_B_1_HASH);
  }

  function test_acceptGamblingResult_whenAlreadyAccepted_thenReverts() external prankAs(user) {
    IIcedrop.GamblingData memory gamblingData = generateGamblingData(user, KEY_B_1_HASH);
    gamblingData.accepted = true;
    underTest.exposed_injectGamblingData(100, KEY_B_1_HASH, gamblingData);

    vm.expectRevert(IIcedrop.GamblingDealAccepted.selector);
    underTest.acceptGamblingResult(KEY_B_1_HASH);
  }

  function test_acceptGamblingResult_whenNotExecuted_thenReverts() external prankAs(user) {
    IIcedrop.GamblingData memory gamblingData = generateGamblingData(user, KEY_B_1_HASH);
    underTest.exposed_injectGamblingData(100, KEY_B_1_HASH, gamblingData);

    vm.expectRevert(IIcedrop.GamblingNotExecuted.selector);
    underTest.acceptGamblingResult(KEY_B_1_HASH);
  }

  function test_acceptGamblingResult_whenMinimumResult_thenCreatesVesting() external prankAs(user) {
    uint256 streamId = 9392;
    IIcedrop.GamblingData memory gamblingData = generateGamblingData(user, KEY_B_1_HASH);
    gamblingData.executed = true;
    gamblingData.seed = 18;

    underTest.exposed_injectGamblingData(100, KEY_B_1_HASH, gamblingData);

    LockupLinear.CreateWithDurations memory stream =
      generateSablierParams(user, MAX_REWARD_B / MAX_SUPPLY, address(token_reward_B));

    uint32 cliff = underTest.CLIFF_DURATION();
    stream.durations = LockupLinear.Durations({ cliff: cliff, total: cliff + underTest.MIN_DURATION() });

    vm.mockCall(
      sablier, abi.encodeWithSelector(ISablierV2LockupLinear.createWithDurations.selector, stream), abi.encode(streamId)
    );
    vm.expectCall(sablier, abi.encodeWithSelector(ISablierV2LockupLinear.createWithDurations.selector, stream));

    expectExactEmit();
    emit IIcedrop.StreamStarted(user, KEY_B_1_HASH, streamId);

    underTest.acceptGamblingResult(KEY_B_1_HASH);

    gamblingData.accepted = true;
    assertEq(abi.encode(underTest.getGamblingRequest(100)), abi.encode(gamblingData));
    assertEq(underTest.getGamblingWeekResult(KEY_B_1_HASH), 1);
  }

  function test_acceptGamblingResult_whenMaximumResult_thenCreatesVesting() external prankAs(user) {
    uint256 streamId = 9392;
    IIcedrop.GamblingData memory gamblingData = generateGamblingData(user, KEY_B_1_HASH);
    gamblingData.executed = true;
    gamblingData.seed = 17;

    underTest.exposed_injectGamblingData(100, KEY_B_1_HASH, gamblingData);

    LockupLinear.CreateWithDurations memory stream =
      generateSablierParams(user, MAX_REWARD_B / MAX_SUPPLY, address(token_reward_B));

    uint32 cliff = underTest.CLIFF_DURATION();
    stream.durations = LockupLinear.Durations({ cliff: cliff, total: cliff + underTest.MAX_DURATION() });

    vm.mockCall(
      sablier, abi.encodeWithSelector(ISablierV2LockupLinear.createWithDurations.selector, stream), abi.encode(streamId)
    );
    vm.expectCall(sablier, abi.encodeWithSelector(ISablierV2LockupLinear.createWithDurations.selector, stream));

    expectExactEmit();
    emit IIcedrop.StreamStarted(user, KEY_B_1_HASH, streamId);

    underTest.acceptGamblingResult(KEY_B_1_HASH);

    gamblingData.accepted = true;
    assertEq(abi.encode(underTest.getGamblingRequest(100)), abi.encode(gamblingData));
    assertEq(underTest.getGamblingWeekResult(KEY_B_1_HASH), 18);
  }

  function test_retryGambling_whenMsgValueUnderCost_thenReverts() external prankAs(user) {
    vm.expectRevert(IIcedrop.NotEnoughToGamble.selector);
    underTest.retryGambling{ value: gamblingCost - 1 }(keccak256(abi.encode(keyB_Capped, 1)));
  }

  function test_retryGambling_whenCallerIsNotKeyOwner_thenReverts() external prankAs(user) {
    IIcedrop.GamblingData memory gamblingData = generateGamblingData(generateAddress(), KEY_B_1_HASH);
    underTest.exposed_injectGamblingData(100, KEY_B_1_HASH, gamblingData);

    vm.expectRevert(IIcedrop.NotKeyOwner.selector);
    underTest.retryGambling{ value: gamblingCost * 2 }(KEY_B_1_HASH);
  }

  function test_retryGambling_whenAccepted_thenReverts() external prankAs(user) {
    IIcedrop.GamblingData memory gamblingData = generateGamblingData(user, KEY_B_1_HASH);
    gamblingData.accepted = true;

    underTest.exposed_injectGamblingData(100, KEY_B_1_HASH, gamblingData);

    vm.expectRevert(IIcedrop.GamblingDealAccepted.selector);
    underTest.retryGambling{ value: gamblingCost * 2 }(keccak256(abi.encode(keyB_Capped, 1)));
  }

  function test_retryGambling_whenNotExecuted_thenReverts() external prankAs(user) {
    IIcedrop.GamblingData memory gamblingData = generateGamblingData(user, KEY_B_1_HASH);

    underTest.exposed_injectGamblingData(100, KEY_B_1_HASH, gamblingData);

    vm.expectRevert(IIcedrop.GamblingNotExecuted.selector);
    underTest.retryGambling{ value: gamblingCost * 2 }(keccak256(abi.encode(keyB_Capped, 1)));
  }

  function test_retryGambling_whenMaxRetriedReached_thenReverts() external prankAs(user) {
    IIcedrop.GamblingData memory gamblingData = generateGamblingData(user, KEY_B_1_HASH);
    gamblingData.executed = true;
    gamblingData.retried = true;

    underTest.exposed_injectGamblingData(100, KEY_B_1_HASH, gamblingData);

    vm.expectRevert(IIcedrop.MaxRetryReached.selector);
    underTest.retryGambling{ value: gamblingCost * 2 }(keccak256(abi.encode(keyB_Capped, 1)));
  }

  function test_retryGambling_thenRetries() external prankAs(user) {
    uint256 randomizerId = 9328;

    IIcedrop.GamblingData memory gamblingData = generateGamblingData(user, KEY_B_1_HASH);
    gamblingData.executed = true;

    underTest.exposed_injectGamblingData(100, KEY_B_1_HASH, gamblingData);
    mockRandomizerRequest(randomizerId);

    underTest.retryGambling{ value: gamblingCost * 2 + RANDOMIZER_FEE }(keccak256(abi.encode(keyB_Capped, 1)));
    gamblingData.executed = false;
    gamblingData.retried = true;

    assertEq(abi.encode(underTest.getGamblingRequest(randomizerId)), abi.encode(gamblingData));
  }

  function test_createGamblingRequest_whenValueIsNotEqualsToRandomizerFee_thenReverts() external prankAs(user) {
    LockupLinear.CreateWithDurations memory sablierParams = generateSablierParams(user, 0, address(0));

    vm.expectRevert(IIcedrop.InsufficientFeeCost.selector);

    underTest.exposed_createGamblingRequest{ value: gamblingCost + RANDOMIZER_FEE - 1 }(
      KEY_B_1_HASH, false, sablierParams
    );

    vm.expectRevert(IIcedrop.InsufficientFeeCost.selector);
    underTest.exposed_createGamblingRequest{ value: gamblingCost + RANDOMIZER_FEE + 1 }(
      KEY_B_1_HASH, false, sablierParams
    );
  }

  function test_createGamblingRequest_whenFailsToSendETH_thenReverts() external prankAs(user) {
    uint256 randomizerId = 9328;
    LockupLinear.CreateWithDurations memory sablierParams = generateSablierParams(user, 0, address(0));
    IIcedrop.GamblingData memory expectedGamblingData = generateGamblingData(user, KEY_B_1_HASH);
    expectedGamblingData.streamParams = sablierParams;

    mockRandomizerRequest(randomizerId);

    vm.etch(treasury, type(FailOnReceive).creationCode);

    vm.expectRevert(IIcedrop.FailedToSendETH.selector);
    underTest.exposed_createGamblingRequest{ value: gamblingCost + RANDOMIZER_FEE }(KEY_B_1_HASH, false, sablierParams);
  }

  function test_createGamblingRequest_thenCreatesRequest() external prankAs(user) {
    uint256 randomizerId = 9328;
    LockupLinear.CreateWithDurations memory sablierParams = generateSablierParams(user, 0, address(0));
    IIcedrop.GamblingData memory expectedGamblingData = generateGamblingData(user, KEY_B_1_HASH);
    expectedGamblingData.streamParams = sablierParams;

    mockRandomizerRequest(randomizerId);

    expectExactEmit();
    emit IIcedrop.GamblingRequestSent(KEY_B_1_HASH, randomizerId);
    underTest.exposed_createGamblingRequest{ value: gamblingCost + RANDOMIZER_FEE }(KEY_B_1_HASH, false, sablierParams);

    assertEq(abi.encode(underTest.getGamblingRequest(randomizerId)), abi.encode(expectedGamblingData));
    assertEq(underTest.keyHashGamblingId(KEY_B_1_HASH), randomizerId);
    assertEq(treasury.balance, gamblingCost);
  }

  function test_randomizerCallback_whenNotRandomizerAI_thenReverts() external {
    vm.expectRevert(IIcedrop.NotRandomizerAI.selector);
    underTest.randomizerCallback(1, bytes32(abi.encode(1)));
  }

  function test_randomizerCallback_whenAlreadyExecuted_thenReverts() external prankAs(randomizer) {
    uint256 requestId = 444;
    IIcedrop.GamblingData memory gambling = generateGamblingData(user, KEY_B_1_HASH);
    gambling.executed = true;

    underTest.exposed_injectGamblingData(requestId, KEY_B_1_HASH, gambling);

    vm.expectRevert(IIcedrop.GamblingAlreadyExecuted.selector);
    underTest.randomizerCallback(requestId, keccak256(abi.encode(32)));
  }

  function test_randomizerCallback_thenRegistersValue() external prankAs(randomizer) {
    uint256 requestId = 444;
    bytes32 value = KEY_B_1_HASH;
    uint256 expectedResultMonth = uint256(value) % 18 + 1;

    IIcedrop.GamblingData memory gambling = generateGamblingData(user, KEY_B_1_HASH);

    underTest.exposed_injectGamblingData(requestId, KEY_B_1_HASH, gambling);

    expectExactEmit();
    emit IIcedrop.GamblingRequestReceived(requestId, value);
    underTest.randomizerCallback(requestId, value);

    gambling.executed = true;
    gambling.seed = uint256(value);

    assertEq(abi.encode(underTest.getGamblingRequest(requestId)), abi.encode(gambling));
    assertEq(underTest.getGamblingWeekResult(KEY_B_1_HASH), expectedResultMonth);
  }

  function test_randomizerWithdraw_whenNotOwner_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.randomizerWithdraw(0);
  }

  function test_randomizerWithdraw_thenCallsClientWithdrawTo() external prankAs(owner) {
    uint256 amount = 0.39e18;

    vm.mockCall(
      randomizer, abi.encodeWithSelector(IRandomizer.clientWithdrawTo.selector, owner, amount), abi.encode(true)
    );
    vm.expectCall(randomizer, abi.encodeWithSelector(IRandomizer.clientWithdrawTo.selector, owner, amount));

    underTest.randomizerWithdraw(amount);
  }

  function test_updateGamblingCost_whenNotOwner_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.updateGamblingCost(0);
  }

  function test_updateGamblingCost_thenUpdatesGamblingCost() external prankAs(owner) {
    uint256 newCost = 0.932e18;

    expectExactEmit();
    emit IIcedrop.GamblingCostUpdated(newCost);

    underTest.updateGamblingCost(newCost);

    assertEq(underTest.gamblingCost(), newCost);
  }

  function test_updateSupportedToken_whenNotOwner_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.updateSupportedToken(DEFAULT_CONFIGURATION[0]);
  }

  function test_updateSupportedToken_thenAddsNewSupportedTokens() external prankAs(owner) {
    address genesis = generateAddress();

    IIcedrop.SupportedTokenData memory newToken = IIcedrop.SupportedTokenData({
      genesisKey: genesis,
      output: address(generateAddress()),
      maxOutputToken: MAX_REWARD_B,
      started: false
    });

    expectExactEmit();
    emit IIcedrop.SupportedTokenUpdated(genesis, newToken);

    underTest.updateSupportedToken(newToken);

    assertEq(abi.encode(underTest.getGenesisKeySupport(genesis)), abi.encode(newToken));
  }

  function test_getGamblingWeekResult_whenGamblingNotExecuted_thenReturnsZero() external view {
    assertEq(underTest.getGamblingWeekResult(KEY_B_1_HASH), 0);
  }

  function mockKeyOwner(address key, uint256 keyId, address keyOwner) private {
    vm.mockCall(key, abi.encodeWithSignature("ownerOf(uint256)", keyId), abi.encode(keyOwner));
  }

  function mockRandomizerRequest(uint256 _returnedRequestId) private {
    vm.mockCall(randomizer, abi.encodeWithSelector(IRandomizer.request.selector), abi.encode(_returnedRequestId));
  }

  function generateGamblingData(address _caller, bytes32 _keyHash) private view returns (IIcedrop.GamblingData memory) {
    return IIcedrop.GamblingData({
      caller: _caller,
      keyHash: _keyHash,
      streamParams: generateSablierParams(_caller, MAX_REWARD_B / MAX_SUPPLY, address(token_reward_B)),
      executed: false,
      accepted: false,
      seed: 0,
      retried: false
    });
  }

  function generateSablierParams(address _receipient, uint256 _totalAmount, address _outputToken)
    private
    view
    returns (LockupLinear.CreateWithDurations memory)
  {
    uint32 cliff = underTest.CLIFF_DURATION();
    return LockupLinear.CreateWithDurations({
      sender: address(underTest),
      recipient: _receipient,
      totalAmount: uint128(_totalAmount),
      asset: IERC20(_outputToken),
      cancelable: false,
      transferable: false,
      durations: LockupLinear.Durations({ cliff: cliff, total: cliff + underTest.DEFAULT_DURATION() }),
      broker: Broker(address(0), ud60x18(0))
    });
  }
}

contract IcedropHarness is Icedrop {
  constructor(
    address _owner,
    address _treasury,
    address _sablier,
    address _randomizerAI,
    SupportedTokenData[] memory _supports
  ) Icedrop(_owner, _treasury, _sablier, _randomizerAI, _supports) { }

  function exposed_createGamblingRequest(
    bytes32 _keyHash,
    bool _retried,
    LockupLinear.CreateWithDurations memory _params
  ) external payable {
    _createGamblingRequest(_keyHash, _retried, _params);
  }

  function exposed_injectGamblingData(uint256 _requestId, bytes32 _keyHash, GamblingData memory _data) external {
    gamblingRequests[_requestId] = _data;
    keyHashGamblingId[_keyHash] = _requestId;
  }
}
