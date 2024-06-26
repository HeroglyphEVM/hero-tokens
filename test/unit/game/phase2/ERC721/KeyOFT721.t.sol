// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "../../../../base/BaseTest.t.sol";
import { KeyOFT721 } from "src/game/phase2/ERC721/KeyOFT721.sol";
import { MockERC20 } from "test/mock/contract/MockERC20.t.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

contract KeyOFT721Test is BaseTest {
  string private constant NAME = "MO";
  string private constant SYMBOL = "DU";
  string private constant DISPLAY_NAME = "displayName";
  string private constant URI = "www.google.com";

  uint32 private constant LZ_GAS_LIMIT = 200_000;
  uint256 private constant COST = 0.001 ether;
  uint256 private constant MAX_SUPPLY = 100;

  address private owner = generateAddress("Owner");
  address private user = generateAddress("User", 100e18);
  address private mockLzEndpoint = generateAddress("LZ Endpoint");
  address private treasury = generateAddress("Treasury");
  MockERC20 private input;

  KeyOFT721 private underTest;

  function setUp() external prankAs(owner) {
    vm.mockCall(mockLzEndpoint, abi.encodeWithSignature("setDelegate(address)"), abi.encode(true));
    input = new MockERC20("A", "A", 18);
    input.mint(user, 1000e18);

    underTest = createKeyOFT721(address(0), MAX_SUPPLY);
  }

  function test_constructor_thenSetupCorrectly() external {
    underTest = createKeyOFT721(address(0), MAX_SUPPLY);

    assertEq(underTest.maxSupply(), MAX_SUPPLY);
    assertEq(underTest.cost(), COST);
    assertEq(address(underTest.inputToken()), address(0));
    assertEq(underTest.treasury(), treasury);

    underTest = new KeyOFT721(
      NAME, SYMBOL, DISPLAY_NAME, URI, owner, mockLzEndpoint, LZ_GAS_LIMIT, 0, COST * 2, address(input), treasury
    );

    assertEq(underTest.maxSupply(), 0);
    assertEq(underTest.cost(), COST * 2);
    assertEq(address(underTest.inputToken()), address(input));
    assertEq(underTest.treasury(), treasury);
  }

  function test_buy_whenNative_givenBadMsgValue_thenReverts() external prankAs(user) {
    vm.expectRevert(KeyOFT721.InvalidAmount.selector);
    underTest.buy{ value: COST + 1 }();
  }

  function test_buy_whenMaxSupplyReached_thenReverts() external prankAs(user) {
    for (uint256 i = 0; i < MAX_SUPPLY; ++i) {
      underTest.buy{ value: COST }();
    }

    vm.expectRevert(KeyOFT721.MaxSupplyReached.selector);
    underTest.buy{ value: COST }();
  }

  function test_buy_whenCostIsZero_thenReverts() external prankAs(user) {
    underTest =
      new KeyOFT721(NAME, SYMBOL, DISPLAY_NAME, URI, owner, mockLzEndpoint, LZ_GAS_LIMIT, 0, 0, address(0), treasury);

    vm.expectRevert(KeyOFT721.CannotBeBoughtHere.selector);
    underTest.buy();
  }

  function test_buy_whenERC20_givenETH_thenReverts() external prankAs(user) {
    underTest = createKeyOFT721(address(input), MAX_SUPPLY);

    vm.expectRevert(KeyOFT721.NoETHNedded.selector);
    underTest.buy{ value: 0.1e18 }();
  }

  function test_buy_withNoMaxSupply_thenMints() external prankAs(user) {
    underTest = createKeyOFT721(address(0), 0);

    for (uint256 i = 0; i < 9999; ++i) {
      underTest.buy{ value: COST }();
    }

    underTest.buy{ value: COST }();
    assertEq(underTest.totalSupply(), 10_000);
  }

  function test_buy_whenERC20_thenUsesExacltyTheAmountSendToTreasury() external prankAs(user) {
    underTest = createKeyOFT721(address(input), MAX_SUPPLY);
    uint256 balanceBefore = input.balanceOf(user);

    underTest.buy();
    assertEq(balanceBefore - COST, input.balanceOf(user));
    assertEq(input.balanceOf(treasury), COST);
  }

  function test_buy_thenMintsAndSendToTreasury() external prankAs(user) {
    underTest.buy{ value: COST }();
    assertEq(underTest.ownerOf(1), user);
    assertEq(treasury.balance, COST);

    underTest = createKeyOFT721(address(input), MAX_SUPPLY);
    underTest.buy();
    assertEq(underTest.ownerOf(1), user);
    assertEq(underTest.totalSupply(), 1);
    assertEq(input.balanceOf(treasury), COST);
  }

  function test_getCostInWEI_given10Decimals_thenConverts() external {
    underTest = createKeyOFT721(address(new MockERC20("A", "A", 10)), MAX_SUPPLY);

    assertEq(underTest.getCostInWEI(), COST * (10 ** (18 - 10)));
  }

  function test_getCostInWEI_given18Decimals_thenSendsTheSame() external {
    underTest = createKeyOFT721(address(input), MAX_SUPPLY);
    assertEq(underTest.getCostInWEI(), COST);
  }

  function test_getCostInWEI_givenNative_thenSendsTheSame() external view {
    assertEq(underTest.getCostInWEI(), COST);
  }

  function test_tokenURI_thenSendsExact() external prankAs(user) {
    underTest.buy{ value: COST }();
    underTest.buy{ value: COST }();

    assertEq(keccak256(bytes(underTest.tokenURI(1))), keccak256(bytes(generateURI(1))));
    assertEq(keccak256(bytes(underTest.tokenURI(2))), keccak256(bytes(generateURI(2))));
    assertTrue(keccak256(bytes(underTest.tokenURI(1))) != keccak256(bytes(generateURI(2))));
  }

  function generateURI(uint256 id) internal pure returns (string memory) {
    string memory data = string(
      abi.encodePacked(
        '{"name":"',
        DISPLAY_NAME,
        Strings.toString(id),
        '","description":"Unlock one of the Heroglyph`s tickers","image":"',
        URI,
        '"}'
      )
    );

    return string(abi.encodePacked("data:application/json;utf8,", data));
  }

  function createKeyOFT721(address _input, uint256 _maxSupply) internal returns (KeyOFT721) {
    return new KeyOFT721(
      NAME, SYMBOL, DISPLAY_NAME, URI, owner, mockLzEndpoint, LZ_GAS_LIMIT, _maxSupply, COST, _input, treasury
    );
  }
}
