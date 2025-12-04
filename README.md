1. Relative stability : Anchored or Pegged -> $1.00
   1.  chainlink PriceFeed
   2.  Set a function to exchange ETH and BTC -> $$$
2. stability method : Algorithmic  (Decentralized)
    1. People can only mint the stablecoin with enough collateral(Coded)
3. Collateral : Exogenous (Crypto)
    1. wETH
    2. wBTC



- calculate health factor function
- set health factor if debt is 0
- Added a bunch of view functions


1. Invariant testing:
- You define a property of the system that must always remain true no matter what random sequence of calls, inputs, or interactions happen.
 
2. Open invariant testing:
- “Give Foundry the whole contract and tell it to try breaking the core properties of your protocol using any random function call it wants.”
- It is the highest-level stress test for protocol safety.
- If your invariant survives open invariant fuzzing, your system is actually robust, not just “tests-pass” robust.



- some checks to do before finallizing the project,
1. write / complete all unit test left for later
2. complete the fuzzing test , for both handler and invarient
3. write test also for DecentralizedStableCoin.sol
4. if you can , aslo try to update your helperconfig , for more on cahins deployment , other then sepolia and anvil
5. try to solve the prices carsh problem in code
6. at last read and try to understand whole project and project codes again