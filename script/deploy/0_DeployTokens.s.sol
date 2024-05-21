// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../BaseScript.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IHeroOFTXOperator } from "src/tokens/extension/IHeroOFTXOperator.sol";
import { HeroLinearToken20 } from "src/tokens/ERC20/HeroLinearToken20.sol";

contract DeployTokensScript is BaseScript {
  struct Config {
    address treasury;
    address nativeTokenWrapped;
    address lzEndpoint;
    uint32 lzDeploymentChainEndpointId;
    bool isTestnet;
    address heroglyphAttestation;
    address heroglyphRelay;
    address gasPool;
    address redeemHub;
  }

  struct TokenConfig {
    string name;
    string symbol;
    uint256 maxSupply;
    address key;
    uint256 preMintAmountBPS;
    uint256 fullEmissionInSeconds;
    uint32 immunity;
    uint32[] sourceLzEndpoints;
  }

  uint88 private constant TOKEN_OFFSET = 100;
  string private constant CONFIG_NAME = "ProtocolConfig";
  string private constant TOKEN_DATA = "TokensMetadata";

  Config config;
  uint256 activeDeployer;
  address deployerWallet;

  function run() external {
    activeDeployer = _getDeployerPrivateKey();
    deployerWallet = _getDeployerAddress();

    config = abi.decode(vm.parseJson(_getConfig(CONFIG_NAME), string.concat(".", _getNetwork())), (Config));
    TokenConfig[] memory tokens = abi.decode(vm.parseJson(_getConfig(TOKEN_DATA)), (TokenConfig[]));

    _loadContracts();

    IHeroOFTXOperator.HeroOFTXOperatorArgs memory heroArgs = IHeroOFTXOperator.HeroOFTXOperatorArgs({
      wrappedNative: config.nativeTokenWrapped,
      key: address(0),
      owner: deployerWallet,
      treasury: config.treasury,
      feePayer: config.gasPool,
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
    for (uint256 i = 12; i < 13; ++i) {
      token = tokens[i];
      heroArgs.maxSupply = token.maxSupply;

      if (!config.isTestnet) heroArgs.key = token.key;

      (tokenContractAddr, alreadyExisting) = _tryDeployLinearERC20(uint88(i), token, heroArgs);

      if (!alreadyExisting) {
        _connectWithGasPool(tokenContractAddr);
      }
    }
  }

  function _tryDeployLinearERC20(
    uint88 id,
    TokenConfig memory _token,
    IHeroOFTXOperator.HeroOFTXOperatorArgs memory _heroArgs
  ) internal returns (address tokenContractAddr, bool alreadyExisting) {
    uint256 preMintAmount = Math.mulDiv(_token.maxSupply, _token.preMintAmountBPS, 10_000);
    uint256 tokenPerSeconds = (_token.maxSupply - preMintAmount) / _token.fullEmissionInSeconds;

    //TODO: redo this as it is not the good arguments
    bytes memory args = abi.encode(
      _token.name,
      _token.symbol,
      0x000000000000000000000000000000000000dEaD,
      100,
      preMintAmount,
      config.treasury,
      tokenPerSeconds,
      config.redeemHub,
      _heroArgs
    );

    if (config.isTestnet) {
      (tokenContractAddr, alreadyExisting) =
        _tryDeployContract(string.concat("Token_", _token.name), 0, type(HeroLinearToken20).creationCode, args);
    } else {
      (tokenContractAddr, alreadyExisting) = _tryDeployContractDeterministic(
        string.concat("Token_", _token.name),
        _generateSeed(TOKEN_OFFSET + id),
        type(HeroLinearToken20).creationCode,
        args
      );
    }

    if (!alreadyExisting) {
      uint32 hookId;
      for (uint256 i = 0; i < _token.sourceLzEndpoints.length; ++i) {
        hookId = _token.sourceLzEndpoints[i];
        if (hookId == config.lzDeploymentChainEndpointId) continue;

        vm.broadcast(activeDeployer);
        HeroLinearToken20(payable(tokenContractAddr)).setPeer(hookId, bytes32(abi.encode(tokenContractAddr)));
      }

      vm.broadcast(activeDeployer);
      HeroLinearToken20(payable(tokenContractAddr)).transferOwnership(config.treasury);
    }

    return (tokenContractAddr, alreadyExisting);
  }

  function _connectWithGasPool(address _token) internal {
    if (config.gasPool == address(0) || Ownable(config.gasPool).owner() != deployerWallet) {
      console.log("--- Not Owner of Gas Pool --- ");
      console.log("Don't forgot to give access to the token to use the Gas Pool! ", _token);
      console.log("--- ---- --- ");
      return;
    }

    vm.broadcast(activeDeployer);
    ExecutionPool(payable(config.gasPool)).setAccessTo(_token, true);
  }
}

interface ExecutionPool {
  function setAccessTo(address _token, bool _access) external;
}
