// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "../../../base/BaseTest.t.sol";
import { OFT721, IERC721Receiver } from "src/tokens/ERC721/OFT721.sol";

contract OFT721Test is BaseTest {
  string private constant NAME = "MO";
  string private constant SYMBOL = "DU";
  string private constant URI = "www.google.com";

  uint32 private constant LZ_GAS_LIMIT = 200_000;
  uint256 private constant LZ_FEE = 2_399_482;
  uint256 private constant USER_NFT_ID_MINTED = 1;
  uint256 private constant RANDOM_NFT_ID_MINTED = 2;

  address private owner = generateAddress("Owner");
  address private user = generateAddress("User", 100e18);
  address private mockLzEndpoint = generateAddress("LZ Endpoint");

  OFT721Harness private underTest;

  function setUp() external prankAs(owner) {
    vm.mockCall(mockLzEndpoint, abi.encodeWithSignature("setDelegate(address)"), abi.encode(true));

    underTest = new OFT721Harness(NAME, SYMBOL, URI, owner, mockLzEndpoint, LZ_GAS_LIMIT);

    underTest.exposed_mint(user);
    underTest.exposed_mint(address(underTest));
  }

  function test_constructor_thenSetupCorrectly() external {
    underTest = new OFT721Harness(NAME, SYMBOL, URI, owner, mockLzEndpoint, LZ_GAS_LIMIT);

    assertEq(abi.encode(underTest.exposed_baseURI()), abi.encode(URI));
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

  function test_credit_whenNFTExistsButNoOwnedByContract_thenReverts() external pranking {
    changePrank(address(underTest));
    underTest.transferFrom(address(underTest), generateAddress(), RANDOM_NFT_ID_MINTED);

    vm.expectRevert(OFT721.NFTOwnerIsNotContract.selector);
    underTest.exposed_credit(user, RANDOM_NFT_ID_MINTED, false);
  }

  function test_credit_thenSendNFTs() external prankAs(user) {
    uint256 returnedValue = underTest.exposed_credit(user, RANDOM_NFT_ID_MINTED, false);

    assertEq(returnedValue, RANDOM_NFT_ID_MINTED);
    assertEq(underTest.ownerOf(RANDOM_NFT_ID_MINTED), user);
  }

  function test_credit_wheNFTDoesNotExists_thenMintsToUser() external {
    uint256 id = 99;
    uint256 returnedValue = underTest.exposed_credit(user, id, false);

    assertEq(returnedValue, id);
    assertEq(underTest.ownerOf(id), user);
  }

  function test_exists_thenReturnsCorrectState() external {
    uint256 latestId = underTest.latestedId();

    assertFalse(underTest.exposed_exists(0));
    assertFalse(underTest.exposed_exists(latestId + 1));
    assertTrue(underTest.exposed_exists(latestId));

    underTest.exposed_mint(user);

    assertTrue(underTest.exposed_exists(latestId + 1));
  }

  function test_onERC721Received_thenReturnsSelector() external view {
    assertEq(underTest.onERC721Received(user, user, 0, ""), IERC721Receiver.onERC721Received.selector);
  }

  function test_toLocalDecimals_thenReturnsExactValue() external view {
    uint64 value = 239.88e6;
    assertEq(underTest.exposed_toLocalDecimals(value), value);
  }

  function test_toSharedDecimals_thenReturnsExactValue() external view {
    uint64 value = 289.88e6;
    assertEq(underTest.exposed_toSharedDecimals(value), value);
  }
}

contract OFT721Harness is OFT721 {
  uint256 public latestedId = 0;

  constructor(
    string memory _name,
    string memory _symbol,
    string memory _uri,
    address _owner,
    address _localLzEndpoint,
    uint32 _lzGasLimit
  ) OFT721(_name, _symbol, _uri, _owner, _localLzEndpoint, _lzGasLimit) { }

  function exposed_mint(address _to) external {
    latestedId++;
    _mint(_to, latestedId);
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
