// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

abstract contract DeployUtils {
  struct Config {
    address owner;
    address treasury;
    address lzEndpoint;
    uint32 lzDeploymentChainEndpointId;
    address nativeTokenWrapped;
    bool isTestnet;
    address heroglyphAttestation;
    address heroglyphRelay;
  }

  string internal constant GAS_POOL_NAME = "GasPool";
  string internal constant GENESIS_HUB_NAME = "GenesisHub";

  uint88 internal constant TOKEN_OFFSET = 100;
  uint88 internal constant KEYS_OFFSET = 150;

  function lzEndpointToChainId(uint32 lzEndpoint) internal pure returns (uint256) {
    if (lzEndpoint == 30_110) return 42_161;
    if (lzEndpoint == 30_184) return 8453;
    if (lzEndpoint == 30_106) return 43_114;
    if (lzEndpoint == 30_109) return 137;
    if (lzEndpoint == 30_111) return 10;
    if (lzEndpoint == 30_181) return 5000;
    if (lzEndpoint == 30_183) return 59_144;
    if (lzEndpoint == 30_112) return 250;
    if (lzEndpoint == 30_214) return 534_352;
    if (lzEndpoint == 30_255) return 252;
    if (lzEndpoint == 30_145) return 100;

    return 0;
  }
}
