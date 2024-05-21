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

contract DeployTokensScript is BaseScript, DeployUtils {
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

  string private constant CONFIG_NAME = "ProtocolConfig";
  string private constant TOKEN_DATA = "TokensMetadata";

  Config config;
  uint256 activeDeployer;
  address deployerWallet;

  address gasPool;
  address genesisHub;

  address[] private genesisToHook;

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

      (tokenContractAddr, alreadyExisting) = _tryDeployLinearERC20(uint88(i), token, heroArgs);

      if (!alreadyExisting) {
        genesisToHook.push(tokenContractAddr);
        _connectWithGasPool(tokenContractAddr);
      }
    }

    _connectAllToHub();

    if (Ownable(genesisHub).owner() == deployerWallet) {
      vm.broadcast(activeDeployer);
      GenesisHub(payable(genesisHub)).transferOwnership(config.owner);
    }

    if (Ownable(gasPool).owner() == deployerWallet) {
      vm.broadcast(activeDeployer);
      ExecutionPool(payable(gasPool)).transferOwnership(config.owner);
    }
  }

  function _tryDeployLinearERC20(
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
    if (GenesisHub(genesisHub).owner() != deployerWallet) {
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
    GenesisHub(payable(genesisHub)).setRedeeemSettings(genesisToHook, redeemSettings);
  }
}
