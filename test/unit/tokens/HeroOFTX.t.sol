// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "../../base/BaseTest.t.sol";
import { HeroOFTX, HeroOFTErrors } from "src/tokens/HeroOFTX.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { OApp, Origin, MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";
import { ILayerZeroEndpointV2 } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppCore.sol";
import { MessagingParams } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

contract HeroOFTXTest is BaseTest {
  using OptionsBuilder for bytes;

  uint32 private constant LZ_ENDPOINT_ID = 332;
  uint32 private constant LZ_ENDPOINT_ID_TWO = 99;
  uint32 private constant LZ_GAS_LIMIT = 200_000;
  bytes32 private constant PEER = bytes32("PEER");
  uint256 private constant LZ_FEE = 2_399_482;

  address private owner = generateAddress("Owner");
  address private user = generateAddress("User", 100e18);
  address private mockLzEndpoint = generateAddress("LZ Endpoint");

  HeroOFTXHarness private underTest;

  function setUp() external prankAs(owner) {
    vm.mockCall(mockLzEndpoint, abi.encodeWithSignature("setDelegate(address)"), abi.encode(true));

    underTest = new HeroOFTXHarness(owner, mockLzEndpoint, LZ_GAS_LIMIT);
    underTest.setPeer(LZ_ENDPOINT_ID_TWO, PEER);

    vm.mockCall(
      mockLzEndpoint, abi.encodeWithSelector(ILayerZeroEndpointV2.quote.selector), abi.encode(MessagingFee(LZ_FEE, 0))
    );

    MessagingReceipt memory emptyMsg;
    vm.mockCall(mockLzEndpoint, abi.encodeWithSelector(ILayerZeroEndpointV2.send.selector), abi.encode(emptyMsg));
  }

  function test_constructor_givenZeroLimitGas_thenReverts() external {
    vm.expectRevert(HeroOFTErrors.GasLimitCannotBeZero.selector);
    underTest = new HeroOFTXHarness(owner, mockLzEndpoint, 0);
  }

  function test_constructor_thenContractSets() external {
    bytes memory expectDefaultLzOption = OptionsBuilder.newOptions().addExecutorLzReceiveOption(LZ_GAS_LIMIT, 0);
    underTest = new HeroOFTXHarness(owner, mockLzEndpoint, LZ_GAS_LIMIT);

    assertEq(underTest.lzGasLimit(), LZ_GAS_LIMIT);
    assertEq(underTest.defaultLzOption(), expectDefaultLzOption);
  }

  function test_send_whenMinAmountIsHigherThanReceiving_thenReverts() external prankAs(user) {
    uint256 amountIn = 992e18;
    uint256 minAmount = amountIn + 1;

    vm.expectRevert(abi.encodeWithSelector(HeroOFTErrors.SlippageExceeded.selector, amountIn, minAmount));
    underTest.send{ value: LZ_FEE }(LZ_ENDPOINT_ID_TWO, user, amountIn, minAmount);
  }

  function test_send_thenCallsDebitAndLzSend() external prankAs(user) {
    uint256 amountIn = 992e15;
    uint256 minAmount = amountIn;

    uint8 decimals = 11;
    uint64 expectedAmount = uint64(amountIn / (10 ** (18 - decimals)));
    address to = generateAddress();

    bytes memory message = abi.encode(to, expectedAmount);

    underTest.exposed_conversion(decimals);

    expectExactEmit();
    emit HeroOFTXHarness.OnDebit(amountIn, minAmount);

    _expectLZSend(LZ_FEE, LZ_ENDPOINT_ID_TWO, message, underTest.defaultLzOption(), user);

    underTest.send{ value: LZ_FEE }(LZ_ENDPOINT_ID_TWO, to, amountIn, minAmount);
  }

  function test_send_whenToShareChainOverrided_thenAppliesConversion() external prankAs(user) {
    uint8 decimals = 11;
    uint64 amount = 9.992e15;
    uint256 expectedAmount = amount / (10 ** (18 - decimals));
    address to = generateAddress();

    bytes memory message = abi.encode(to, expectedAmount);

    underTest.exposed_conversion(decimals);

    expectExactEmit();
    emit HeroOFTXHarness.OnDebit(amount, amount);

    _expectLZSend(LZ_FEE, LZ_ENDPOINT_ID_TWO, message, underTest.defaultLzOption(), user);

    underTest.send{ value: LZ_FEE }(LZ_ENDPOINT_ID_TWO, to, amount, amount);
  }

  function test_estimateFee_thenReturnsFee() external {
    assertEq(underTest.estimateFee(LZ_ENDPOINT_ID_TWO, generateAddress(), 0), LZ_FEE);
  }

  function test_lzReceive_thenCallsCredit() external {
    Origin memory origin = Origin({ srcEid: LZ_ENDPOINT_ID_TWO, sender: PEER, nonce: 0 });
    bytes32 uuid = keccak256(abi.encode("HelloWorld"));
    uint64 amount = 9.992e5;
    address to = generateAddress();

    bytes memory message = abi.encode(to, amount);

    expectExactEmit();
    emit HeroOFTXHarness.OnCredit(to, amount, false);

    underTest.exposed_lzReceive(uuid, origin, message);
  }

  function test_lzReceive_whenToShareChainOverrided_thenAppliesConversion() external {
    Origin memory origin = Origin({ srcEid: LZ_ENDPOINT_ID_TWO, sender: PEER, nonce: 0 });
    bytes32 uuid = keccak256(abi.encode("HelloWorld"));

    uint8 decimals = 11;
    uint64 amount = 9.992e5;
    uint256 expectedAmount = amount * (10 ** (18 - decimals));
    address to = generateAddress();

    bytes memory message = abi.encode(to, amount);

    underTest.exposed_conversion(decimals);

    expectExactEmit();
    emit HeroOFTXHarness.OnCredit(to, expectedAmount, false);

    underTest.exposed_lzReceive(uuid, origin, message);
  }

  function test_updateLayerZeroGasLimit_asNonOwner_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.updateLayerZeroGasLimit(0);
  }

  function test_updateLayerZeroGasLimit_givenZero_thenReverts() external prankAs(owner) {
    vm.expectRevert(HeroOFTErrors.GasLimitCannotBeZero.selector);
    underTest.updateLayerZeroGasLimit(0);
  }

  function test_updateLayerZeroGasLimit_thenUpdatesLimitAndDefaultOption() external prankAs(owner) {
    uint32 gasLimit = 302_392;

    bytes memory expectDefaultLzOption = OptionsBuilder.newOptions().addExecutorLzReceiveOption(gasLimit, 0);
    underTest.updateLayerZeroGasLimit(gasLimit);

    assertEq(underTest.lzGasLimit(), gasLimit);
    assertEq(underTest.defaultLzOption(), expectDefaultLzOption);
  }

  function test_toLocalDecimals_thenDoNoConversion() external view {
    uint64 value = 938e8;
    assertEq(underTest.exposed_toLocalDecimals(value), value);
  }

  function test_toSharedDecimals_whenTooHighNumber_thenReverts() external {
    uint256 value = 938e18;

    vm.expectRevert(HeroOFTErrors.ConversionOutOfBounds.selector);
    underTest.exposed_toSharedDecimals(value);
  }

  function test_toSharedDecimals_thenDoNoConversion() external view {
    uint64 value = 938e8;
    assertEq(underTest.exposed_toSharedDecimals(value), value);
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
}

