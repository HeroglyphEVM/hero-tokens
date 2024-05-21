// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { OFT721 } from "src/tokens/ERC721/OFT721.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SendNativeHelper } from "src/SendNativeHelper.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title KeyOFT721
 * @notice Each Heroglyph Tokens are linked to a key, without the key, you can not mint the Token
 */
contract KeyOFT721 is OFT721, SendNativeHelper {
  using SafeERC20 for IERC20Metadata;

  error InvalidAmount();
  error NoETHNedded();
  error CannotBeBoughtHere();
  error MaxSupplyReached();

  IERC20Metadata public immutable inputToken;
  uint256 public immutable maxSupply;
  address public immutable treasury;
  uint256 public immutable cost;
  uint256 public totalSupply;

  string internal displayName;
  string internal imageURI;

  constructor(
    string memory _name,
    string memory _symbol,
    string memory _displayName,
    string memory _imageURI,
    address _owner,
    address _localLzEndpoint,
    uint32 _lzGasLimit,
    uint256 _maxSupply,
    uint256 _cost,
    address _inputToken,
    address _treasury
  ) OFT721(_name, _symbol, "", _owner, _localLzEndpoint, _lzGasLimit) {
    if (_treasury == address(0)) revert("Treasury is Zero");

    maxSupply = _maxSupply;
    cost = _cost;
    inputToken = IERC20Metadata(_inputToken);
    treasury = _treasury;
    displayName = _displayName;
    imageURI = _imageURI;
  }

  function buy() external payable {
    if (cost == 0) revert CannotBeBoughtHere();

    uint256 cacheTotalSupply = totalSupply + 1;

    if (address(inputToken) == address(0) && msg.value != cost) revert InvalidAmount();
    if (address(inputToken) != address(0)) {
      if (msg.value != 0) revert NoETHNedded();
      inputToken.safeTransferFrom(msg.sender, treasury, cost);
    }

    if (maxSupply != 0 && cacheTotalSupply > maxSupply) revert MaxSupplyReached();

    _safeMint(msg.sender, cacheTotalSupply);
    totalSupply = cacheTotalSupply;

    _sendNative(treasury, msg.value, true);
  }

  function getCostInWEI() external view returns (uint256) {
    if (address(inputToken) == address(0)) return cost;

    uint8 decimals = inputToken.decimals();
    if (decimals < 18) return cost * (10 ** (18 - decimals));

    return cost;
  }

  function tokenURI(uint256 tokenId) public view override returns (string memory) {
    _requireOwned(tokenId);

    string memory data = string(
      abi.encodePacked(
        '{"name":"',
        displayName,
        Strings.toString(tokenId),
        '","description":"Unlock one of the Heroglyph`s tickers","image":"',
        imageURI,
        '"}'
      )
    );

    return string(abi.encodePacked("data:application/json;utf8,", data));
  }
}
