// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../BaseScript.sol";
import { DeployUtils } from "../utils/DeployUtils.sol";
import { Icedrop } from "src/game/phase3/module/Icedrop.sol";
import { IIcedrop } from "src/game/phase3/interface/IIcedrop.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DeployIcedropScript is BaseScript, DeployUtils {
  struct IcedropConfig {
    address owner;
    address treasury;
    address sablier;
    address randomizer;
    SupportedTokenData[] tokenConfig;
  }

  struct SupportedTokenData {
    address genesisKey;
    address output;
    uint256 maxOutputToken;
  }

  IcedropConfig ice;

  string private constant ICEDROP_CONFIG_NAME = "IcedropConfig";

  function run() external {
    _loadContracts();

    ice = abi.decode(vm.parseJson(_getConfig(ICEDROP_CONFIG_NAME), string.concat(".", _getNetwork())), (IcedropConfig));

    IIcedrop.SupportedTokenData[] memory supportedTokenData = new IIcedrop.SupportedTokenData[](ice.tokenConfig.length);

    for (uint256 i = 0; i < ice.tokenConfig.length; i++) {
      supportedTokenData[i] = IIcedrop.SupportedTokenData({
        genesisKey: ice.tokenConfig[i].genesisKey,
        output: ice.tokenConfig[i].output,
        maxOutputToken: uint128(ice.tokenConfig[i].maxOutputToken),
        started: false
      });
    }

    _tryDeployContract(
      "Icedrop",
      0,
      type(Icedrop).creationCode,
      abi.encode(ice.owner, ice.treasury, ice.sablier, ice.randomizer, supportedTokenData)
    );
  }
}
