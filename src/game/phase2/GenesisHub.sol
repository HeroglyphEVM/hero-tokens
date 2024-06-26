// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IGenesisToken } from "./interface/IGenesisToken.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IGenesisHub } from "./IGenesisHub.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract GenesisHub is IGenesisHub, Ownable {
  uint256 public constant MAX_DIFFICULTY = 1e18;

  uint256 public difficulty;
  mapping(address genesisToken => RedeemSettings) private redeemSettings;

  constructor(address _owner) Ownable(_owner) {
    difficulty = Math.mulDiv(350, 1e18, 86_400);
  }

  function applyDifficulty(uint256 _reward) external view returns (uint256) {
    return Math.mulDiv(_reward, MAX_DIFFICULTY - difficulty, MAX_DIFFICULTY);
  }

  function redeem(address _genesisToken, uint256 _redeemMultiplier) external {
    RedeemSettings memory settings = redeemSettings[_genesisToken];

    ERC20(settings.tokenInput).transferFrom(msg.sender, address(this), _redeemMultiplier * settings.ratePerRedeem);
    uint256 reward = IGenesisToken(_genesisToken).redeem(msg.sender, _redeemMultiplier);

    emit RedeemToken(msg.sender, _genesisToken, reward);
  }

  function setRedeemSettings(address[] calldata _genesisToken, RedeemSettings[] calldata _settings) external onlyOwner {
    for (uint256 i = 0; i < _genesisToken.length; ++i) {
      _setRedeemSetting(_genesisToken[i], _settings[i]);
    }
  }

  function setRedeemSetting(address _genesisToken, RedeemSettings calldata _settings) external onlyOwner {
    _setRedeemSetting(_genesisToken, _settings);
  }

  function _setRedeemSetting(address _genesisToken, RedeemSettings calldata _settings) internal {
    redeemSettings[_genesisToken] = _settings;
    emit RedeemSettingUpdated(_genesisToken, _settings);
  }

  function updateGlobalDifficulty(uint256 _difficulty) external onlyOwner {
    if (_difficulty > MAX_DIFFICULTY) revert InvalidDifficulty();

    difficulty = _difficulty;
    emit GlobalDifficultyUpdated(_difficulty);
  }

  function getRedeemSettings(address _genesisToken) external view returns (RedeemSettings memory) {
    return redeemSettings[_genesisToken];
  }
}
