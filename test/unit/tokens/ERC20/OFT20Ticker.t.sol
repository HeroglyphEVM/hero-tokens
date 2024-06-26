// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "../../../base/BaseTest.t.sol";
import { OFT20Ticker } from "src/tokens/ERC20/OFT20Ticker.sol";
import { IHeroOFTXOperator } from "src/tokens/extension/IHeroOFTXOperator.sol";
import { HeroOFTErrors } from "src/tokens/HeroOFTErrors.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { ILayerZeroEndpointV2 } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppCore.sol";
import {
  MessagingReceipt,
  MessagingParams,
  MessagingFee
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { MockERC20 } from "../../../mock/contract/MockERC20.t.sol";

contract OFT20TickerTest is BaseTest {
  string private constant NAME = "MO";
  string private constant SYMBOL = "DU";
  uint256 private constant MAX_SUPPLY = 219_000e18;
  uint32 private constant LZ_ENDPOINT_ID = 332;
  uint32 private constant LZ_GAS_LIMIT = 200_000;
  uint32 private constant CROSS_CHAIN_FEE = 100;
  bytes32 private constant PEER = bytes32("PEER");
  uint256 private constant LZ_FEE = 2_399_482;

  address private owner = generateAddress("Owner");
  address private treasury = generateAddress("Treasury");
  address private user = generateAddress("User", 100e18);
  address private mockLzEndpoint = generateAddress("LZ Endpoint");
  address private mockRelay = generateAddress("Heroglyph Relay");
  MockERC20 private wrappedNative;

  IHeroOFTXOperator.HeroOFTXOperatorArgs args;

  OFT20TickerHarness private underTest;

  function setUp() external prankAs(owner) {
    vm.mockCall(mockLzEndpoint, abi.encodeWithSignature("setDelegate(address)"), abi.encode(true));

    wrappedNative = new MockERC20("W", "W", 18);

    args = IHeroOFTXOperator.HeroOFTXOperatorArgs({
      wrappedNative: address(wrappedNative),
      key: address(0),
      owner: owner,
      treasury: treasury,
      feePayer: address(0),
      heroglyphRelay: mockRelay,
      localLzEndpoint: mockLzEndpoint,
      localLzEndpointID: LZ_ENDPOINT_ID,
      lzGasLimit: LZ_GAS_LIMIT,
      maxSupply: MAX_SUPPLY
    });

    underTest = new OFT20TickerHarness(NAME, SYMBOL, treasury, CROSS_CHAIN_FEE, args);

    underTest.setPeer(LZ_ENDPOINT_ID, PEER);

    MessagingReceipt memory emptyMsg;

    vm.mockCall(
      mockLzEndpoint, abi.encodeWithSelector(ILayerZeroEndpointV2.quote.selector), abi.encode(MessagingFee(LZ_FEE, 0))
    );
    vm.mockCall(mockLzEndpoint, abi.encodeWithSelector(ILayerZeroEndpointV2.send.selector), abi.encode(emptyMsg));
  }

  function test_constructor_givenEmptyFeeCollector_thenReverts() external {
    vm.expectRevert(OFT20Ticker.EmptyFeeCollector.selector);
    new OFT20TickerHarness(NAME, SYMBOL, address(0), CROSS_CHAIN_FEE, args);
  }

  function test_constructor_thenSetupCorrectly() external {
    underTest = new OFT20TickerHarness(NAME, SYMBOL, treasury, CROSS_CHAIN_FEE, args);

    assertEq(underTest.feeCollector(), treasury);
    assertEq(underTest.crossChainFee(), CROSS_CHAIN_FEE);
  }

  function test_onValidatorCrossChainFailed_thenMints() external {
    underTest.exposed_onValidatorCrossChainFailed(user, 100e18);
    assertEq(underTest.balanceOf(user), 100e18);
  }

  function test_credit_givenFrozen_thenDoNotMint() external {
    uint256 value = 11.1e18;
    uint256 returnedValue = underTest.exposed_credit(user, value, true);

    assertEq(returnedValue, value);
    assertEq(underTest.balanceOf(user), 0);
  }

  function test_credit_givenNotFrozen_thenMints() external {
    uint256 value = 11.1e18;
    uint256 returnedValue = underTest.exposed_credit(user, value, false);

    assertEq(returnedValue, value);
    assertEq(underTest.balanceOf(user), value);
  }

  function test_debit_thenBurnsAmountAndMintFeeToLPAddress() external prankAs(user) {
    uint256 sending = 0.98e18;
    uint256 fee = _getCrosschainFee(sending);

    underTest.exposed_mint(user, 1e18);
    uint256 balanceBefore = underTest.balanceOf(user);

    uint256 amountReceiving = underTest.exposed_debit(sending, 0);

    assertEq(amountReceiving, sending - fee);
    assertEq(balanceBefore - underTest.balanceOf(user), sending);
    assertEq(underTest.balanceOf(treasury), fee);
  }

  function test_debitView_whenSlippageExceeded_thenReverts() external {
    uint256 sending = 45.98e18;
    uint256 fee = _getCrosschainFee(sending);

    vm.expectRevert(abi.encodeWithSelector(HeroOFTErrors.SlippageExceeded.selector, sending - fee, sending));
    underTest.exposed_debitView(sending, sending);
  }

  function test_debitView_thenApplyCrosschainFees() external view {
    uint256 sending = 0.98e18;
    uint256 fee = _getCrosschainFee(sending);

    (uint256 amountSent, uint256 amountReceiving) = underTest.exposed_debitView(sending, 0);

    assertEq(amountSent, sending);
    assertEq(amountReceiving, sending - fee);
  }

  function test_updateCrossChainFee_asUser_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.updateCrossChainFee(1);
  }

  function test_updateCrossChainFee_asOwner_givenFeeHigherThan10Percents_thenReverts() external prankAs(owner) {
    vm.expectRevert(OFT20Ticker.FeeTooHigh.selector);
    underTest.updateCrossChainFee(1001);
  }

  function test_updateCrossChainFee_asOwner_thenUpdates() external prankAs(owner) {
    underTest.updateCrossChainFee(1);

    assertEq(underTest.crossChainFee(), 1);
  }

  function test_updateFeeCollector_asUser_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.updateFeeCollector(address(0));
  }

  function test_updateFeeCollector_asOwner_givenEmptyAddress_thenReverts() external prankAs(owner) {
    vm.expectRevert(OFT20Ticker.EmptyFeeCollector.selector);
    underTest.updateFeeCollector(address(0));
  }

  function test_updateFeeCollector_asOwner_thenUpdates() external prankAs(owner) {
    underTest.updateFeeCollector(user);
    assertEq(underTest.feeCollector(), user);
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

  function _getCrosschainFee(uint256 _amount) private pure returns (uint256) {
    return Math.mulDiv(_amount, CROSS_CHAIN_FEE, 10_000);
  }
}

