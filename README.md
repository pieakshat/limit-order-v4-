
## Mechanism design 

1. Place Order 
2. Cancel 
3. redeem output tokens 

These things don't have anything to do with uniswap 

current price is 1 ETH = 2000 USDC 
sell 1 ETH = 2500 USDC 


## Placing an order 

1. Tick the price to execute an order at 
2. zeroForOne (A to B) or (B to A)
3. amount 
4. PoolId 

we will round down to the closest usable tick value 

when we're searching for orders to execute, we need to look at the "last tick" vs "new tick" and we need to find any orders placed within that window 

we're only gonna allow placing limit orders at multiples of tick spacing  


### After placing orders 
- Alice has 5 claim tokens 
- Bob has 3 claim tokens 

ticks shift and both of their orders are filled 

1. We need to some place to store the amount of output tokens we got back from executing their orders
2. based on the claim tokens that alice and bob individually have, we need a way to calculate what % of output tokens belong to them individually? 

