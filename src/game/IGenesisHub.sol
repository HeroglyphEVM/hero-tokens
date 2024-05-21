// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IGenesisHub {
  struct RedeemSettings {
    address tokenInput;
    uint256 ratePerRedeem;
  }

  error InvalidDifficulty();

  event RedeemToken(address indexed caller, address indexed token, uint256 reward);
  event RedeemSettingUpdated(address indexed token, RedeemSettings settings);
  event GlobalDifficultyUpdated(uint256 difficulty);

  function redeem(address _genesisToken, uint256 _redeemMultiplier) external;

  function getRedeemSettings(address _genesisToken) external view returns (RedeemSettings memory);

  function applyDifficulty(uint256 _reward) external view returns (uint256);
}
