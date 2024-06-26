// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../BaseScript.sol";
import { DeployUtils } from "../utils/DeployUtils.sol";

import { KeyOFT721 } from "src/game/phase2/ERC721/KeyOFT721.sol";

contract DeployKeysScript is BaseScript, DeployUtils {
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

  Config config;

  function run() external {
    activeDeployer = _getDeployerPrivateKey();
    deployerWallet = _getDeployerAddress();

    config = abi.decode(vm.parseJson(_getConfig(CONFIG_NAME), string.concat(".", _getNetwork())), (Config));
    KeyConfig[] memory keys = abi.decode(vm.parseJson(_getConfig(KEYS_DATA)), (KeyConfig[]));

    _loadContracts();

    KeyConfig memory key;
    bytes memory args;

    for (uint256 i = 0; i < keys.length; ++i) {
      key = keys[i];
      args = abi.encode(
        key.name,
        key.symbol,
        key.displayName,
        key.image,
        config.owner,
        config.lzEndpoint,
        200_000,
        key.maxSupply,
        key.cost,
        key.paymentToken,
        config.treasury
      );

      address keyAddr;

      if (config.isTestnet) {
        (keyAddr,) = _tryDeployContract(key.name, 0, type(KeyOFT721).creationCode, args);
      } else {
        (keyAddr,) = _tryDeployContractDeterministic(
          key.name, _generateSeed(KEYS_OFFSET + uint88(i)), type(KeyOFT721).creationCode, args
        );
      }

      if (_isSimulation()) {
        _verify(KeyOFT721(keyAddr), key);
      }
    }
  }

  function _verify(KeyOFT721 _contract, KeyConfig memory _key) private view {
    require(_contract.owner() == config.owner, "Not same Owner");
    require(_contract.treasury() == config.treasury, "Not same treasury");
    require(address(_contract.inputToken()) == _key.paymentToken, "Not same input token");
    require(_contract.cost() == _key.cost, "Not Same Cost");
  }
}
