// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IIcedrop } from "../interface/IIcedrop.sol";

import { KeyOFT721 } from "../../phase2/ERC721/KeyOFT721.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ud60x18 } from "@prb-math/src/UD60x18.sol";
import { ISablierV2LockupLinear } from "@sablier/v2-core/src/interfaces/ISablierV2LockupLinear.sol";
import { Broker, LockupLinear } from "@sablier/v2-core/src/types/DataTypes.sol";
import { IRandomizer } from "../vendor/IRandomizer.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract Icedrop is IIcedrop, Ownable {
  uint32 public constant MIN_WEEKS = 1;
  uint32 public constant MAX_WEEKS = 18;
  uint32 public constant MIN_DURATION = 1 weeks * MIN_WEEKS;
  uint32 public constant MAX_DURATION = 1 weeks * MAX_WEEKS;
  uint32 public constant DEFAULT_DURATION = 6 weeks;
  uint32 public constant CLIFF_DURATION = 3 weeks;
  uint32 public constant MAX_GAS_RANDOMIZER = 100_000;

  ISablierV2LockupLinear public immutable sablier;
  IRandomizer public immutable randomizer;
  address public treasury;
  uint256 public gamblingCost;

  mapping(address genesis => SupportedTokenData) internal genesisKeys;
  mapping(bytes32 keyHash => bool) public calledIcedrop;
  mapping(bytes32 keyHash => uint256 id) public keyHashGamblingId;
  mapping(bytes32 keyHash => StreamingData) internal keyStreamingData;
  mapping(uint256 requestId => GamblingData) internal gamblingRequests;

  constructor(
    address _owner,
    address _treasury,
    address _sablier,
    address _randomizerAI,
    SupportedTokenData[] memory _supports
  ) Ownable(_owner) {
    sablier = ISablierV2LockupLinear(_sablier);
    randomizer = IRandomizer(_randomizerAI);
    gamblingCost = 0.01e18;
    treasury = _treasury;

    SupportedTokenData memory support;
    for (uint256 i = 0; i < _supports.length; ++i) {
      support = _supports[i];
      genesisKeys[support.genesisKey] = support;

      emit SupportedTokenUpdated(support.genesisKey, support);
    }
  }

  /// @inheritdoc IIcedrop
  function initializeIcedrop(address _key) external override {
    SupportedTokenData storage support = genesisKeys[_key];
    _initializeIcedrop(support, _key);
  }

  /// @inheritdoc IIcedrop
  function startVesting(address _key, uint256 _id, bool _gambling) external payable override {
    SupportedTokenData storage support = genesisKeys[_key];
    bytes32 keyHash = keccak256(abi.encode(_key, _id));

    if (!support.started) {
      _initializeIcedrop(support, _key);
    }

    if (!_gambling && msg.value != 0) revert RemoveMsgValueIfNotGambling();
    if (_gambling && msg.value < gamblingCost) revert NotEnoughToGamble();
    if (KeyOFT721(_key).ownerOf(_id) != msg.sender) revert NotKeyOwner();
    if (calledIcedrop[keyHash]) revert AlreadyCalledIcedrop();

    calledIcedrop[keyHash] = true;

    LockupLinear.CreateWithDurations memory params = LockupLinear.CreateWithDurations({
      sender: address(this),
      recipient: msg.sender,
      totalAmount: uint128(support.maxOutputToken / KeyOFT721(_key).maxSupply()), //maxSupply is not in WEI
      asset: IERC20(support.output),
      cancelable: false,
      transferable: false,
      durations: LockupLinear.Durations({ cliff: CLIFF_DURATION, total: CLIFF_DURATION + DEFAULT_DURATION }),
      broker: Broker(address(0), ud60x18(0))
    });

    emit IcedropCalled(msg.sender, _key, _id, keyHash);

    if (!_gambling) {
      _createVesting(msg.sender, keyHash, params);
    } else {
      _createGamblingRequest(keyHash, false, params);
    }
  }

  function _initializeIcedrop(SupportedTokenData storage support, address _key) internal {
    address output = support.output;
    uint256 maxOutput = support.maxOutputToken;

    if (KeyOFT721(_key).totalSupply() != KeyOFT721(_key).maxSupply()) revert KeyIsNotSoldOut();
    if (support.output == address(0)) revert NotSupported();
    if (maxOutput == 0) revert Misconfiguration();
    if (IERC20(output).balanceOf(address(this)) < maxOutput) revert NotEnoughTokenInContract();
    if (support.started) revert IcedropAlreadyStarted();

    support.started = true;

    IERC20(output).approve(address(sablier), maxOutput);

    emit IcedropStarted(_key, support.output, maxOutput);
  }

  /// @inheritdoc IIcedrop
  function acceptGamblingResult(bytes32 _keyHash) external override {
    GamblingData storage gamblingData = gamblingRequests[keyHashGamblingId[_keyHash]];
    LockupLinear.CreateWithDurations memory params = gamblingData.streamParams;

    if (gamblingData.caller != msg.sender) revert NotKeyOwner();
    if (gamblingData.accepted) revert GamblingDealAccepted();
    if (!gamblingData.executed) revert GamblingNotExecuted();

    gamblingData.accepted = true;
    uint256 weeksInSecond = 1 weeks * (gamblingData.seed % MAX_WEEKS + MIN_WEEKS);

    params.durations = LockupLinear.Durations({ cliff: CLIFF_DURATION, total: CLIFF_DURATION + uint40(weeksInSecond) });

    _createVesting(msg.sender, _keyHash, params);
  }

  /// @inheritdoc IIcedrop
  function retryGambling(bytes32 _keyHash) external payable override {
    if (msg.value < (gamblingCost * 2)) revert NotEnoughToGamble();

    GamblingData memory gamblingData = gamblingRequests[keyHashGamblingId[_keyHash]];
    if (gamblingData.caller != msg.sender) revert NotKeyOwner();
    if (gamblingData.accepted) revert GamblingDealAccepted();
    if (!gamblingData.executed) revert GamblingNotExecuted();
    if (gamblingData.retried) revert MaxRetryReached();

    _createGamblingRequest(_keyHash, true, gamblingData.streamParams);
  }

  function _createGamblingRequest(bytes32 _keyHash, bool _retried, LockupLinear.CreateWithDurations memory _params)
    internal
  {
    uint256 fee = randomizer.estimateFee(MAX_GAS_RANDOMIZER);
    uint256 cachedGamblingCost = gamblingCost * (_retried ? 2 : 1);

    if ((msg.value - cachedGamblingCost) != fee) revert InsufficientFeeCost();

    randomizer.clientDeposit{ value: fee }(address(this));

    uint256 randomizerRequestID = randomizer.request(MAX_GAS_RANDOMIZER);

    gamblingRequests[randomizerRequestID] = GamblingData({
      caller: msg.sender,
      keyHash: _keyHash,
      streamParams: _params,
      executed: false,
      accepted: false,
      seed: 0,
      retried: _retried
    });

    keyHashGamblingId[_keyHash] = randomizerRequestID;

    if (cachedGamblingCost > 0) {
      (bool success,) = treasury.call{ value: cachedGamblingCost }("");
      if (!success) revert FailedToSendETH();
    }

    emit GamblingRequestSent(_keyHash, randomizerRequestID);
  }

  function randomizerCallback(uint256 _id, bytes32 _value) external {
    GamblingData storage gamblingData = gamblingRequests[_id];

    if (msg.sender != address(randomizer)) revert NotRandomizerAI();
    if (gamblingData.executed) revert GamblingAlreadyExecuted();

    gamblingData.executed = true;
    gamblingData.seed = uint256(_value);

    emit GamblingRequestReceived(_id, _value);
  }

  function _createVesting(address _caller, bytes32 _keyHash, LockupLinear.CreateWithDurations memory _params) internal {
    uint256 streamId = sablier.createWithDurations(_params);

    keyStreamingData[_keyHash] = StreamingData({
      streamId: streamId,
      amount: _params.totalAmount,
      start: uint32(block.timestamp),
      end: uint32(block.timestamp + _params.durations.total)
    });

    emit StreamStarted(_caller, _keyHash, streamId);
  }

  function randomizerWithdraw(uint256 amount) external onlyOwner {
    randomizer.clientWithdrawTo(msg.sender, amount);
  }

  function updateTreasury(address _treasury) external onlyOwner {
    treasury = _treasury;
    emit TreasuryUpdated(_treasury);
  }

  function updateGamblingCost(uint256 _cost) external onlyOwner {
    gamblingCost = _cost;
    emit GamblingCostUpdated(_cost);
  }

  function updateSupportedToken(SupportedTokenData memory _support) external onlyOwner {
    genesisKeys[_support.genesisKey] = _support;
    emit SupportedTokenUpdated(_support.genesisKey, _support);
  }

  /// @inheritdoc IIcedrop
  function getGenesisKeySupport(address _genesisKey) external view override returns (SupportedTokenData memory) {
    return genesisKeys[_genesisKey];
  }

  /// @inheritdoc IIcedrop
  function getGamblingRequest(uint256 _randomizerIdRequest) external view override returns (GamblingData memory) {
    return gamblingRequests[_randomizerIdRequest];
  }

  /// @inheritdoc IIcedrop
  function getGamblingWeekResult(bytes32 _keyHash) external view override returns (uint256) {
    GamblingData memory gamblingData = gamblingRequests[keyHashGamblingId[_keyHash]];
    return !gamblingData.executed ? 0 : gamblingData.seed % MAX_WEEKS + MIN_WEEKS;
  }

  /// @inheritdoc IIcedrop
  function getKeyStreamingData(bytes32 _keyHash) external view override returns (StreamingData memory) {
    return keyStreamingData[_keyHash];
  }

  receive() external payable { }
}
