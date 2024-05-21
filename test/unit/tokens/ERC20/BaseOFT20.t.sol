// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "../../../base/BaseTest.t.sol";
import { BaseOFT20, HeroOFTErrors } from "src/tokens/ERC20/BaseOFT20.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BaseOFT20Test is BaseTest {
  uint8 private constant DECIMALS = 18;

  BaseOFT20Harness private underTest;

  function setUp() external {
    underTest = new BaseOFT20Harness(DECIMALS);
  }

  function test_constructor_invalidDecimals_thenReverts() external {
    vm.expectRevert(BaseOFT20.InvalidLocalDecimals.selector);
    underTest = new BaseOFT20Harness(5);
  }

  function test_constructor_thenContractInitalized() external {
    underTest = new BaseOFT20Harness(DECIMALS);
    assertEq(underTest.decimalConversionRate(), 10 ** (DECIMALS - 6));
  }

  function test_sharedDecimals() external view {
    assertEq(underTest.sharedDecimals(), 6);
  }

  function test_debitView_whenMinimumIsHigherThanReturnedValue_thenReverts() external {
    uint256 amountIn = 938e18;
    uint256 amountMin = amountIn + 1;

    vm.expectRevert(abi.encodeWithSelector(HeroOFTErrors.SlippageExceeded.selector, amountIn, amountMin));

    underTest.exposed_debitView(amountIn, amountMin);
  }

  function test_debitView_thenRemoveDustAndReturns() external view {
    uint256 amountIn = 938.3787e11;
    uint256 amountMin = amountIn / 2;

    uint256 expected = underTest.exposed_removeDust(amountIn);

    (uint256 amountSentLD, uint256 amountReceivedLD) = underTest.exposed_debitView(amountIn, amountMin);

    assertEq(amountSentLD, expected);
    assertEq(amountReceivedLD, expected);
    assertLt(amountSentLD, amountIn);
  }

  function test_removeDust_thenRemovesExtraDecimals() external view {
    uint256 amountIn = 23.3787717911e10;
    uint256 conversionRate = (10 ** (18 - 6));

    uint256 expected = (amountIn / conversionRate) * conversionRate;

    assertEq(underTest.exposed_removeDust(amountIn), expected);
  }

  function test_toLD_thenAppliesConversion() external view {
    uint64 value = 239.88e6;
    uint256 expected = uint256(value) * (10 ** (18 - 6));
    assertEq(underTest.exposed_toLD(value), expected);
  }

  function test_toSD_thenAppliesConversion() external view {
    uint256 value = 289.88e18;
    uint64 expected = uint64(value / (10 ** (18 - 6)));
    assertEq(underTest.exposed_toSD(value), expected);
  }
}

contract BaseOFT20Harness is BaseOFT20 {
  uint256 public constant REWARD_PER_MINT = 60e18;

  constructor(uint8 _decimals) BaseOFT20(_decimals) ERC20("A", "A") { }

  function exposed_debitView(uint256 _amountLD, uint256 _minAmountLD)
    external
    view
    returns (uint256 amountSentLD, uint256 amountReceivedLD)
  {
    return _debitView(_amountLD, _minAmountLD);
  }

  function exposed_removeDust(uint256 _amountLD) external view returns (uint256 amountLD) {
    return _removeDust(_amountLD);
  }

  function exposed_toLD(uint64 _value) external view returns (uint256) {
    return _toLD(_value);
  }

  function exposed_toSD(uint256 _value) external view virtual returns (uint64) {
    return _toSD(_value);
  }
}
