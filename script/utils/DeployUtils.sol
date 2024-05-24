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

  struct TokenConfig {
    string name;
    string symbol;
    uint256 maxSupply;
    address key;
    uint256 preMintAmountBPS;
    uint256 minimumDuration;
    uint256 maxBonusFullDay;
    uint32 immunity;
    uint32[] sourceLzEndpoints;
  }

  struct LayerZeroConfig {
    address messageLibReceiver;
    address messageLibSender;
    address executioner;
    address lzEndpoint;
    address DVN;
    uint32[] endpointToConfig;
    uint32 lzDeploymentChainEndpointId;
  }

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

  struct SendingConfig {
    uint32 eid;
    uint32 configType;
    bytes config;
  }

  string internal constant CONFIG_NAME = "ProtocolConfig";
  string internal constant TOKEN_DATA = "TokensMetadata";
  string internal constant LZ_CONFIG_NAME = "LayerZeroConfig";

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
