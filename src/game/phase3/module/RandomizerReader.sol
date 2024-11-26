// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IRandomizer } from "../vendor/IRandomizer.sol";

contract RandomizerReader {
  uint32 public constant MAX_GAS_RANDOMIZER = 100_000;

  error RandomizerFee(uint256 fee);

  IRandomizer public immutable randomizer;

  constructor(address _randomizerAI) {
    randomizer = IRandomizer(_randomizerAI);
  }

  function getFee() external returns (uint256) {
    revert RandomizerFee(randomizer.estimateFee(MAX_GAS_RANDOMIZER));
  }
}
