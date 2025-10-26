// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol"; 
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol"; 
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

// import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";


contract TakeProfitsHook is BaseHook, ERC1155 {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;
    using StateLibrary for IPoolManager; 

    mapping(PoolId poolId => mapping(int24 tickToExecuteAt => mapping(bool zeroForOne => uint256 inputAmount))) public pendingOrders; 

    mapping (uint256 positionId => uint256 claimSupply) public claimTokensSupply;
    mapping (uint256 positionId => uint256 outputClaimable) public claimableOutputTokens; 
    mapping(PoolId poolId => int24 lastTick) public lastKnownTick; 

    error NotEnoughClaimTokens();
    error NothingToClaim();

    constructor(
        IPoolManager _manager,  
        string memory _uri
    ) ERC1155(_uri) BaseHook(_manager) {

    }


    function getHookPermissions() 
    public 
    pure 
    override 
    returns(Hooks.Permissions memory)
    {
               return Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: true,
                beforeAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function _afterInitialize(
        address, 
        PoolKey calldata key, 
        uint160, 
        int24 tick
    ) internal override returns(bytes4) {
        lastKnownTick[key.toId()] = tick; 
        return this.afterInitialize.selector; 
    } 

    function _afterSwap(
        address sender, 
        PoolKey calldata key, 
        SwapParams calldata params,
        BalanceDelta, 
        bytes calldata  
    ) internal override returns(bytes4, int128) {
        // if we are entering this function after swap being made by the hook
        // we don't want to end-up in an endless recursive loop 
        if (sender == address(this)) return (this.afterSwap.selector, 0); 

        // we're gonna have a high level loop 
        // that just goes on until we break out of it 
        bool tryMore = true; 
        int24 currentTick; 

        while (tryMore) {
            // in the case there are no orders left to be executed, 
            // we should break out of this high-level loop 
            // and finish afterSwap 

            // in the case we do endup executing an order 
            // then this order will cause a further movement in the pool's tick value 
            // we kind of have to start again and look for new orders that might be valid again 
            // and should be executed
            // in the new "tick shift range" 

            (tryMore, currentTick) = tryExecutingOrders(
                key, 
                !params.zeroForOne
            ); 
        }

        lastKnownTick[key.toId()] = currentTick; 
        return (this.afterSwap.selector, 0); 
    }

    function tryExecutingOrders(
        PoolKey calldata key, 
        bool orderDirection
    ) internal returns(bool tryMore, int24 newTick) {
         // 1. get the current tick of the pool (tick after bob's orignal swap)
         (, int24 currentTick, , ) = poolManager.getSlot0(key.toId()); 
         // 2/ get the "last known tick"" of the pool (from our mapping)
         int24 lastTick = lastKnownTick[key.toId()]; 

        //  Case (1) if newTick > lastTick 
        if (currentTick > lastTick) {
            // loop from last tick to current tick 
            // iterating over 'tickspacing' amount over each time 
            // and execute orders looking to sell token 0
            for (int24 tick = lastTick; tick <= currentTick; tick += key.tickSpacing) {
                // execute an order if any 
                uint256 inputAmountToSell = pendingOrders[key.toId()][tick][orderDirection];
                if (inputAmountToSell > 0) {
                    executeOrder(key, tick, orderDirection, inputAmountToSell); 
                    return (true, currentTick); 
                }
            }
        } else {
            for (int24 tick = lastTick; tick >= currentTick;  tick -= key.tickSpacing) {
                uint256 inputAmountToSell = pendingOrders[key.toId()][tick][
                    orderDirection
                ]; 
                if (inputAmountToSell > 0) {
                    executeOrder(key, tick, orderDirection, inputAmountToSell); 
                    return (true, currentTick); 
                }
            }
        }
        // Case (2) if newTick < lastTick

        // if we find any orders in any case we execute the order 
        // and then return tryMore = true and the newTick value 

        // if we don't find anything to execute 
        // default return: tryMore = false, newTick = currentTick 
        return(false, currentTick); 
    }


    // Step one: PLACING ORDERS 
    function placeOrder(
        PoolKey calldata key, 
        int24 tickToSellAt, 
        bool zeroForOne, 
        uint256 inputAmount 
    ) external returns (int24) {
        int24 tickToExecuteAt = getLowerUsableTick(tickToSellAt, key.tickSpacing);

        // store the order 
        pendingOrders[key.toId()][tickToExecuteAt][zeroForOne] += inputAmount; 

        uint256 positionId = getPositionId(key, tickToExecuteAt, zeroForOne);
        claimTokensSupply[positionId] += inputAmount;
        _mint(msg.sender, positionId, inputAmount, "");

        // transfer input token from user to hook contract 
        address sellToken = zeroForOne ? Currency.unwrap(key.currency0) : Currency.unwrap(key.currency1);
        IERC20(sellToken).transferFrom(msg.sender, address(this), inputAmount);
        return tickToExecuteAt;
    }

    // cancel Order 
    function cancelOrder(
        PoolKey calldata key, 
        int24 tickToSellAt, 
        bool zeroForOne, 
        uint256 amountToCancel 
    ) external {
        int24 tickToExecuteAt = getLowerUsableTick(tickToSellAt, key.tickSpacing);
        uint256 positionId = getPositionId(key, tickToExecuteAt, zeroForOne);

        uint256 positionIdTokens = balanceOf(msg.sender, positionId); 
        if (positionIdTokens < amountToCancel) {
            revert NotEnoughClaimTokens(); 
        }

        pendingOrders[key.toId()][tickToExecuteAt][zeroForOne] -= amountToCancel;
        claimTokensSupply[positionId] -= amountToCancel;
        _burn(msg.sender, positionId, amountToCancel);

        // transfer input token back to user
        Currency token = zeroForOne ? key.currency0 : key.currency1;
        token.transfer(msg.sender, amountToCancel); 

    }

    //Step three: Redemption 
    function redeem(
        PoolKey calldata key, 
        int24 tick, 
        bool zeroForOne, 
        uint256 inputAmountToClaimFor
    ) external {
        int24 tickToExecuteAt = getLowerUsableTick(tick, key.tickSpacing); 
        uint256 positionId = getPositionId(key, tickToExecuteAt, zeroForOne);

        if(claimableOutputTokens[positionId] == 0) revert NothingToClaim(); 

        uint256 positionTokens = balanceOf(msg.sender, positionId); 
        if(positionTokens < inputAmountToClaimFor) revert NotEnoughClaimTokens(); 

        // percentage share of the input amount is used
        uint256 totalClaimableForPosition = claimableOutputTokens[positionId]; 
        uint256 totalInputAmountForPosition = claimTokensSupply[positionId]; 

        uint256 outputAmountToSend = (inputAmountToClaimFor * totalClaimableForPosition) / totalInputAmountForPosition; 

        // reduce claimable output tokens amount 
        // reduce claim token supply 
        // burn claim tokens 
        // transfer output tokens 
        claimableOutputTokens[positionId] -= outputAmountToSend; 
        claimTokensSupply[positionId] -= inputAmountToClaimFor; 
        _burn(msg.sender, positionId, inputAmountToClaimFor);

        Currency token = zeroForOne ? key.currency1 : key.currency0; 
        token.transfer(msg.sender, outputAmountToSend);
    }

    function executeOrder(PoolKey calldata key, int24 tick, bool zeroForOne, uint256 inputAmount) internal {
        // perform a swap 
        // settle balances for swap against the poolManager

        BalanceDelta delta = swapAndSettleBalances(
            key, 
            SwapParams({
                zeroForOne: zeroForOne, 
                amountSpecified: -int256(inputAmount), 
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            })
        ); 

        // update mappings 
        pendingOrders[key.toId()][tick][zeroForOne] -= inputAmount; 
        uint256 positionId = getPositionId(key, tick, zeroForOne); 
        uint256 outputAmount = zeroForOne ? uint256(int256(delta.amount1())) : uint256(int256(delta.amount0())); 

        claimableOutputTokens[positionId] += outputAmount; 
    } 



    // Helper function 
    function swapAndSettleBalances(
        PoolKey calldata key, 
        SwapParams memory params 
        ) internal returns (BalanceDelta) {
            // we don't need to unlock the poolManage rin this case 
            // because hook is already operating inside of an unlocked pool manager 

            BalanceDelta delta = poolManager.swap(key, params, ""); 

            // settle balances 
            if (params.zeroForOne) {
                // amount0 will be negative 
                // settle amount0 
                // amount1 will be positive 
                // take amount1 

                _settle(key.currency0, uint128(-delta.amount0())); 
                _take(key.currency1, uint128(delta.amount1()));
            } else {
                // settle amount1 
                // take amount0 

                _settle(key.currency1, uint128(-delta.amount1())); 
                _take(key.currency0, uint128(delta.amount0())); 
            }


            // settle 
            // sending money from swapper -> PM 
            // take 
            // taking money fro PM -> swapper 
            return delta; 
        }

    function _settle(Currency currency, uint128 amount) internal {
        poolManager.sync(currency); 
        currency.transfer(address(poolManager), amount);
        poolManager.settle();
    }

    function _take(Currency currency, uint128 amount) internal {
        // take tokens out of PM to hook contract 
        poolManager.take(currency, address(this), amount); 
    }



    function getLowerUsableTick(int24 tick, int24 tickSpacing) internal pure returns (int24) {
        // eg: if tickSpacing is 60 and tick is 100... then we lower down to 60
        int24 intervals = tick / tickSpacing; 

        if (tick < 0 && tick % tickSpacing != 0) intervals--; 

        return intervals * tickSpacing; 
    }

    function getPositionId(PoolKey calldata key, int24 tick, bool zeroForOne) public pure returns(uint256) {
        return uint256 (
            keccak256(abi.encode(key.toId(), tick, zeroForOne)) 
        ); 
    }
}