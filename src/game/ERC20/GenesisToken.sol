// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { OFT20Ticker } from "./../../tokens/ERC20/OFT20Ticker.sol";
import { IGenesisToken } from "./../interface/IGenesisToken.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract GenesisToken is OFT20Ticker, IGenesisToken {
  uint256 public constant SECOND_PER_BLOCK = 12;

  address public redeemHub;
  uint32 public lastMintTriggered;

  GenesisConfiguration private configuration;

  constructor(GenesisConstructor memory _args, HeroOFTXOperatorArgs memory _heroArgs)
    OFT20Ticker(_args.name, _args.symbol, _heroArgs.treasury, _args.crossChainFee, _heroArgs)
  {
    lastMintTriggered = uint32(block.timestamp);
    redeemHub = _args.redeemHub;
    configuration = _args.configuration;

    uint256 preMint = _args.preMintAmount;
    if (preMint == 0) return;

    _mint(_heroArgs.treasury, preMint);
    totalMintedSupply += preMint;
  }

  function _onValidatorSameChain(address _to) internal override returns (uint256) {
    return _executeMint(_to, true);
  }

  function _onValidatorCrossChain(address)
    internal
    override
    returns (uint256 tokenIdOrAmount_, uint256 totalMinted_, bool success_)
  {
    tokenIdOrAmount_ = _executeMint(address(0), true);
    return (tokenIdOrAmount_, tokenIdOrAmount_, tokenIdOrAmount_ != 0);
  }

  function redeem(address _to) external returns (uint256 rewardMinted_) {
    if (msg.sender != redeemHub) revert NotRedeemHub();
    if (address(key) != address(0) && key.balanceOf(_to) == 0) revert NoKeyDetected();

    rewardMinted_ = _executeMint(address(0), false);
    totalMintedSupply += rewardMinted_;

    _mint(_to, rewardMinted_);

    emit TokenRedeemed(_to, rewardMinted_);
    return rewardMinted_;
  }

  function _executeMint(address _to, bool _isMining) internal returns (uint256 reward_) {
    reward_ = _calculateTokensToEmit(uint32(block.timestamp), _isMining);
    lastMintTriggered = uint32(block.timestamp);

    if (_to != address(0)) _mint(_to, reward_);

    return reward_;
  }

  function getNextReward() external view returns (uint256 redeemReward_, uint256 blockProducingReward_) {
    redeemReward_ = _calculateTokensToEmit(uint32(block.timestamp), false);
    blockProducingReward_ = _calculateTokensToEmit(uint32(block.timestamp), true);

    return (redeemReward_, blockProducingReward_);
  }

  function _calculateTokensToEmit(uint32 _timestamp, bool _withBonus) internal view returns (uint256 minting_) {
    GenesisConfiguration memory config = configuration;
    uint256 bonus = 0;

    if (_withBonus) {
      uint256 bonusRate = config.maxBonusFullDay / 1 days;
      uint256 timePassed = (_timestamp - lastMintTriggered);

      bonus = timePassed * bonusRate;
    }

    minting_ = config.fixedRate + Math.min(bonus, config.maxBonusFullDay);

    uint256 totalMintedSupplyCached = totalMintedSupply;
    uint256 maxSupplyCached = maxSupply;

    if (totalMintedSupplyCached >= maxSupplyCached) return 0;
    if (totalMintedSupplyCached + minting_ <= maxSupplyCached) return minting_;

    return maxSupplyCached - totalMintedSupplyCached;
  }

  function updateConfiguration(GenesisConfiguration calldata _configuration) external onlyOwner {
    configuration = _configuration;
    emit ConfigurationUpdated(_configuration);
  }

  function updateRedeemHub(address _redeemHub) external onlyOwner {
    redeemHub = _redeemHub;
    emit RedeemHubUpdated(_redeemHub);
  }

  function getConfiguration() external view returns (GenesisConfiguration memory) {
    return configuration;
  }
}
