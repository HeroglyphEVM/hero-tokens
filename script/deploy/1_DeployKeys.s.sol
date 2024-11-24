// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../BaseScript.sol";
import { DeployUtils } from "../utils/DeployUtils.sol";

import { KeyOFT721 } from "src/game/phase2/ERC721/KeyOFT721.sol";

contract DeployKeysScript is BaseScript, DeployUtils {
  uint256 constant ARBITRUM_CHAIN_ID = 42_161;

  struct KeyConfig {
    string name;
    string symbol;
    string displayName;
    string image;
    uint256 maxSupply;
    address paymentToken;
    uint256 cost;
  }

  string private constant KEYS_DATA = "KeysMetadata";

  uint256 activeDeployer;
  address deployerWallet;
  bool keyHasCost;

  Config config;

  function run() external {
    activeDeployer = _getDeployerPrivateKey();
    deployerWallet = _getDeployerAddress();

    address[] memory arbitrumAddresses = new address[](16);
    arbitrumAddresses[0] = 0x518AD4c19FeA481f743B8dE33Ff1ec1796f94023;
    arbitrumAddresses[1] = 0xF5E0DFEf32e0e6dB9882af1750c08e9497459100;
    arbitrumAddresses[2] = 0xE077E5f63C34B611a913B3FCBFADAA3b25991733;
    arbitrumAddresses[3] = 0x84Bc8D2a2c6281F15afC18C896766D64EF93bf02;
    arbitrumAddresses[4] = 0x6F2Ffdd387f01A0573Ca40628EaCF9dBe5240731;
    arbitrumAddresses[5] = 0xbcEDcFf31C68B1fb362FaEBe36917B35643DE471;
    arbitrumAddresses[6] = 0x01d7Ef2ab555C800f0818edfc6A9744B79771DA1;
    arbitrumAddresses[7] = 0xb8F977f9cb94ca72d71eC6466785605319c83F0C;
    arbitrumAddresses[8] = 0x32E707B2Fa13851Ae5A8D5d610B236aB3ad5687f;
    arbitrumAddresses[9] = 0x30dA1A8b1673Db2eEE02c72682097290b11325Fd;
    arbitrumAddresses[10] = 0x1910bFE60B28b751b19Ba1C266674eB61b7e6D2B;
    arbitrumAddresses[11] = 0xbc75c6a9021a97c3343DC5c52eA2E13E5F1f852c;
    arbitrumAddresses[12] = 0x7d35995Ec68BcA71849068e0FC91EB75641c9aA8;
    arbitrumAddresses[13] = 0xf4E131ba5E4678bd00e8DBd508f5820fE453A51D;
    arbitrumAddresses[14] = 0xC38F5a1aA46853Be3BfbFcF00562E01856867ba7;
    arbitrumAddresses[15] = 0xD37e64dD683BeDD72259e861D53c29bE51Ee8E04;

    config = abi.decode(vm.parseJson(_getConfig(CONFIG_NAME), string.concat(".", _getNetwork())), (Config));
    KeyConfig[] memory keys = abi.decode(vm.parseJson(_getConfig(KEYS_DATA)), (KeyConfig[]));

    _loadContracts();

    KeyConfig memory key;
    bytes memory args;
    keyHasCost = block.chainid == ARBITRUM_CHAIN_ID || config.isTestnet;

    for (uint256 i = 0; i < keys.length; ++i) {
      key = keys[i];

      args = abi.encode(
        key.name,
        key.symbol,
        key.displayName,
        key.image,
        deployerWallet,
        config.lzEndpoint,
        200_000,
        key.maxSupply,
        keyHasCost ? key.cost : 0,
        key.paymentToken,
        config.treasury
      );

      address keyAddr;

      if (!config.isTestnet) {
        (keyAddr,) = _tryDeployContract(key.name, 0, type(KeyOFT721).creationCode, args);
      } else {
        (keyAddr,) = _tryDeployContractDeterministic(
          key.name, _generateSeed(KEYS_OFFSET + uint88(i)), type(KeyOFT721).creationCode, args
        );
      }

      vm.startBroadcast(activeDeployer);
      KeyOFT721(keyAddr).setPeer(30_110, bytes32(abi.encode(arbitrumAddresses[i])));
      KeyOFT721(keyAddr).setDelegate(config.owner);
      KeyOFT721(keyAddr).transferOwnership(config.owner);
      vm.stopBroadcast();

      if (_isSimulation()) {
        _verify(KeyOFT721(keyAddr), key);
      }
    }
  }

  function _verify(KeyOFT721 _contract, KeyConfig memory _key) private view {
    require(_contract.owner() == config.owner, "Not same Owner");
    require(_contract.treasury() == config.treasury, "Not same treasury");
    require(address(_contract.inputToken()) == _key.paymentToken, "Not same input token");
    require(_contract.cost() == (keyHasCost ? _key.cost : 0), "Not Same Cost");
  }
}
