// // SPDX-License-Identifier: BUSL-1.1
// pragma solidity 0.8.26;

// import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
// import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
// import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
// import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
// import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
// import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
// import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
// import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";


// contract GasPriceFeesHook is BaseHook {
//     using LPFeeLibrary for uint24; 

//     // moving average gas price
//     uint128 public movingAverageGasPrice; 

//     // number of times the moving average has been updated
//     uint128 public movingAverageGasPriceCount; 

//     uint24 public constant BASE_FEE = 5000; 


//     error MustUseDynamicFee(); 

//     constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
//         updateMovingAverageGasPrice(); // initialize 
//     }

//     // get permissions to see which hooks are used
//     function getHookPermissions() 
//     public
//     pure 
//     override 
//     returns(Hooks.Permissions memory)
//     {
//        return Hooks.Permissions({
//                 beforeInitialize: true,
//                 afterInitialize: false,
//                 beforeAddLiquidity: false,
//                 beforeRemoveLiquidity: false,
//                 afterAddLiquidity: false,
//                 afterRemoveLiquidity: false,
//                 beforeSwap: true,
//                 afterSwap: true,
//                 beforeDonate: false,
//                 afterDonate: false,
//                 beforeSwapReturnDelta: false,
//                 afterSwapReturnDelta: false,
//                 afterAddLiquidityReturnDelta: false,
//                 afterRemoveLiquidityReturnDelta: false
//             });
//     }

//     // checks if dynamic fees is even allowed on the pool. 
//     function _beforeInitialize(
//         address, 
//         PoolKey calldata key, 
//         uint160
//     ) internal pure override returns(bytes4) {
//         if (!key.fee.isDynamicFee()) {
//             revert MustUseDynamicFee(); 
//         }
//         return this.beforeInitialize.selector; // returns the function selector for _beforeInitialize function
//     }

//     function _beforeSwap(
//         address, 
//         PoolKey calldata, 
//         SwapParams calldata, 
//         bytes calldata
//         ) internal override view returns(bytes4, BeforeSwapDelta, uint24) {
//             uint24 fee = getFee(); 

//             uint24 feeWithFlag = fee | LPFeeLibrary.DYNAMIC_FEE_FLAG; // differentiates between if fee is 0 and if fee is not set. flag helps poolManager differentiate 

//             return (
//                 this.beforeSwap.selector, 
//                 BeforeSwapDeltaLibrary.ZERO_DELTA, 
//                 feeWithFlag
//             ); 
//     }

//     function _afterSwap(
//         address, 
//         PoolKey calldata, 
//         SwapParams calldata, 
//         BalanceDelta, 
//         bytes calldata
//     ) internal override returns (bytes4, int128) {
//         updateMovingAverageGasPrice(); 
//         return (this.afterSwap.selector, 0);
//     }

//     // helper functions 
//     function getFee() internal view returns (uint24) {
//         uint128 gasPrice = uint128(tx.gasprice); 

//         if (gasPrice > (110 * movingAverageGasPrice) / 100) {
//             return BASE_FEE / 2; 
//         }

//         if (gasPrice < (90 * movingAverageGasPrice) / 100) {
//             return BASE_FEE * 2; 
//         }

//         return BASE_FEE; 
//     }


//     function updateMovingAverageGasPrice() internal {
//         uint128 gasPrice = uint128(tx.gasprice); 

//         movingAverageGasPrice = ((movingAverageGasPrice * movingAverageGasPriceCount) + gasPrice) / (movingAverageGasPriceCount + 1);
//         movingAverageGasPriceCount += 1;
//     }


// }