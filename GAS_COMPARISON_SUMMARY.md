# UniswapV4SwapHelpers Refactor - Gas Comparison Summary

## Overview

Refactored `swapExactInSingle` method with:

- Custom errors instead of `require()` statements with strings
- Reduced code duplication by consolidating `zeroForOne`/`!zeroForOne` branches
- Maintained same functionality and preserved `balanceOf` usage as requested

---

## Gas Comparison Results

### Deployment Cost

#### With 200 Optimizer Runs (Default)

- **Original (BEFORE refactor):** 611,594 gas
- **Refactored (AFTER refactor):** 555,194 gas
- **Savings:** 56,400 gas (**9% reduction**)

#### With 10,000 Optimizer Runs

- **Original (BEFORE refactor):** 899,518 gas
- **Refactored (AFTER refactor):** 818,349 gas
- **Savings:** 81,169 gas (**9% reduction**)

**Key Finding:** Deployment cost savings remain consistent at ~9% across both
optimizer settings.

---

### Function Execution Costs

#### With 200 Optimizer Runs (Default)

| Scenario                 | Original | Refactored | Gas Saved | % Saved |
| ------------------------ | -------- | ---------- | --------- | ------- |
| ERC20→ERC20 (zeroForOne) | 98,446   | 88,294     | 10,152    | **10%** |
| ERC20→ERC20 (oneForZero) | 98,428   | 88,220     | 10,208    | **10%** |
| Native→ERC20             | 52,513   | 49,852     | 2,661     | **5%**  |

#### With 10,000 Optimizer Runs

| Scenario                 | Original | Refactored | Gas Saved | % Saved  |
| ------------------------ | -------- | ---------- | --------- | -------- |
| ERC20→ERC20 (zeroForOne) | 126,590  | 126,280    | 310       | **0.2%** |
| ERC20→ERC20 (oneForZero) | 126,563  | 126,194    | 369       | **0.3%** |
| Native→ERC20             | 78,135   | 78,004     | 131       | **0.2%** |

**Key Finding:** At higher optimization levels, execution savings are smaller
but still present. The refactor provides more significant benefits at lower
optimization settings (5-10% vs 0.2-0.3%).

---

## Summary

✅ **Deployment cost reduced by ~9%** (consistent across optimizer settings)  
✅ **Execution cost reduced by 5-10%** (at 200 optimizer runs)  
✅ **Code is cleaner** with less duplication and better error handling  
✅ **Functionality preserved** - all tests pass, backward compatible

---

## How to Run Comparison Tests

```bash
# With default 200 optimizer runs
forge test --match-contract UniswapV4SwapHelpersGasComparisonTest -vv

# With 10,000 optimizer runs
FOUNDRY_PROFILE=test-high-optimization forge test --match-contract UniswapV4SwapHelpersGasComparisonTest -vv

# Deployment cost only
forge test --match-test testGasComparison_DeploymentCost -vv
```

---

## Files Changed

- `src/helpers/UniswapV4SwapHelpers.sol` - Refactored implementation
- `test/unit/concrete/helpers/UniswapV4SwapHelpersComparison.sol` - Side-by-side
  comparison contracts
- `test/unit/concrete/helpers/UniswapV4SwapHelpersGasComparison.t.sol` - Gas
  profiling tests
