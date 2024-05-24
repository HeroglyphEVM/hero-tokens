// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../BaseScript.sol";

import { DeployUtils } from "../utils/DeployUtils.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IHeroOFTXOperator } from "src/tokens/extension/IHeroOFTXOperator.sol";
import { GenesisToken, IGenesisToken } from "src/game/ERC20/GenesisToken.sol";
import { GenesisHub, IGenesisHub } from "src/game/GenesisHub.sol";
import { ExecutionPool } from "src/game/ExecutionPool.sol";

import { ILayerZeroEndpointV2 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";

contract DeployTokensScript is BaseScript, DeployUtils {
  Config config;
  uint256 activeDeployer;
  address deployerWallet;

  address gasPool;
  address genesisHub;

  address[] private genesisToHook;
  uint32[] private relatedLzEndpointToConfig;

  function run() external {
    activeDeployer = _getDeployerPrivateKey();
    deployerWallet = _getDeployerAddress();

    config = abi.decode(vm.parseJson(_getConfig(CONFIG_NAME), string.concat(".", _getNetwork())), (Config));
    TokenConfig[] memory tokens = abi.decode(vm.parseJson(_getConfig(TOKEN_DATA)), (TokenConfig[]));

    _loadContracts();

    if (block.chainid == 42_161) {
      (gasPool,) = _tryDeployContract(GAS_POOL_NAME, 0, type(ExecutionPool).creationCode, abi.encode(deployerWallet));
      (genesisHub,) = _tryDeployContract(GENESIS_HUB_NAME, 0, type(GenesisHub).creationCode, abi.encode(deployerWallet));
    }

    IHeroOFTXOperator.HeroOFTXOperatorArgs memory heroArgs = IHeroOFTXOperator.HeroOFTXOperatorArgs({
      wrappedNative: config.nativeTokenWrapped,
      key: address(0),
      owner: deployerWallet,
      treasury: config.treasury,
      feePayer: gasPool,
      heroglyphRelay: config.heroglyphRelay,
      localLzEndpoint: config.lzEndpoint,
      localLzEndpointID: config.lzDeploymentChainEndpointId,
      lzGasLimit: 200_000,
      maxSupply: 0
    });

    if (tokens.length == 0) revert("NO TOKENS");

    TokenConfig memory token;
    address tokenContractAddr;
    bool alreadyExisting;
    for (uint256 i = 0; i < tokens.length; ++i) {
      token = tokens[i];
      heroArgs.maxSupply = token.maxSupply;

      bool isDeploymentChain = false;

      for (uint256 lzEndpoints = 0; lzEndpoints < token.sourceLzEndpoints.length; ++lzEndpoints) {
        if (lzEndpointToChainId(token.sourceLzEndpoints[lzEndpoints]) != block.chainid) continue;
        isDeploymentChain = true;
      }

      if (!isDeploymentChain) {
        console.log("Skipping", token.name, "Not Deploying on", block.chainid);
        continue;
      }

      if (!config.isTestnet) heroArgs.key = token.key;

      (tokenContractAddr, alreadyExisting) = _tryDeployGenesis(uint88(i), token, heroArgs);

      if (!alreadyExisting) {
        genesisToHook.push(tokenContractAddr);
        _connectWithGasPool(tokenContractAddr);
      }
    }

    _connectAllToHub();

    if (genesisHub != address(0) && Ownable(genesisHub).owner() == deployerWallet) {
      vm.broadcast(activeDeployer);
      GenesisHub(payable(genesisHub)).transferOwnership(config.owner);
    }

    if (gasPool != address(0) && Ownable(gasPool).owner() == deployerWallet) {
      vm.broadcast(activeDeployer);
      ExecutionPool(payable(gasPool)).transferOwnership(config.owner);
    }
  }

  function _tryDeployGenesis(
    uint88 id,
    TokenConfig memory _token,
    IHeroOFTXOperator.HeroOFTXOperatorArgs memory _heroArgs
  ) internal returns (address tokenContractAddr, bool alreadyExisting) {
    uint256 preMintAmount = Math.mulDiv(_token.maxSupply, _token.preMintAmountBPS, 10_000);
    uint256 fixedRate = (_token.maxSupply - preMintAmount) / _token.minimumDuration;
    uint256 bonus = _token.maxBonusFullDay;

    if (bonus == 0) {
      bonus = fixedRate * 3600;
    }

    if (!_isTestnet() && block.chainid != 42_161) {
      preMintAmount = 0;
      fixedRate = 0;
      bonus = 0;
    }

    IGenesisToken.GenesisConfiguration memory genesisConfiguration =
      IGenesisToken.GenesisConfiguration({ fixedRate: fixedRate, maxBonusFullDay: bonus });

    IGenesisToken.GenesisConstructor memory constructorArgs = IGenesisToken.GenesisConstructor({
      name: _token.name,
      symbol: _token.symbol,
      crossChainFee: 0,
      preMintAmount: preMintAmount,
      genesisHub: genesisHub,
      configuration: genesisConfiguration
    });

    bytes memory args = abi.encode(constructorArgs, _heroArgs);

    if (config.isTestnet) {
      (tokenContractAddr, alreadyExisting) =
        _tryDeployContract(string.concat("Token_", _token.name), 0, type(GenesisToken).creationCode, args);
    } else {
      (tokenContractAddr, alreadyExisting) = _tryDeployContractDeterministic(
        string.concat("Token_", _token.name), _generateSeed(TOKEN_OFFSET + id), type(GenesisToken).creationCode, args
      );
    }

    if (!alreadyExisting) {
      uint32 hookId;
      for (uint256 i = 0; i < _token.sourceLzEndpoints.length; ++i) {
        hookId = _token.sourceLzEndpoints[i];
        if (hookId == config.lzDeploymentChainEndpointId) continue;

        vm.broadcast(activeDeployer);
        GenesisToken(payable(tokenContractAddr)).setPeer(hookId, bytes32(abi.encode(tokenContractAddr)));
      }

      try this._connectLayerZeroChain(tokenContractAddr, _token.sourceLzEndpoints) {
        console.log(_token.name, tokenContractAddr, "has been lz configured");
      } catch (bytes memory) { }

      vm.broadcast(activeDeployer);
      GenesisToken(payable(tokenContractAddr)).setDelegate(config.treasury);

      vm.broadcast(activeDeployer);
      GenesisToken(payable(tokenContractAddr)).transferOwnership(config.treasury);
    }

    return (tokenContractAddr, alreadyExisting);
  }

  function _connectWithGasPool(address _token) internal {
    if (gasPool == address(0) || Ownable(gasPool).owner() != deployerWallet) {
      console.log("--- Not Owner of Gas Pool --- ");
      console.log("Don't forgot to give access to the token to use the Gas Pool! ", _token);
      console.log("--- ---- --- ");
      return;
    }

    vm.broadcast(activeDeployer);
    ExecutionPool(payable(gasPool)).setAccessTo(_token, true);
  }

  function _connectAllToHub() internal {
    if (genesisHub == address(0) || GenesisHub(genesisHub).owner() != deployerWallet) {
      console.log("--- Not Owner of Genesis Hub --- ");
      console.log("Don't forgot to config GenesisHub! ", genesisHub);
      console.log("--- ---- --- ");
      return;
    }

    IGenesisHub.RedeemSettings memory defaultRedeem =
      IGenesisHub.RedeemSettings({ tokenInput: config.heroglyphAttestation, ratePerRedeem: 1e18 });

    GenesisHub.RedeemSettings[] memory redeemSettings = new GenesisHub.RedeemSettings[](genesisToHook.length);
    for (uint256 i = 0; i < genesisToHook.length; ++i) {
      redeemSettings[i] = defaultRedeem;
    }

    vm.broadcast(activeDeployer);
    GenesisHub(payable(genesisHub)).setRedeemSettings(genesisToHook, redeemSettings);
  }

  function _connectLayerZeroChain(address _token, uint32[] calldata _tokenLzConnections) external {
    console.log("Trying to connect Lz Chain of [", _token, "] from", _getNetwork());

    LayerZeroConfig memory lzConfig =
      abi.decode(vm.parseJson(_getConfig(LZ_CONFIG_NAME), string.concat(".", _getNetwork())), (LayerZeroConfig));

    console.log("Layer Config Found for", _getNetwork());

    SetConfigParam[] memory sendingConfig = new SetConfigParam[](1);
    ULNConfigStructType memory uln;
    ExecutorConfigStructType memory executor;

    address[] memory DVN = new address[](1);
    DVN[0] = lzConfig.DVN;

    delete relatedLzEndpointToConfig;

    for (uint32 i = 0; i < lzConfig.endpointToConfig.length; i++) {
      for (uint32 x = 0; x < _tokenLzConnections.length; x++) {
        if (lzConfig.endpointToConfig[i] != _tokenLzConnections[x]) continue;

        relatedLzEndpointToConfig.push(_tokenLzConnections[x]);
      }
    }

    if (relatedLzEndpointToConfig.length == 0) {
      console.log("No LZ Configuration set for ", _token);
      revert("No LZConfig to do");
    }
    for (uint32 i = 0; i < relatedLzEndpointToConfig.length; i++) {
      sendingConfig[0].eid = relatedLzEndpointToConfig[i];

      uln = ULNConfigStructType({
        confirmations: 20,
        requiredDVNCount: uint8(DVN.length),
        optionalDVNCount: 0,
        optionalDVNThreshold: 0,
        requiredDVNs: DVN,
        optionalDVNs: new address[](0)
      });

      executor = ExecutorConfigStructType({ maxMessageSize: 1024, executorAddress: lzConfig.executioner });

      sendingConfig[0].config = abi.encode(uln);
      sendingConfig[0].configType = 2;

      //Read

      vm.broadcast(activeDeployer);
      ILayerZeroEndpointV2(lzConfig.lzEndpoint).setConfig(_token, lzConfig.messageLibReceiver, sendingConfig);
      vm.broadcast(activeDeployer);
      ILayerZeroEndpointV2(lzConfig.lzEndpoint).setConfig(_token, lzConfig.messageLibSender, sendingConfig);

      //messageLibWrite
      sendingConfig[0].config = abi.encode(executor);
      sendingConfig[0].configType = 1;

      vm.broadcast(activeDeployer);
      ILayerZeroEndpointV2(lzConfig.lzEndpoint).setConfig(_token, lzConfig.messageLibSender, sendingConfig);
    }
  }
}
