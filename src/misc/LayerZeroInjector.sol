// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { HeroOFTX, MessagingFee, MessagingReceipt } from "../tokens/HeroOFTX.sol";
import { BaseOFT20, ERC20 } from "../tokens/ERC20/BaseOFT20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OApp } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";

/**
 * @title LayerZeroInjector
 * @notice Addresses a LayerZero V2 issue where large transfers (> uint64.max) caused token loss.
 * This contract injects missing tokens into the genesis tokens' contract as a workaround.
 * @dev Ref of the issue https://github.com/LayerZero-Labs/LayerZero-v2/pull/82
 * @dev This injector shall be deployed on unused chain by genesis like bsc, to assure we don't break the
 * natural flow while fixing it.
 *
 * @dev https://layerzeroscan.com/tx/0x943390cf44055a73286b94d9fff40bb547e5e82c76946f382223f58c552f7e72
 * @dev https://layerzeroscan.com/tx/0xd9872bd02511cbe6625569b6f7d361e7405931ffa89aa59274f9b547e134e0db
 */
//30102
contract LayerZeroInjector is HeroOFTX(200_000), BaseOFT20(18) {
  mapping(address gensisTokenMissing => uint256 amountToMint) public amountToMint;

  constructor(address _owner, address _endpoint) OApp(_endpoint, _owner) Ownable(_owner) ERC20("Injector", "inj") {
    //SANIC
    amountToMint[0xE2eca013A124FBcE7F7507a66FDf9Ad2e22d999B] = 171_535_000_000_000e18 - 5_514_416_086_614e18;
    //frxBULLAS
    amountToMint[0x3Ec67133bB7d9D2d93D40FBD9238f1Fb085E01eE] = 109_999_000_000_000e18 - 17_766_279_631_452e18;
    //GNOBBY
    amountToMint[0x1a8805194D0eF2F73045a00c70Da399d9E74221c] = 2_017_040_000_000_000e18 - 6_347_297_665_659e18;
    //KABOSUCHAN
    amountToMint[0x9e949461F9EC22C6032cE26Ea509824Fd2f6d98f] = 196_490_000_000_000e18 - 12_022_647_482_916e18;
  }

  function inject(uint32 _dstEid, uint256 _maxLoop) external onlyOwner {
    address genesis = address(uint160(uint256(_getPeerOrRevert(_dstEid))));
    uint256 toMint = amountToMint[genesis];
    uint256 uint64MaxLD = _toLD(type(uint64).max);

    if (toMint == 0) revert("Nothing to Mint");
    if (_maxLoop == 0) _maxLoop = type(uint256).max;

    bytes memory payload;
    MessagingFee memory fee;
    MessagingReceipt memory msgReceipt;
    uint256 minting;

    for (uint256 i = 0; i < _maxLoop; ++i) {
      if (toMint == 0) break;

      minting = (toMint > uint64MaxLD) ? uint64MaxLD : toMint;
      toMint -= minting;

      payload = abi.encode(0x888D768764A2E304215247F0bA3457cCb0f0ab4f, _toSharedDecimals(minting), 0);
      fee = _estimateFee(_dstEid, payload, defaultLzOption);

      msgReceipt = _lzSend(_dstEid, payload, defaultLzOption, fee, payable(msg.sender));

      emit OFTSent(msgReceipt.guid, _dstEid, msg.sender, minting);
    }

    amountToMint[genesis] = toMint;
  }

  function _payNative(uint256 _nativeFee) internal override returns (uint256 nativeFee) {
    uint256 balance = address(this).balance;

    if (msg.value != 0 && msg.value != _nativeFee) revert NotEnoughNative(msg.value);
    if (msg.value == 0 && balance < _nativeFee) revert NotEnoughNative(balance);

    return _nativeFee;
  }

  function _toSharedDecimals(uint256 _value) internal view override returns (uint64) {
    return _toSD(_value);
  }

  function _credit(address, uint256, bool) internal pure override returns (uint256) {
    return 0;
  }

  function _debit(uint256, uint256) internal pure override returns (uint256 amountReceiving_) {
    return 0;
  }

  receive() external payable { }

  function withdrawETH() external onlyOwner {
    (bool success,) = msg.sender.call{ value: address(this).balance }("");
    if (!success) revert("Failed to send ETH");
  }
}
