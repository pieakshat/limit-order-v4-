
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

### Mechanism design for aterSwap 

Consider token pool A/B. let's say current tick = 0. 

Alice places an order to sell at tick = 100 

bob comes aroud, buys A for B, therefore increasing A's relative price and therefore the tick in the pool 

new tick after bob's swap is 200 

-- 
inside 'afterSwap' of Bob's transaction, we need to look at "current tick" of the pool 
-> since this is afterSwap, the current tick = new tick of the pool because of Bob's swap 
-> tell us it is now 200 
-> TODO; somehow, we need to know what the tick of the pool was prior to Bob's swap

once we have the info that it was 0 initially 

then we can loop through our pending orders and try and find an order with direction opposite to Bob's swap within the range of tick 0 to 200 

if there are mutiple orders within a range 

let's say Charlie and Alice had orders placed within 0-200 

when we're looking through our pending orders, let's say Alice's comes first and we execute Alice's order 

We must be cognizant about the fact that executing Alice's order will further shift the tick of the pool and this may cause charlie's order to become "invalid" at this point  

insight #2: be careful about what orders you are executing if there are multiple potential orders that can be executed 

bob calls swap() 
Hook goes into afterSwap()  
hook finds an order that can be executed
hook calls swap()

