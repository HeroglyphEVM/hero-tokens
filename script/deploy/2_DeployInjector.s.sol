// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../BaseScript.sol";
import { DeployUtils } from "../utils/DeployUtils.sol";
import { LayerZeroInjector } from "src/misc/LayerZeroInjector.sol";
import {
  IMessageLibManager,
  SetConfigParam
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";

contract DeployInjectorScript is BaseScript, DeployUtils {
  address constant LZ_ENDPOINT_BSC = 0x1a44076050125825900e736c501f859c50fE728c;
  uint32 constant LZ_EID_SANIC = 30_112;
  uint32 constant LZ_EID_frx = 30_255;
  uint32 constant LZ_EID_GNOBBY = 30_145;
  uint32 constant LZ_EID_KABO = 30_184;

  function run() external {
    _loadContracts();

    (address _lzInjector, bool existing) = _tryDeployContract(
      "LayerZeroInjector", 0, type(LayerZeroInjector).creationCode, abi.encode(_getDeployerAddress(), LZ_ENDPOINT_BSC)
    );

    LayerZeroInjector _injector = LayerZeroInjector(payable(_lzInjector));

    vm.startBroadcast(_getDeployerPrivateKey());
    if (!existing) {
      _configureLz(_injector);
    }

    if (_lzInjector.balance == 0) {
      vm.broadcast(_getDeployerPrivateKey());
      (bool success,) = _lzInjector.call{ value: 0.04 ether }("");
      require(success, "Failed to send ETH to LayerZeroInjector");
    }

    _injector.inject(LZ_EID_SANIC, 0);
    _injector.inject(LZ_EID_frx, 0);
    _injector.inject(LZ_EID_GNOBBY, 0);
    _injector.inject(LZ_EID_KABO, 0);

    _injector.withdrawETH();
    vm.stopBroadcast();
  }

  function _configureLz(LayerZeroInjector _injector) internal {
    //SANIC
    _injector.setPeer(LZ_EID_SANIC, bytes32(abi.encode(0xE2eca013A124FBcE7F7507a66FDf9Ad2e22d999B)));
    //frxBULLAS
    _injector.setPeer(LZ_EID_frx, bytes32(abi.encode(0x3Ec67133bB7d9D2d93D40FBD9238f1Fb085E01eE)));
    //GNOBBY
    _injector.setPeer(LZ_EID_GNOBBY, bytes32(abi.encode(0x1a8805194D0eF2F73045a00c70Da399d9E74221c)));
    //KABOSUCHAN
    _injector.setPeer(LZ_EID_KABO, bytes32(abi.encode(0x9e949461F9EC22C6032cE26Ea509824Fd2f6d98f)));
  }
}
