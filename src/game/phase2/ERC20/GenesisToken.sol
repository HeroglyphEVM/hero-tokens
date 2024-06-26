// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { OFT20Ticker } from "src/tokens/ERC20/OFT20Ticker.sol";
import { IGenesisToken } from "./../interface/IGenesisToken.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IGenesisHub } from "./../IGenesisHub.sol";

contract GenesisToken is OFT20Ticker, IGenesisToken {
  uint256 public constant SECOND_PER_BLOCK = 12;

  address public genesisHub;
  uint32 public lastMintTriggered;

  GenesisConfiguration private configuration;

  constructor(GenesisConstructor memory _args, HeroOFTXOperatorArgs memory _heroArgs)
    OFT20Ticker(_args.name, _args.symbol, _heroArgs.treasury, _args.crossChainFee, _heroArgs)
  {
    lastMintTriggered = uint32(block.timestamp);
    genesisHub = _args.genesisHub;
    configuration = _args.configuration;

    uint256 preMint = _args.preMintAmount;
    if (preMint == 0) return;

    _mint(_heroArgs.treasury, preMint);
    totalMintedSupply += preMint;
  }

  function _onValidatorSameChain(address _to) internal override returns (uint256) {
    return _executeMint(_to, true, 1);
  }

  function _onValidatorCrossChain(address)
    internal
    override
    returns (uint256 tokenIdOrAmount_, uint256 totalMinted_, bool success_)
  {
    tokenIdOrAmount_ = _executeMint(address(0), true, 1);
    return (tokenIdOrAmount_, tokenIdOrAmount_, tokenIdOrAmount_ != 0);
  }

  function redeem(address _to, uint256 _multiplier) external override returns (uint256 rewardMinted_) {
    if (msg.sender != genesisHub) revert NotgenesisHub();
    if (address(key) != address(0) && key.balanceOf(_to) == 0) revert NoKeyDetected();

    rewardMinted_ = _executeMint(address(0), false, _multiplier);
    totalMintedSupply += rewardMinted_;

    _mint(_to, rewardMinted_);

    emit TokenRedeemed(_to, rewardMinted_);
    return rewardMinted_;
  }

  function _executeMint(address _to, bool _isMining, uint256 _multiplier) internal returns (uint256 reward_) {
    reward_ = _calculateTokensToEmit(uint32(block.timestamp), _isMining, _multiplier);
    lastMintTriggered = uint32(block.timestamp);

    if (_to != address(0)) _mint(_to, reward_);

    return reward_;
  }

  function getNextReward(uint256 _multiplier)
    external
    view
    override
    returns (uint256 redeemReward_, uint256 blockProducingReward_)
  {
    if (_multiplier == 0) _multiplier = 1;

    redeemReward_ = _calculateTokensToEmit(uint32(block.timestamp), false, _multiplier);
    blockProducingReward_ = _calculateTokensToEmit(uint32(block.timestamp), true, _multiplier);

    return (redeemReward_, blockProducingReward_);
  }

  function _calculateTokensToEmit(uint32 _timestamp, bool _withBonus, uint256 _multiplier)
    internal
    view
    returns (uint256 minting_)
  {
    GenesisConfiguration memory config = configuration;
    uint256 bonus = 0;

    if (_withBonus) {
      uint256 bonusRate = config.maxBonusFullDay / 1 days;
      uint256 timePassed = (_timestamp - lastMintTriggered);

      bonus = timePassed * bonusRate;
    }

    minting_ = IGenesisHub(genesisHub).applyDifficulty(config.fixedRate * _multiplier);
    minting_ += Math.min(bonus, config.maxBonusFullDay);

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

  function updateGenesisHub(address _genesisHub) external onlyOwner {
    genesisHub = _genesisHub;
    emit genesisHubUpdated(_genesisHub);
  }

  function getConfiguration() external view override returns (GenesisConfiguration memory) {
    return configuration;
  }
}
