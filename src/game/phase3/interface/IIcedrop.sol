// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { LockupLinear } from "@sablier/v2-core/src/types/DataTypes.sol";

interface IIcedrop {
  error NotSupported();
  error Misconfiguration();
  error IcedropAlreadyStarted();
  error AlreadyCalledIcedrop();
  error NotKeyOwner();
  error IcedropNotStarted();
  error NotEnoughToGamble();
  error RemoveMsgValueIfNotGambling();
  error NotRandomizerAI();
  error GamblingAlreadyExecuted();
  error InsufficientFeeCost();
  error MaxRetryReached();
  error GamblingDealAccepted();
  error GamblingNotExecuted();
  error NotEnoughTokenInContract();
  error KeyIsNotSoldOut();
  error FailedToSendETH();

  event GamblingRequestSent(bytes32 indexed keyHash, uint256 indexed randomizerRequestId);
  event GamblingRequestReceived(uint256 indexed randomizerRequestId, bytes32 value);
  event IcedropStarted(address indexed genesisKey, address indexed output, uint256 allowedAmount);
  event IcedropCalled(address indexed user, address indexed genesisKey, uint256 indexed keyId, bytes32 keyHash);
  event StreamStarted(address indexed caller, bytes32 indexed keyHash, uint256 indexed streamId);
  event GamblingCostUpdated(uint256 cost);
  event TreasuryUpdated(address treasury);
  event SupportedTokenUpdated(address indexed genesisKey, SupportedTokenData supportedTokenData);

  struct SupportedTokenData {
    address genesisKey;
    address output;
    uint128 maxOutputToken;
    bool started;
  }

  struct GamblingData {
    LockupLinear.CreateWithDurations streamParams;
    bytes32 keyHash;
    uint256 seed;
    address caller;
    bool executed;
    bool retried;
    bool accepted;
  }

  struct StreamingData {
    uint256 streamId;
    uint128 amount;
    uint32 start;
    uint32 end;
  }

  /**
   * @notice Start the Icedrop of a genesis key
   * @param _key Genesis Key
   * @dev Genesis Key needs to be fully sold out
   */
  function initializeIcedrop(address _key) external;

  /**
   * @notice Start your Vesting of your Icedrop
   * @param _key Genesis Key
   * @param _id  Genesis NFT Key ID
   * @param _gambling use gambling option, in which the linear duration will be randomized betwee 1 to MAX_DURATION
   * @dev `_gambling` is not free and requires to paid the RandomizerAI fee & `gamblingCost`
   */
  function startVesting(address _key, uint256 _id, bool _gambling) external payable;

  /**
   * @notice Accept the gambling result
   * @param _keyHash keccak256(abi.encode(GenesisKey, NFT Id))
   */
  function acceptGamblingResult(bytes32 _keyHash) external;

  /**
   * @notice Retry the gambling one more time at the same cost
   * @param _keyHash keccak256(abi.encode(GenesisKey, NFT Id))
   * @dev can only retry once
   */
  function retryGambling(bytes32 _keyHash) external payable;

  /**
   * @notice Get gambling request data
   * @param _randomizerIdRequest ID of the request on RandomizerAI
   */
  function getGamblingRequest(uint256 _randomizerIdRequest) external view returns (GamblingData memory);

  /**
   * @notice Get Gambling Week result
   * @param _keyHash keccak256(abi.encode(GenesisKey, NFT Id))
   * @dev Revert if the gambling request is missing or not done
   */
  function getGamblingWeekResult(bytes32 _keyHash) external view returns (uint256);

  /**
   * @notice get supported token metadata
   * @param _genesisKey Genesis Key Address
   */
  function getGenesisKeySupport(address _genesisKey) external view returns (SupportedTokenData memory);

  /**
   * @notice Get streaming data
   * @param _keyHash keccak256(abi.encode(GenesisKey, NFT Id))
   */
  function getKeyStreamingData(bytes32 _keyHash) external view returns (StreamingData memory);
}
