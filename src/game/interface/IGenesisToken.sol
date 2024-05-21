// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IGenesisToken {
  struct GenesisConfiguration {
    uint256 fixedRate;
    uint256 maxBonusFullDay;
  }

  struct GenesisConstructor {
    string name;
    string symbol;
    uint32 crossChainFee;
    uint256 preMintAmount;
    address redeemHub;
    GenesisConfiguration configuration;
  }

  error NoRedeemTokenDectected();
  error RewardLowerThanMinimumAllowed();
  error NoRewardCurrently();
  error RedeemDecayTooHigh();
  error NoKeyDetected();
  error NotRedeemHub();

  event TokenRedeemed(address indexed from, uint256 reward);
  event ConfigurationUpdated(GenesisConfiguration configuration);
  event RedeemHubUpdated(address redeemHub);
}
