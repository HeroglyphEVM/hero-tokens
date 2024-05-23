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
    address genesisHub;
    GenesisConfiguration configuration;
  }

  error NoRedeemTokenDectected();
  error RewardLowerThanMinimumAllowed();
  error NoRewardCurrently();
  error RedeemDecayTooHigh();
  error NoKeyDetected();
  error NotgenesisHub();

  event TokenRedeemed(address indexed from, uint256 reward);
  event ConfigurationUpdated(GenesisConfiguration configuration);
  event genesisHubUpdated(address genesisHub);

  function redeem(address _to, uint256 _multiplier) external returns (uint256 rewardMinted_);
  function getNextReward() external view returns (uint256 redeemReward_, uint256 blockProducingReward_);
  function getConfiguration() external view returns (GenesisConfiguration memory);
}
