// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../BaseScript.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract DeployTokensScript is BaseScript {
  struct ULNConfigStructType {
    uint64 confirmations;
    uint8 requiredDVNCount;
    uint8 optionalDVNCount;
    uint8 optionalDVNThreshold;
    address[] requiredDVNs;
    address[] optionalDVNs;
  }

  struct ExecutorConfigStructType {
    uint32 maxMessageSize;
    address executorAddress;
  }

  uint256 private activeDeployer;
  address private deployerWallet;

  function run() external {
    activeDeployer = _getDeployerPrivateKey();
    deployerWallet = _getDeployerAddress();
  }
}
