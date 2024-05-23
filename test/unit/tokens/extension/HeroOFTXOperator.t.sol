// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "../../../base/BaseTest.t.sol";

import { HeroOFTXOperator, IHeroOFTXOperator } from "src/tokens/extension/HeroOFTXOperator.sol";
import { ITickerOperator } from "heroglyph-library/ITickerOperator.sol";
import { IGasPool } from "heroglyph-library/IGasPool.sol";
import { IHeroOFTX } from "src/tokens/IHeroOFTX.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { Origin, MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";
import { ILayerZeroEndpointV2 } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppCore.sol";
import { MessagingParams } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import { FailOnReceive } from "test/mock/contract/FailOnReceive.t.sol";
import { MockERC20 } from "test/mock/contract/MockERC20.t.sol";

contract HeroOFTXOperatorTest is BaseTest {
  uint256 private constant MAX_SUPPLY = 219_000e18;
  uint32 private constant LZ_ENDPOINT_ID = 332;
  uint32 private constant LZ_ENDPOINT_ID_TWO = 99;
  uint32 private constant LZ_GAS_LIMIT = 200_000;
  bytes32 private constant PEER = bytes32("PEER");
  uint256 private constant LZ_FEE = 2_399_482;
  uint32 private constant BLOCK = 1_999_283;
  uint256 private constant VALIDATOR_KEY_BALANCE = 1e18;

  address private owner = generateAddress("Owner");
  address private user = generateAddress("User", 100e18);
  address private mockLzEndpoint = generateAddress("LZ Endpoint");
  address private mockRelay = generateAddress("Heroglyph Relay");
  address private validator = generateAddress("Validator");
  address private feePayer = generateAddress("FeePayer");
  address private treasury = generateAddress("treasury");
  MockERC20 private wrappedNative;
  MockERC20 private key;

  IHeroOFTXOperator.HeroOFTXOperatorArgs heroArgs;

  HeroOFTXHarness private underTest;

  function setUp() external prankAs(owner) {
    vm.mockCall(mockLzEndpoint, abi.encodeWithSignature("setDelegate(address)"), abi.encode(true));

    wrappedNative = new MockERC20("W", "W", 18);
    key = new MockERC20("K", "E", 18);

    key.mint(validator, VALIDATOR_KEY_BALANCE);
    wrappedNative.mint(validator, 1000e18);
    wrappedNative.mint(user, 1000e18);

    heroArgs = IHeroOFTXOperator.HeroOFTXOperatorArgs({
      wrappedNative: address(wrappedNative),
      key: address(key),
      owner: owner,
      feePayer: feePayer,
      heroglyphRelay: mockRelay,
      treasury: treasury,
      localLzEndpoint: mockLzEndpoint,
      localLzEndpointID: LZ_ENDPOINT_ID,
      lzGasLimit: LZ_GAS_LIMIT,
      maxSupply: MAX_SUPPLY
    });

    underTest = new HeroOFTXHarness(heroArgs);
    underTest.setPeer(LZ_ENDPOINT_ID_TWO, PEER);

    vm.mockCall(
      mockLzEndpoint, abi.encodeWithSelector(ILayerZeroEndpointV2.quote.selector), abi.encode(MessagingFee(LZ_FEE, 0))
    );

    MessagingReceipt memory emptyMsg;

    vm.mockCall(mockLzEndpoint, abi.encodeWithSelector(ILayerZeroEndpointV2.send.selector), abi.encode(emptyMsg));
    vm.mockCall(feePayer, abi.encodeWithSelector(IGasPool.payTo.selector), abi.encode(true));
  }

  function test_constructor_thenSetupCorrectly() external {
    underTest = new HeroOFTXHarness(heroArgs);

    assertEq(address(underTest.wrappedNative()), address(wrappedNative));
    assertEq(address(underTest.key()), address(key));
    assertEq(underTest.treasury(), treasury);
    assertEq(underTest.totalMintedSupply(), 0);
    assertEq(underTest.maxSupply(), MAX_SUPPLY);
    assertEq(underTest.getLatestBlockMinted(), 0);
    assertEq(underTest.localLzEndpointID(), LZ_ENDPOINT_ID);

    assertEq(
      underTest.ERROR_LZ_RETURNED_FALSE(), abi.encodeWithSelector(IHeroOFTXOperator.NotEnoughToLayerZeroFee.selector)
    );
  }

  function test_onValidatorTriggered_asNonRelay_thenReverts() external {
    vm.expectRevert(ITickerOperator.NotHeroglyph.selector);
    underTest.onValidatorTriggered(LZ_ENDPOINT_ID, BLOCK, validator, 0);
  }

  function test_onValidatorTriggered_whenValidatorDoesntHaveTheKey_thenDoNothing() external prankAs(mockRelay) {
    underTest.onValidatorTriggered(LZ_ENDPOINT_ID, BLOCK, validator, 0);
    key.burn(validator, VALIDATOR_KEY_BALANCE);

    underTest.onValidatorTriggered(LZ_ENDPOINT_ID, BLOCK + 1, validator, 0);
    assertEq(underTest.getLatestBlockMinted(), BLOCK);
  }

  function test_onValidatorTriggered_whenKeyIsEmptyAddress_thenCallsValidatorSameChain() external prankAs(mockRelay) {
    heroArgs.key = address(0);
    underTest = new HeroOFTXHarness(heroArgs);
    key.burn(validator, VALIDATOR_KEY_BALANCE);

    expectExactEmit();
    emit HeroOFTXHarness.OnValidatorSameChain(validator);

    underTest.onValidatorTriggered(LZ_ENDPOINT_ID, BLOCK, validator, 0);

    assertEq(underTest.getLatestBlockMinted(), BLOCK);
  }

  function test_onValidatorTriggered_givenOnSameChain_thenCallsValidatorSameChain() external prankAs(mockRelay) {
    expectExactEmit();
    emit HeroOFTXHarness.OnValidatorSameChain(validator);

    underTest.onValidatorTriggered(LZ_ENDPOINT_ID, BLOCK, validator, 0);

    assertEq(underTest.getLatestBlockMinted(), BLOCK);
  }

  function test_onValidatorTriggered_givenTwiceTheSameBlock_thenDoNothing() external prankAs(mockRelay) {
    expectExactEmit();
    emit HeroOFTXHarness.OnValidatorSameChain(validator);

    underTest.onValidatorTriggered(LZ_ENDPOINT_ID, BLOCK, validator, 0);

    underTest.onValidatorTriggered(LZ_ENDPOINT_ID, BLOCK, validator, 0);

    assertEq(underTest.totalMintedSupply(), underTest.REWARD_PER_MINT());
  }

  function test_onValidatorTriggered_givenDifferentBlock_thenExecutes() external prankAs(mockRelay) {
    expectExactEmit();
    emit HeroOFTXHarness.OnValidatorSameChain(validator);

    underTest.onValidatorTriggered(LZ_ENDPOINT_ID, BLOCK, validator, 0);
    underTest.onValidatorTriggered(LZ_ENDPOINT_ID, BLOCK + 1, validator, 0);

    assertEq(underTest.totalMintedSupply(), underTest.REWARD_PER_MINT() * 2);
    assertEq(underTest.getLatestBlockMinted(), BLOCK + 1);
  }

  function test_onValidatorTriggered_givenDifferentChain_whenOnValidatorCrossChainFails_thenDontExecuteLZ()
    external
    prankAs(mockRelay)
  {
    underTest.exposed_failNextOnValidatorCrossChain();

    vm.mockCallRevert(
      mockLzEndpoint, abi.encodeWithSelector(ILayerZeroEndpointV2.send.selector), abi.encode("Shouldnt be called")
    );
    expectExactEmit();
    emit HeroOFTXHarness.OnValidatorCrossChain(validator);

    underTest.onValidatorTriggered(LZ_ENDPOINT_ID_TWO, BLOCK, validator, 0);
    assertEq(underTest.totalMintedSupply(), 0);
  }

  function test_onValidatorTriggered_givenDifferentChain_whenReturnFalse_thenTriggersOnCrossChainFails()
    external
    pranking
  {
    changePrank(owner);
    underTest.updateFeePayer(address(underTest));

    changePrank(mockRelay);
    uint64 reward = underTest.REWARD_PER_MINT();

    expectExactEmit();
    emit HeroOFTXHarness.OnValidatorCrossChain(validator);
    expectExactEmit();
    emit HeroOFTXHarness.OnValidatorCrossChainFailed(validator, reward);
    expectExactEmit();
    emit IHeroOFTXOperator.OnCrossChainCallFails(
      validator, reward, abi.encodeWithSelector(IHeroOFTXOperator.NotEnoughToLayerZeroFee.selector)
    );

    underTest.onValidatorTriggered(LZ_ENDPOINT_ID_TWO, BLOCK, validator, 0);
    assertEq(underTest.totalMintedSupply(), reward);
  }

  function test_onValidatorTriggered_givenDifferentChain_whenLzFails_thenTriggersOnCrossChainFails()
    external
    prankAs(mockRelay)
  {
    bytes memory revertMsg = abi.encodePacked("Reverted");
    uint64 reward = underTest.REWARD_PER_MINT();

    vm.deal(address(underTest), 100e18);
    vm.mockCallRevert(mockLzEndpoint, abi.encodeWithSelector(ILayerZeroEndpointV2.send.selector), revertMsg);
    expectExactEmit();
    emit HeroOFTXHarness.OnValidatorCrossChain(validator);
    expectExactEmit();
    emit HeroOFTXHarness.OnValidatorCrossChainFailed(validator, reward);
    expectExactEmit();
    emit IHeroOFTXOperator.OnCrossChainCallFails(validator, reward, revertMsg);

    underTest.onValidatorTriggered(LZ_ENDPOINT_ID_TWO, BLOCK, validator, 0);
    assertEq(underTest.totalMintedSupply(), reward);
  }

  function test_onValidatorTriggered_givenDifferentChain__thenExecutesLZAndCallOnValidatorCrossChain()
    external
    prankAs(mockRelay)
  {
    vm.deal(address(underTest), 10e18);

    bytes memory message = _generateMessage(validator, underTest.REWARD_PER_MINT(), LZ_FEE);

    _expectLZSend(LZ_FEE, LZ_ENDPOINT_ID_TWO, message, underTest.exposed_defaultOption(), feePayer);

    expectExactEmit();
    emit HeroOFTXHarness.OnValidatorCrossChain(validator);

    underTest.onValidatorTriggered(LZ_ENDPOINT_ID_TWO, BLOCK, validator, 0);

    assertEq(underTest.totalMintedSupply(), underTest.REWARD_PER_MINT());
  }

  function test_validatorCrosschain_givenDifferentChain_whenOnValidatorCrossChainFails_thenDontExecuteLZ()
    external
    prankAs(mockRelay)
  {
    underTest.exposed_failNextOnValidatorCrossChain();

    vm.mockCallRevert(
      mockLzEndpoint, abi.encodeWithSelector(ILayerZeroEndpointV2.send.selector), abi.encode("Shouldnt be called")
    );
    expectExactEmit();
    emit HeroOFTXHarness.OnValidatorCrossChain(validator);

    underTest.exposed_validatorCrosschain(LZ_ENDPOINT_ID_TWO, validator);
  }

  function test_validatorCrosschain_givenDifferentChain__thenExecutesLZAndCallOnValidatorCrossChain()
    external
    prankAs(mockRelay)
  {
    vm.deal(address(underTest), 10e18);

    bytes memory message = _generateMessage(validator, underTest.REWARD_PER_MINT(), LZ_FEE);

    _expectLZSend(LZ_FEE, LZ_ENDPOINT_ID_TWO, message, underTest.exposed_defaultOption(), feePayer);

    expectExactEmit();
    emit HeroOFTXHarness.OnValidatorCrossChain(validator);

    underTest.exposed_validatorCrosschain(LZ_ENDPOINT_ID_TWO, validator);
  }

  function test_validatorCrosschain_whenToShareChainIsOverrided_thenDoConversion() external {
    vm.deal(address(underTest), 10e18);

    uint8 conversionDecimals = 11;
    uint256 convertion = (10 ** (18 - conversionDecimals));

    uint64 expectedReward = uint64(underTest.REWARD_PER_MINT() / convertion);
    bytes memory message = _generateMessage(validator, expectedReward, LZ_FEE);

    underTest.exposed_conversion(conversionDecimals);

    _expectLZSend(LZ_FEE, LZ_ENDPOINT_ID_TWO, message, underTest.exposed_defaultOption(), feePayer);

    underTest.exposed_validatorCrosschain(LZ_ENDPOINT_ID_TWO, validator);
  }

  function test_validatorLZSend_whenNotContract_thenReverts() external {
    vm.expectRevert(IHeroOFTXOperator.NoPermission.selector);
    underTest.validatorLZSend(1, msg.sender, 0);
  }

  function test_lzReceive_whenHasFee_thenFreezesAsset() external prankAs(user) {
    Origin memory origin = Origin({ srcEid: LZ_ENDPOINT_ID_TWO, sender: PEER, nonce: 0 });
    bytes32 uuid = keccak256(abi.encode("HelloWorld"));
    uint256 sending = 22e18;
    uint64 reward = underTest.REWARD_PER_MINT();

    bytes memory message = _generateMessage(validator, reward, LZ_FEE);

    expectExactEmit();
    emit HeroOFTXHarness.OnCreditCalled(validator, reward, true);
    expectExactEmit();
    emit IHeroOFTX.OFTReceived(uuid, LZ_ENDPOINT_ID_TWO, validator, reward);

    underTest.exposed_lzReceive{ value: sending }(uuid, origin, message);

    IHeroOFTXOperator.RequireAction[] memory actions = underTest.getPendingActions(LZ_ENDPOINT_ID_TWO, validator);

    assertEq(actions.length, 1);
    assertEq(actions[0].amountOrId, reward);
    assertEq(actions[0].fee, LZ_FEE);
  }

  function test_lzReceive_whenHasNoFee_thenCallsCreditWithNoFreeze() external prankAs(user) {
    Origin memory origin = Origin({ srcEid: LZ_ENDPOINT_ID_TWO, sender: PEER, nonce: 0 });
    bytes32 uuid = keccak256(abi.encode("HelloWorld"));
    uint64 reward = underTest.REWARD_PER_MINT();

    bytes memory message = _generateMessage(validator, reward, 0);

    expectExactEmit();
    emit HeroOFTXHarness.OnCreditCalled(validator, reward, false);
    expectExactEmit();
    emit IHeroOFTX.OFTReceived(uuid, LZ_ENDPOINT_ID_TWO, validator, reward);

    underTest.exposed_lzReceive(uuid, origin, message);

    assertEq(underTest.getPendingActions(LZ_ENDPOINT_ID_TWO, validator).length, 0);
  }

  function test_lzReceive_whenOverridedToLocalChain_thenConverts() external prankAs(user) {
    Origin memory origin = Origin({ srcEid: LZ_ENDPOINT_ID_TWO, sender: PEER, nonce: 0 });
    bytes32 uuid = keccak256(abi.encode("HelloWorld"));
    uint8 conversionDecimals = 11;

    uint64 reward = underTest.REWARD_PER_MINT();
    uint256 expectedReward = reward * (10 ** (18 - conversionDecimals));

    underTest.exposed_conversion(conversionDecimals);

    expectExactEmit();
    emit HeroOFTXHarness.OnCreditCalled(validator, expectedReward, false);
    expectExactEmit();
    emit IHeroOFTX.OFTReceived(uuid, LZ_ENDPOINT_ID_TWO, validator, expectedReward);

    underTest.exposed_lzReceive(uuid, origin, _generateMessage(validator, reward, 0));
  }

  function test_claimAction_whenNoAction_thenReverts() external prankAs(user) {
    uint256[] memory indexes = new uint256[](4);
    indexes[0] = 1;
    indexes[1] = 3;
    indexes[2] = 4;
    indexes[3] = 5;

    vm.expectRevert(IHeroOFTXOperator.NoAction.selector);
    underTest.claimAction(LZ_ENDPOINT_ID_TWO, indexes);
  }

  function test_claimAction_whenFailToSendAsset_thenReverts() external prankAs(user) {
    Origin memory origin = Origin({ srcEid: LZ_ENDPOINT_ID_TWO, sender: PEER, nonce: 0 });
    bytes32 uuid = keccak256(abi.encode("HelloWorld"));
    uint64 reward = underTest.REWARD_PER_MINT();

    bytes memory message = _generateMessage(validator, reward, LZ_FEE);
    underTest.exposed_lzReceive(uuid, origin, message);

    changePrank(validator);
    vm.deal(validator, 10e18);

    vm.mockCall(address(wrappedNative), abi.encodeWithSelector(MockERC20.transferFrom.selector), abi.encode(false));
    vm.expectRevert(IHeroOFTXOperator.FailedToSendWETH.selector);
    underTest.claimAction(LZ_ENDPOINT_ID_TWO, new uint256[](1));
  }

  function test_claimAction_thenSendsAssetsToTreasury() external prankAs(user) {
    Origin memory origin = Origin({ srcEid: LZ_ENDPOINT_ID_TWO, sender: PEER, nonce: 0 });
    bytes32 uuid = keccak256(abi.encode("HelloWorld"));
    uint64 reward = underTest.REWARD_PER_MINT();

    bytes memory message = _generateMessage(validator, reward, LZ_FEE);
    underTest.exposed_lzReceive(uuid, origin, message);

    changePrank(validator);
    vm.deal(validator, 10e18);

    expectExactEmit();
    emit HeroOFTXHarness.OnCreditCalled(validator, reward, false);
    underTest.claimAction(LZ_ENDPOINT_ID_TWO, new uint256[](1));

    assertEq(underTest.getPendingActions(LZ_ENDPOINT_ID_TWO, validator).length, 0);
    assertEq(wrappedNative.balanceOf(treasury), LZ_FEE);
  }

  function test_claimAction_givenOnlyOneIndex_whenHasMultipleActions_thenOnlyRemoveOne() external prankAs(user) {
    Origin memory origin = Origin({ srcEid: LZ_ENDPOINT_ID_TWO, sender: PEER, nonce: 0 });
    bytes32 uuid = keccak256(abi.encode("HelloWorld"));
    uint64 reward = underTest.REWARD_PER_MINT();
    uint256[] memory indexes = new uint256[](1);
    indexes[0] = 1;

    bytes memory message = _generateMessage(validator, reward, LZ_FEE);
    underTest.exposed_lzReceive(uuid, origin, message);

    message = _generateMessage(validator, reward, LZ_FEE * 3);
    underTest.exposed_lzReceive(uuid, origin, message);

    changePrank(validator);
    vm.deal(validator, 10e18);

    expectExactEmit();
    emit HeroOFTXHarness.OnCreditCalled(validator, reward, false);
    underTest.claimAction(LZ_ENDPOINT_ID_TWO, indexes);

    assertEq(underTest.getPendingActions(LZ_ENDPOINT_ID_TWO, validator).length, 1);
    assertEq(underTest.getPendingActions(LZ_ENDPOINT_ID_TWO, validator)[0].fee, LZ_FEE);
    assertEq(wrappedNative.balanceOf(treasury), LZ_FEE * 3);
  }

  function test_claimAction_givenAllIndexes_whenHasMultipleActions_thenClaimsAll() external prankAs(user) {
    Origin memory origin = Origin({ srcEid: LZ_ENDPOINT_ID_TWO, sender: PEER, nonce: 0 });
    bytes32 uuid = keccak256(abi.encode("HelloWorld"));
    uint64 reward = underTest.REWARD_PER_MINT();
    uint256[] memory indexes = new uint256[](2);
    indexes[0] = 1;
    indexes[1] = 0;

    bytes memory message = _generateMessage(validator, reward, LZ_FEE);
    underTest.exposed_lzReceive(uuid, origin, message);

    message = _generateMessage(validator, reward, LZ_FEE * 3);
    underTest.exposed_lzReceive(uuid, origin, message);

    changePrank(validator);
    vm.deal(validator, 10e18);

    assertEq(underTest.getActionsFeeTotal(LZ_ENDPOINT_ID_TWO, validator, indexes), LZ_FEE * 4);

    expectExactEmit();
    emit HeroOFTXHarness.OnCreditCalled(validator, reward, false);
    expectExactEmit();
    emit HeroOFTXHarness.OnCreditCalled(validator, reward, false);
    underTest.claimAction(LZ_ENDPOINT_ID_TWO, indexes);

    assertEq(underTest.getPendingActions(LZ_ENDPOINT_ID_TWO, validator).length, 0);
    assertEq(wrappedNative.balanceOf(treasury), LZ_FEE * 4);
  }

  function test_forgiveDebt_asUser_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.forgiveDebt(LZ_ENDPOINT_ID_TWO, validator, new uint256[](1));
  }

  function test_forgiveDebt_whenNoAction_thenReverts() external prankAs(owner) {
    vm.expectRevert(IHeroOFTXOperator.NoAction.selector);
    underTest.forgiveDebt(LZ_ENDPOINT_ID_TWO, validator, new uint256[](1));
  }

  function test_forgiveDebt_thenExecutesActionWithoutFee() external prankAs(owner) {
    Origin memory origin = Origin({ srcEid: LZ_ENDPOINT_ID_TWO, sender: PEER, nonce: 0 });
    bytes32 uuid = keccak256(abi.encode("HelloWorld"));
    uint64 reward = underTest.REWARD_PER_MINT();

    bytes memory message = _generateMessage(validator, reward, LZ_FEE);
    underTest.exposed_lzReceive(uuid, origin, message);

    expectExactEmit();
    emit HeroOFTXHarness.OnCreditCalled(validator, reward, false);
    underTest.forgiveDebt(LZ_ENDPOINT_ID_TWO, validator, new uint256[](1));

    assertEq(underTest.getPendingActions(LZ_ENDPOINT_ID_TWO, validator).length, 0);
    assertEq(wrappedNative.balanceOf(treasury), 0);
  }

  function test_executeAction_whenNoAction_thenReturnsZero() external {
    assertEq(underTest.exposed_executeAction(0, user, 0), 0);
  }

  function test_executeAction_whenOnlyOneAction_thenRemoveLastActionAndCallOnActionCompleted() external {
    Origin memory origin = Origin({ srcEid: LZ_ENDPOINT_ID_TWO, sender: PEER, nonce: 0 });
    bytes32 uuid = keccak256(abi.encode("HelloWorld"));
    uint64 reward = underTest.REWARD_PER_MINT();

    bytes memory message = _generateMessage(validator, reward, LZ_FEE);
    underTest.exposed_lzReceive(uuid, origin, message);

    expectExactEmit();
    emit HeroOFTXHarness.OnCreditCalled(validator, reward, false);
    underTest.exposed_executeAction(LZ_ENDPOINT_ID_TWO, validator, 0);

    assertEq(underTest.getPendingActions(LZ_ENDPOINT_ID_TWO, validator).length, 0);
  }

  function test_executeAction_whenMultipleActions_thenResizeArrayAndCallOnActionCompleted() external {
    Origin memory origin = Origin({ srcEid: LZ_ENDPOINT_ID_TWO, sender: PEER, nonce: 0 });
    bytes32 uuid = keccak256(abi.encode("HelloWorld"));
    uint64 reward = underTest.REWARD_PER_MINT();

    bytes memory message = _generateMessage(validator, reward, LZ_FEE);
    underTest.exposed_lzReceive(uuid, origin, message);

    message = _generateMessage(validator, reward, LZ_FEE * 3);
    underTest.exposed_lzReceive(uuid, origin, message);

    expectExactEmit();
    emit HeroOFTXHarness.OnCreditCalled(validator, reward, false);
    underTest.exposed_executeAction(LZ_ENDPOINT_ID_TWO, validator, 0);

    assertEq(underTest.getPendingActions(LZ_ENDPOINT_ID_TWO, validator).length, 1);
    assertEq(underTest.getPendingActions(LZ_ENDPOINT_ID_TWO, validator)[0].fee, LZ_FEE * 3);
  }

  function test_retrieveNative_asUser_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.retrieveNative(user);
  }

  function test_retrieveNative_whenFailsToSend_thenReverts() external prankAs(owner) {
    address to = generateAddress();
    uint256 balance = 9.29e18;
    vm.deal(address(underTest), balance);
    vm.etch(to, type(FailOnReceive).creationCode);

    vm.expectRevert(ITickerOperator.FailedToSendETH.selector);
    underTest.retrieveNative(to);
  }

  function test_retrieveNative_thenRetrieves() external prankAs(owner) {
    address to = generateAddress();
    uint256 balance = 9.29e18;

    vm.deal(address(underTest), balance);

    underTest.retrieveNative(to);

    assertEq(to.balance, balance);
  }

  function test_estimateFee_thenReturnsFee() external view {
    assertEq(underTest.estimateFee(LZ_ENDPOINT_ID_TWO, validator, 100e18), LZ_FEE);
  }

  function test_payNative_whenMsgValueNotEnough_thenReverts() external prankAs(user) {
    uint256 msgValue = 1e18;

    vm.expectRevert(abi.encodeWithSignature("NotEnoughNative(uint256)", msgValue));
    underTest.exposed_payNative{ value: msgValue }(msgValue + 1);
  }

  function test_payNative_whenMsgValueIsZeroAndContractBalanceToLower_thenReverts() external prankAs(user) {
    uint256 balance = 1e18;
    vm.deal(address(underTest), balance);

    vm.expectRevert(abi.encodeWithSignature("NotEnoughNative(uint256)", balance));
    underTest.exposed_payNative(balance + 1);
  }

  function test_payNative_whenMsgValueIsNotZeroAndContractHasEnought_thenReverts() external prankAs(user) {
    uint256 balance = 1e18;
    vm.deal(address(underTest), balance * 2);

    vm.expectRevert(abi.encodeWithSignature("NotEnoughNative(uint256)", balance));
    underTest.exposed_payNative{ value: balance }(balance + 1);
  }

  function test_payNative_whenMsgValueHighEnough_thenReturnsNativeFee() external prankAs(user) {
    uint256 sending = 1e18;
    uint256 fee = sending - 0.05e18;

    uint256 returnedFee = underTest.exposed_payNative{ value: sending }(fee);

    assertEq(returnedFee, fee);
  }

  function test_payNative_whenWhenContractBalanceIsHighEnough_thenReturnsNativeFee() external prankAs(user) {
    uint256 sending = 1e18;
    uint256 fee = sending - 0.05e18;

    vm.deal(address(underTest), sending);
    uint256 returnedFee = underTest.exposed_payNative{ value: sending }(fee);

    assertEq(returnedFee, fee);
  }

  function test_generateMessage_thenIncludeFeeToIt() external view {
    assertEq(underTest.exposed_generateMessage(user, 25.3e13), abi.encode(user, uint64(25.3e13), 0));
  }

  function test_generateMessage_whenToShareIsOverrided_thenApplyConvertion() external {
    uint64 amount = 99e13;
    uint8 conversionDecimals = 11;
    uint64 expectAmount = uint64(amount / (10 ** (18 - conversionDecimals)));

    underTest.exposed_conversion(conversionDecimals);

    assertEq(underTest.exposed_generateMessage(user, amount), abi.encode(user, expectAmount, 0));
  }

  function test_updateTreasury_asNonOwner_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.updateTreasury(user);
  }

  function test_updateTreasury_thenUpdates() external prankAs(owner) {
    address newTreasury = generateAddress();

    expectExactEmit();
    emit IHeroOFTXOperator.TreasuryUpdated(newTreasury);
    underTest.updateTreasury(newTreasury);

    assertEq(underTest.treasury(), newTreasury);
  }

  function test_updateNativeWrapper_asNonOwner_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.updateNativeWrapper(user);
  }

  function test_updateNativeWrapper_thenUpdates() external prankAs(owner) {
    address newWrapper = generateAddress();
    underTest.updateNativeWrapper(newWrapper);

    assertEq(underTest.wrappedNative(), newWrapper);
  }

  function _expectLZSend(uint256 _fee, uint32 _toEndpoint, bytes memory _payload, bytes memory _option, address _refund)
    private
  {
    vm.expectCall(
      mockLzEndpoint,
      _fee,
      abi.encodeWithSelector(
        ILayerZeroEndpointV2.send.selector, MessagingParams(_toEndpoint, PEER, _payload, _option, false), _refund
      )
    );
  }

  function _generateMessage(address _to, uint64 _amount, uint256 _fee) private pure returns (bytes memory) {
    return abi.encode(_to, _amount, _fee);
  }
}