contract OFT20TickerHarness is OFT20Ticker {
  uint256 public constant REWARD_PER_MINT = 60e18;

  constructor(
    string memory _name,
    string memory _symbol,
    address _feeCollector,
    uint32 _crossChainFee,
    HeroOFTXOperatorArgs memory _heroArgs
  ) OFT20Ticker(_name, _symbol, _feeCollector, _crossChainFee, _heroArgs) { }

  function _onValidatorSameChain(address _to) internal override returns (uint256 totalMinted_) {
    _mint(_to, REWARD_PER_MINT);
    return REWARD_PER_MINT;
  }

  function _onValidatorCrossChain(address)
    internal
    pure
    override
    returns (uint256 tokenIdOrAmount_, uint256 totalMinted_, bool success_)
  {
    return (REWARD_PER_MINT, REWARD_PER_MINT, true);
  }

  function exposed_onValidatorCrossChainFailed(address _to, uint256 _amount) external {
    _onValidatorCrossChainFailed(_to, _amount);
  }

  function exposed_mint(address _to, uint256 _amount) external {
    _mint(_to, _amount);
  }

  function exposed_debit(uint256 _amount, uint256 _mintAmount) external returns (uint256 amountReceiving) {
    return _debit(_amount, _mintAmount);
  }

  function exposed_debitView(uint256 _amountLD, uint256 _minAmountLD)
    external
    view
    returns (uint256 amountSentLD, uint256 amountReceivedLD)
  {
    return _debitView(_amountLD, _minAmountLD);
  }

  function exposed_credit(address _to, uint256 _value, bool _isFrozen) external returns (uint256) {
    return _credit(_to, _value, _isFrozen);
  }
}
