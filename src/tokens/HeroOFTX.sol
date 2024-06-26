// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IHeroOFTX } from "./IHeroOFTX.sol";
import { HeroOFTXCallbacks } from "./HeroOFTXCallbacks.sol";
import { HeroOFTErrors } from "./HeroOFTErrors.sol";

import { OApp, MessagingFee, MessagingReceipt, Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

/**
 * @title HeroOFTX
 * @notice Base OFT LZv2 with TickerOperation support
 */
abstract contract HeroOFTX is IHeroOFTX, HeroOFTXCallbacks, OApp, HeroOFTErrors {
  using OptionsBuilder for bytes;

  uint32 public lzGasLimit;
  bytes public defaultLzOption;

  constructor(uint32 _lzGasLimit) {
    _updateLayerZeroGasLimit(_lzGasLimit);
  }

  function send(uint32 _dstEid, address _to, uint256 _amountIn, uint256 _minAmountOut)
    external
    payable
    returns (MessagingReceipt memory msgReceipt)
  {
    bytes memory option = defaultLzOption;
    uint256 amountOrIdReceiving = _debit(_amountIn, _minAmountOut);

    if (amountOrIdReceiving < _minAmountOut) {
      revert SlippageExceeded(amountOrIdReceiving, _minAmountOut);
    }

    bytes memory payload = _generateMessage(_to, amountOrIdReceiving);
    MessagingFee memory fee = _estimateFee(_dstEid, payload, option);

    msgReceipt = _lzSend(_dstEid, payload, option, fee, payable(msg.sender));

    emit OFTSent(msgReceipt.guid, _dstEid, msg.sender, amountOrIdReceiving);

    return msgReceipt;
  }

  function _lzReceive(
    Origin calldata _origin,
    bytes32 _guid,
    bytes calldata _message,
    address, /*_executor*/ // @dev unused in the default implementation.
    bytes calldata /*_extraData*/ // @dev unused in the default implementation.
  ) internal virtual override {
    (address to, uint256 idOrAmount) = abi.decode(_message, (address, uint256));
    uint256 amountReceivedLD = _credit(to, idOrAmount, false);

    emit OFTReceived(_guid, _origin.srcEid, to, amountReceivedLD);
  }

  function estimateFee(uint32 _dstEid, address _to, uint256 _tokenId) external view returns (uint256) {
    return _estimateFee(_dstEid, _generateMessage(_to, _tokenId), defaultLzOption).nativeFee;
  }

  function _generateMessage(address _to, uint256 _amountOrId) internal view virtual returns (bytes memory) {
    return abi.encode(_to, _amountOrId);
  }

  function _estimateFee(uint32 _dstEid, bytes memory _message, bytes memory _options)
    internal
    view
    returns (MessagingFee memory fee_)
  {
    return _quote(_dstEid, _message, _options, false);
  }

  /**
   * @notice updateLayerZeroGasLimit Set a new gas limit for LZ
   * @param _lzGasLimit gas limit of a LZ Message execution
   */
  function updateLayerZeroGasLimit(uint32 _lzGasLimit) external virtual onlyOwner {
    _updateLayerZeroGasLimit(_lzGasLimit);
  }

  function _updateLayerZeroGasLimit(uint32 _lzGasLimit) internal virtual {
    if (_lzGasLimit == 0) revert GasLimitCannotBeZero();

    lzGasLimit = _lzGasLimit;
    defaultLzOption = OptionsBuilder.newOptions().addExecutorLzReceiveOption(lzGasLimit, 0);
  }
}