contract HeroOFTXHarness is HeroOFTX {
  uint64 public constant REWARD_PER_MINT = 60e6;
  uint256 public decimalConversionRate = 1;

  event OnDebit(uint256 a, uint256 b);
  event OnCredit(address a, uint256 b, bool c);

  constructor(address _owner, address _lzEndpoint, uint32 _lzGasLimit)
    OApp(_lzEndpoint, _owner)
    HeroOFTX(_lzGasLimit)
    Ownable(_owner)
  { }

  function exposed_lzReceive(bytes32 _uuid, Origin calldata _origin, bytes calldata _payload) external payable {
    _lzReceive(_origin, _uuid, _payload, address(0), _payload);
  }

  function exposed_toLocalDecimals(uint64 _value) external view returns (uint256) {
    return HeroOFTX._toLocalDecimals(_value);
  }

  function exposed_toSharedDecimals(uint256 _value) external view virtual returns (uint64) {
    return HeroOFTX._toSharedDecimals(_value);
  }

  function exposed_conversion(uint256 _decimals) external {
    decimalConversionRate = 10 ** (18 - _decimals);
  }

  function _debit(uint256 _amountOrId, uint256 _minAmount) internal override returns (uint256 _amountSendingOrId_) {
    emit OnDebit(_amountOrId, _minAmount);
    return _amountOrId;
  }

  function _credit(address _to, uint256 _value, bool _isFrozen) internal override returns (uint256 amountReceived_) {
    emit OnCredit(_to, _value, _isFrozen);
    return _value;
  }

  function _toSharedDecimals(uint256 _v) internal view override returns (uint64) {
    return uint64(_v / decimalConversionRate);
  }

  function _toLocalDecimals(uint64 _v) internal view override returns (uint256) {
    return _v * decimalConversionRate;
  }
}