contract HeroOFTXHarness is HeroOFTXOperator {
  uint64 public constant REWARD_PER_MINT = 60e6;
  bool private failOnValidatorCrossChain;
  uint256 public decimalConversionRate = 1;

  event OnCreditCalled(address to, uint256 value, bool isFrozen);
  event OnValidatorSameChain(address to);
  event OnValidatorCrossChain(address to);
  event OnValidatorCrossChainFailed(address to, uint256 value);

  constructor(HeroOFTXOperatorArgs memory _heroArgs) HeroOFTXOperator(_heroArgs) { }

  function exposed_validatorCrosschain(uint32 _lzDstEndpointId, address _to) external {
    _validatorCrosschain(_lzDstEndpointId, _to);
  }

  function exposed_lzReceive(bytes32 _uuid, Origin calldata _origin, bytes calldata _payload) external payable {
    _lzReceive(_origin, _uuid, _payload, address(0), _payload);
  }

  function exposed_credit(address _to, uint256 _value, bool _isFrozen) external returns (uint256) {
    return _credit(_to, _value, _isFrozen);
  }

  function exposed_executeAction(uint32 _srcLzEndpoint, address _of, uint256 _index)
    external
    returns (uint256 amountDue_)
  {
    return _executeAction(_srcLzEndpoint, _of, _index);
  }

  function exposed_defaultOption() external view returns (bytes memory) {
    return defaultLzOption;
  }

  function exposed_failNextOnValidatorCrossChain() external {
    failOnValidatorCrossChain = true;
  }

  function exposed_payNative(uint256 _amount) external payable returns (uint256) {
    return _payNative(_amount);
  }

  function exposed_generateMessage(address _to, uint256 _amountOrId) external view returns (bytes memory) {
    return _generateMessage(_to, _amountOrId);
  }

  function exposed_conversion(uint256 _decimals) external {
    decimalConversionRate = 10 ** (18 - _decimals);
  }

  function _onValidatorSameChain(address _to) internal override returns (uint256) {
    emit OnValidatorSameChain(_to);
    return REWARD_PER_MINT;
  }

  function _onValidatorCrossChain(address _to)
    internal
    override
    returns (uint256 tokenIdOrAmount_, uint256 amountMinted_, bool success_)
  {
    emit OnValidatorCrossChain(_to);
    return (REWARD_PER_MINT, REWARD_PER_MINT, !failOnValidatorCrossChain);
  }

  function _debit(uint256 _amountOrId, uint256) internal pure override returns (uint256 _amountSendingOrId_) {
    return _amountOrId;
  }

  function _credit(address _to, uint256 _value, bool _isFrozen) internal override returns (uint256 amountReceived_) {
    emit OnCreditCalled(_to, _value, _isFrozen);
    return _value;
  }

  function _onValidatorCrossChainFailed(address _to, uint256 _idOrAmount) internal override {
    emit OnValidatorCrossChainFailed(_to, _idOrAmount);
  }

  function _toSharedDecimals(uint256 _v) internal view override returns (uint64) {
    return uint64(_v / decimalConversionRate);
  }

  function _toLocalDecimals(uint64 _v) internal view override returns (uint256) {
    return _v * decimalConversionRate;
  }
}
