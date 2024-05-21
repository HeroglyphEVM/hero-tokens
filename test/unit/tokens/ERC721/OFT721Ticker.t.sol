// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "../../../base/BaseTest.t.sol";
import { OFT721Ticker } from "src/tokens/ERC721/OFT721Ticker.sol";
import { IHeroOFTXOperator } from "src/tokens/extension/IHeroOFTXOperator.sol";

import { ILayerZeroEndpointV2 } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppCore.sol";
import {
  MessagingReceipt,
  MessagingParams,
  MessagingFee
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { MockERC20 } from "../../../mock/contract/MockERC20.t.sol";

contract OFT721TickerTest is BaseTest {
  string private constant NAME = "MO";
  string private constant SYMBOL = "DU";
  uint256 private constant MAX_SUPPLY = 100;
  uint32 private constant LZ_ENDPOINT_ID = 332;
  uint32 private constant LZ_GAS_LIMIT = 200_000;
  bytes32 private constant PEER = bytes32("PEER");
  uint256 private constant LZ_FEE = 2_399_482;
  uint256 private constant USER_NFT_ID_MINTED = 1;
  uint256 private constant RANDOM_NFT_ID_MINTED = 2;

  address private owner = generateAddress("Owner");
  address private treasury = generateAddress("Treasury");
  address private user = generateAddress("User", 100e18);
  address private mockLzEndpoint = generateAddress("LZ Endpoint");
  address private mockRelay = generateAddress("Heroglyph Relay");
  string private URI = "www.google.com";
  MockERC20 private wrappedNative;

  IHeroOFTXOperator.HeroOFTXOperatorArgs heroArgs;

  OFT721TickerHarness private underTest;

  function setUp() external prankAs(owner) {
    vm.mockCall(mockLzEndpoint, abi.encodeWithSignature("setDelegate(address)"), abi.encode(true));

    wrappedNative = new MockERC20("W", "W", 18);

    heroArgs = IHeroOFTXOperator.HeroOFTXOperatorArgs({
      wrappedNative: address(wrappedNative),
      key: address(0),
      owner: owner,
      treasury: treasury,
      feePayer: address(0),
      heroglyphRelay: mockRelay,
      localLzEndpoint: mockLzEndpoint,
      localLzEndpointID: LZ_ENDPOINT_ID,
      lzGasLimit: LZ_GAS_LIMIT,
      maxSupply: MAX_SUPPLY
    });

    underTest = new OFT721TickerHarness(NAME, SYMBOL, URI, heroArgs);
    underTest.exposed_mint(user);
    underTest.exposed_mint(address(underTest));
    underTest.setPeer(LZ_ENDPOINT_ID, PEER);

    MessagingReceipt memory emptyMsg;

    vm.mockCall(
      mockLzEndpoint, abi.encodeWithSelector(ILayerZeroEndpointV2.quote.selector), abi.encode(MessagingFee(LZ_FEE, 0))
    );
    vm.mockCall(mockLzEndpoint, abi.encodeWithSelector(ILayerZeroEndpointV2.send.selector), abi.encode(emptyMsg));
  }

  function test_constructor_thenSetupCorrectly() external {
    underTest = new OFT721TickerHarness(NAME, SYMBOL, URI, heroArgs);

    assertEq(abi.encode(underTest.baseURI()), abi.encode(URI));
    assertEq(abi.encode(underTest.exposed_baseURI()), abi.encode(URI));
  }

  function test_onValidationSameChain_whenMaxSupplyExceed_thenDoNotMint() external {
    for (uint256 i = underTest.totalMintedSupply(); i <= MAX_SUPPLY; i++) {
      underTest.exposed_mint(user);
    }

    underTest.exposed_onValidatorSameChain(user);
    assertEq(underTest.totalMintedSupply(), MAX_SUPPLY);

    vm.expectRevert();
    underTest.ownerOf(MAX_SUPPLY + 1);
  }

  function test_onValidationSameChain_thenMints() external {
    uint256 expectedId = underTest.totalMintedSupply() + 1;
    address receiver = generateAddress();

    underTest.exposed_onValidatorSameChain(receiver);

    assertEq(underTest.ownerOf(expectedId), receiver);
    assertEq(underTest.totalMintedSupply(), expectedId);
  }

  function test_onValidatorCrossChain_whenOverMaxSupply_thenReturnsFail() external {
    for (uint256 i = underTest.totalMintedSupply(); i <= MAX_SUPPLY; i++) {
      underTest.exposed_mint(user);
    }

    (uint256 id, uint256 totalMinted, bool success) = underTest.exposed_onValidatorCrossChain(user);

    assertEq(id, 0);
    assertEq(totalMinted, 0);
    assertFalse(success);
  }

  function test_onValidatorCrossChain_thenMintsToContract() external {
    uint256 expectedId = underTest.totalMintedSupply() + 1;
    (uint256 id, uint256 totalMinted, bool success) = underTest.exposed_onValidatorCrossChain(user);

    assertEq(id, expectedId);
    assertTrue(success);
    assertEq(underTest.ownerOf(expectedId), address(underTest));
    assertEq(totalMinted, 1);
  }

  function test_onValidatorCrossChainFailed_thenTransferNFT() external {
    uint256 expectedId = underTest.totalMintedSupply() + 1;
    underTest.exposed_onValidatorCrossChain(user);

    underTest.exposed_onValidatorCrossChainFailed(user, expectedId);

    assertEq(underTest.totalMintedSupply(), expectedId);
    assertEq(underTest.ownerOf(expectedId), address(user));
  }

  function test_mintAndTrack_whenOverMaxSupply_thenReturnsZero() external {
    for (uint256 i = underTest.totalMintedSupply(); i <= MAX_SUPPLY; i++) {
      underTest.exposed_mint(user);
    }

    uint256 id = underTest.exposed_mintAndTrack(user);

    assertEq(id, 0);
  }

  function test_mintAndTrack_whenUnderMaxSupply_thenMints() external {
    uint256 expectedId = underTest.totalMintedSupply() + 1;

    uint256 id = underTest.exposed_mintAndTrack(user);

    assertEq(id, expectedId);
    assertEq(underTest.ownerOf(expectedId), user);
  }

  function test_mintAndTrack_whenMaxSupplyIsZero_thenMintsInfinite() external {
    heroArgs.maxSupply = 0;
    underTest = new OFT721TickerHarness(NAME, SYMBOL, URI, heroArgs);

    address random = generateAddress();
    uint256 minting = 5000;
    uint256 expectingId = minting + 1;

    for (uint256 i = 0; i < minting; i++) {
      underTest.exposed_mint(user);
    }

    uint256 id = underTest.exposed_mintAndTrack(random);

    assertEq(id, expectingId);
    assertEq(underTest.totalMintedSupply(), expectingId);
    assertEq(underTest.ownerOf(expectingId), random);
  }

  function test_debit_whenNotOwner_thenReverts() external prankAs(user) {
    vm.expectRevert(
      abi.encodeWithSignature(
        "ERC721IncorrectOwner(address,uint256,address)", user, RANDOM_NFT_ID_MINTED, address(underTest)
      )
    );
    underTest.exposed_debit(RANDOM_NFT_ID_MINTED);
  }

  function test_debit_thenTransfers() external prankAs(user) {
    uint256 returnedValue = underTest.exposed_debit(USER_NFT_ID_MINTED);

    assertEq(returnedValue, USER_NFT_ID_MINTED);
    assertEq(underTest.ownerOf(USER_NFT_ID_MINTED), address(underTest));
  }

  function test_credit_givenFrozen_whenNFTDoesNotExist_thenDoNothings() external prankAs(user) {
    uint256 id = 99;
    uint256 returnedValue = underTest.exposed_credit(user, id, true);

    assertEq(returnedValue, id);

    vm.expectRevert(abi.encodeWithSignature("ERC721NonexistentToken(uint256)", 99));
    underTest.ownerOf(id);
  }

  function test_credit_givenFrozen_thenDoNothing() external prankAs(user) {
    uint256 returnedValue = underTest.exposed_credit(user, RANDOM_NFT_ID_MINTED, true);

    assertEq(returnedValue, RANDOM_NFT_ID_MINTED);
    assertEq(underTest.ownerOf(RANDOM_NFT_ID_MINTED), address(underTest));
  }

  function test_credit_givenNotFrozen_whenNFTExistsButNoOwnedByContract_thenReverts() external pranking {
    changePrank(address(underTest));
    underTest.transferFrom(address(underTest), generateAddress(), RANDOM_NFT_ID_MINTED);

    vm.expectRevert(OFT721Ticker.NFTOwnerIsNotContract.selector);
    underTest.exposed_credit(user, RANDOM_NFT_ID_MINTED, false);
  }

  function test_credit_givenNotFrozen_thenSendNFTs() external prankAs(user) {
    uint256 returnedValue = underTest.exposed_credit(user, RANDOM_NFT_ID_MINTED, false);

    assertEq(returnedValue, RANDOM_NFT_ID_MINTED);
    assertEq(underTest.ownerOf(RANDOM_NFT_ID_MINTED), user);
  }

  function test_credit_givenNotFrozen_wheNFTDoesNotExists_thenMintsToUser() external {
    uint256 id = 99;
    uint256 returnedValue = underTest.exposed_credit(user, id, false);

    assertEq(returnedValue, id);
    assertEq(underTest.ownerOf(id), user);
  }

  function test_exists_thenReturnsCorrectState() external {
    uint256 latestId = underTest.totalMintedSupply();

    assertFalse(underTest.exposed_exists(0));
    assertFalse(underTest.exposed_exists(latestId + 1));
    assertTrue(underTest.exposed_exists(latestId));

    underTest.exposed_mintAndTrack(user);

    assertTrue(underTest.exposed_exists(latestId + 1));
  }

  function test_toLocalDecimals_thenReturnsExactValue() external view {
    uint64 value = 239.88e6;
    assertEq(underTest.exposed_toLocalDecimals(value), value);
  }

  function test_toSharedDecimals_thenReturnsExactValue() external view {
    uint64 value = 289.88e6;
    assertEq(underTest.exposed_toSharedDecimals(value), value);
  }

  function _expectLZSend(uint256 _fee, uint32 _toEndpoint, bytes memory _payload, bytes memory _option, address _refund)
    private
  {
    vm.expectCall(
      mockLzEndpoint,
      _fee,
      abi.encodeWithSelector(
        ILayerZeroEndpointV2.send.selector, MessagingParams(_toEndpoint, PEER, _payload, _option, false), _refund
      )
    );
  }
}

contract OFT721TickerHarness is OFT721Ticker {
  constructor(
    string memory _name,
    string memory _symbol,
    string memory _url,
    IHeroOFTXOperator.HeroOFTXOperatorArgs memory _heroArgs
  ) OFT721Ticker(_name, _symbol, _url, _heroArgs) { }

  function exposed_onValidatorSameChain(address _to) external {
    uint256 value = _onValidatorSameChain(_to);
    if (value == 1) totalMintedSupply++;
  }

  function exposed_onValidatorCrossChain(address _to)
    external
    returns (uint256 tokenIdOrAmount_, uint256 quantityMinted_, bool success_)
  {
    (tokenIdOrAmount_, quantityMinted_, success_) = _onValidatorCrossChain(_to);

    if (success_) totalMintedSupply++;

    return (tokenIdOrAmount_, quantityMinted_, success_);
  }

  function exposed_onValidatorCrossChainFailed(address _to, uint256 _nftId) external {
    _onValidatorCrossChainFailed(_to, _nftId);
  }

  function exposed_mintAndTrack(address _to) external returns (uint256 return_) {
    return_ = _mintAndTrack(_to);

    if (return_ != 0) {
      totalMintedSupply++;
    }

    return return_;
  }

  function exposed_mint(address _to) external {
    uint256 return_ = _mintAndTrack(_to);

    if (return_ != 0) {
      totalMintedSupply++;
    }
  }

  function exposed_debit(uint256 _amountOrId) external returns (uint256 _amountSendingOrId_) {
    return _debit(_amountOrId, 0);
  }

  function exposed_credit(address _to, uint256 _value, bool _isFrozen) external returns (uint256) {
    return _credit(_to, _value, _isFrozen);
  }

  function exposed_exists(uint256 _tokenId) external view returns (bool) {
    return _exists(_tokenId);
  }

  function exposed_baseURI() external view returns (string memory) {
    return _baseURI();
  }

  function exposed_toLocalDecimals(uint64 _value) external view returns (uint256) {
    return _toLocalDecimals(_value);
  }

  function exposed_toSharedDecimals(uint256 _value) external view virtual returns (uint64) {
    return _toSharedDecimals(_value);
  }
}
