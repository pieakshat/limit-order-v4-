// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";


import {TakeProfitsHook} from "../src/TakeProfitsHook.sol";

contract TestTakeProfitsHook is Test, Deployers, IERC1155Receiver {

    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey; 
    using CurrencyLibrary for Currency; 

    Currency token0; 
    Currency token1; 

    TakeProfitsHook hook; 

    function setUp() public {
        // deploy v4 contracts
        deployFreshManagerAndRouters(); 


        // deploy couple of currencies
        (token0, token1) = deployMintAndApprove2Currencies(); 

        // deploy our hook 
        uint160 flags = uint160 (
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_SWAP_FLAG
        ); 
        address hookAddress = address(flags); 
        deployCodeTo("TakeProfitsHook.sol", abi.encode(manager, ""), hookAddress); 
        hook = TakeProfitsHook(hookAddress); 

        // approve our hook to be able to spend tokens on our behalf
        MockERC20(Currency.unwrap(token0)).approve(hookAddress, type(uint256).max); 
        MockERC20(Currency.unwrap(token1)).approve(hookAddress, type(uint256).max); 

        // initialize pool
       PoolId poolId;
       (key, poolId) = initPool(token0, token1, hook, 3000, SQRT_PRICE_1_1 );

       // add some liquidity 
       modifyLiquidityRouter.modifyLiquidity(
        key,
        ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 10 ether,
            salt: bytes32(0)
        }),
        ZERO_BYTES
       );

       modifyLiquidityRouter.modifyLiquidity(
        key,
        ModifyLiquidityParams({
            tickLower: -120,
            tickUpper: 120,
            liquidityDelta: 10 ether,
            salt: bytes32(0)
        }),
        ZERO_BYTES
       );


       modifyLiquidityRouter.modifyLiquidity(
        key,
        ModifyLiquidityParams({
            tickLower: TickMath.minUsableTick(60),
            tickUpper: TickMath.maxUsableTick(60),
            liquidityDelta: 10 ether,
            salt: bytes32(0)
        }),
        ZERO_BYTES
       );
    } 

    function test_place_order() public {
        // place a zeroForOne order 
        // sell 10 token0 for token1
        // when tick = 100 

        int24 tickAmountToSellAt = 100; 
        uint256 amount = 10e18; 
        bool zeroForOne = true; 

        uint256 originalToken0Balance = token0.balanceOfSelf();

        int24 tickForOrder = hook.placeOrder(key, tickAmountToSellAt, zeroForOne, amount);

        uint256 newTokenBalance = token0.balanceOfSelf();

        assertEq(tickForOrder, 60); 
        assertEq(originalToken0Balance - newTokenBalance, amount);

        // we should have received some erc-1155 tokens as well representing our placed order 
        uint256 positionId = hook.getPositionId(key, tickForOrder, zeroForOne);
        uint256 claimTokenBalance = hook.balanceOf(address(this), positionId);

        assertEq(claimTokenBalance, amount);
    }

    function test_cancel_order() public {

        int24 tickAmountToSellAt = 100; 
        uint256 amount = 10e18; 
        bool zeroForOne = true; 

        uint256 originalToken0Balance = token0.balanceOfSelf();

        int24 tickForOrder = hook.placeOrder(key, tickAmountToSellAt, zeroForOne, amount);

        uint256 newTokenBalance = token0.balanceOfSelf();

        assertEq(tickForOrder, 60); 
        assertEq(originalToken0Balance - newTokenBalance, amount);

        // we should have received some erc-1155 tokens as well representing our placed order 
        uint256 positionId = hook.getPositionId(key, tickForOrder, zeroForOne);
        uint256 claimTokenBalance = hook.balanceOf(address(this), positionId);

        assertEq(claimTokenBalance, amount);

        hook.cancelOrder(key, tickAmountToSellAt, zeroForOne, amount);

        uint256 finalToken0Balance = token0.balanceOfSelf();

        assertEq(finalToken0Balance, originalToken0Balance);
        claimTokenBalance = hook.balanceOf(address(this), positionId);
        assertEq(claimTokenBalance, 0); 
    }

    function test_orderExecute_zeroForOne() public {
        int24 tickToSellAt = 100; 
        uint256 amount = 1e18; 
        bool zeroForOne = true; 

        int24 tickForOrder = hook.placeOrder(key, tickToSellAt, zeroForOne, amount); 

        // do a seperate swap for oneForZero that makes the tick go up such that the above order should be executed 
        SwapParams memory swapParams = SwapParams({
            zeroForOne: false, 
            amountSpecified: -1 ether, 
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        }); 
        PoolSwapTest.TestSettings memory routerSettings = PoolSwapTest.TestSettings({
            takeClaims: false, 
            settleUsingBurn: false 
        }); 

        swapRouter.swap(key, swapParams, routerSettings, ZERO_BYTES); 

        uint256 pendingInputTokens = hook.pendingOrders(key.toId(), tickForOrder, zeroForOne); 
        assertEq(pendingInputTokens, 0); 

        uint256 positionId = hook.getPositionId(key, tickForOrder, zeroForOne); 
        uint256 claimableOutputTokens = hook.claimableOutputTokens(positionId); 
        uint256 hookToken1Balance = token1.balanceOf(address(hook));
        assertEq(claimableOutputTokens, hookToken1Balance); 

        uint256 originalToken1Balance = token1.balanceOfSelf();
        hook.redeem(key, tickForOrder, zeroForOne, amount);
        uint256 newToken1Balance =  token1.balanceOfSelf();

        assertEq(
            newToken1Balance - originalToken1Balance, 
            claimableOutputTokens
        ); 
    }


       function test_orderExecute_oneForZero() public {
        int24 tickToSellAt = -100; 
        uint256 amount = 1e18; 
        bool zeroForOne = false; 

        int24 tickForOrder = hook.placeOrder(key, tickToSellAt, zeroForOne, amount); 

        // do a seperate swap for oneForZero that makes the tick go up such that the above order should be executed 
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true , 
            amountSpecified: -1 ether, 
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        }); 
        PoolSwapTest.TestSettings memory routerSettings = PoolSwapTest.TestSettings({
            takeClaims: false, 
            settleUsingBurn: false 
        }); 

        swapRouter.swap(key, swapParams, routerSettings, ZERO_BYTES); 

        uint256 pendingInputTokens = hook.pendingOrders(key.toId(), tickForOrder, zeroForOne); 
        assertEq(pendingInputTokens, 0); 

        uint256 positionId = hook.getPositionId(key, tickForOrder, zeroForOne); 
        uint256 claimableOutputTokens = hook.claimableOutputTokens(positionId); 
        uint256 hookToken0Balance = token0.balanceOf(address(hook));
        assertEq(claimableOutputTokens, hookToken0Balance); 

        uint256 originalToken0Balance = token0.balanceOfSelf();
        hook.redeem(key, tickForOrder, zeroForOne, amount);
        uint256 newToken0Balance =  token0.balanceOfSelf();

        assertEq(
            newToken0Balance - originalToken0Balance, 
            claimableOutputTokens
        ); 
    }

    // function testMultipleOrderExecute_zeroForOne_onlyOneExecution() public {
         
    //     PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
    //         takeClaims: false, 
    //         settleUsingBurn: false 
    //     }); 

    //     // setup two zeroForOne orders at tick 60, 120 
    //     uint256 amount = 0.01 ether; 

    //     hook.placeOrder(key, 60, true, amount); 
    //     hook.placeOrder(key, 120, true, amount);

    //     SwapParams memory swapParams = IPoolManager.SwapParams({
    //         zeroForOne: false, 
    //         amountSpecified: -0.1 ether, 
    //         sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
    //     }); 

    //     swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES); 

    //     uint256 pendingInputTokensForOrderAtTick120 = hook.pendingOrders(key.toId(), 120, true); 
    //     assertEq(pendingInputTokensForOrderAtTick120, 0);

    //     uint256 pendingInputTokensForOrderAtTick60 = hook.pendingOrders(
    //         key.toId(), 

    //     )
    // }

    // ERC1155 Receiver implementation
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }
}