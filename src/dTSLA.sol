// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * @title dTSLA
 * @author Amogh Patil
 */

contract dTSLA {
    constructor() {
        
    }

    // Send an http request to:
    // 1. See how many TSLA is bought 
    // 2. If there is enough TSLA in the alpaca account,
    // mint the dTSLA.
    // 2 txn function
    function sendMintRequest() public {
           
    }

    function _mintFulFillRequest() internal {}

    /// @notice User sends a request to sell TSLA for USDC (redemptionToken)
    /// This will have our chainlink function call our alpaca (bank)
    /// and do the following :
    /// 1. Sell TSLA on brokarage
    /// 2. Buy USDC on brokarage
    /// 3. send the USDC to this contract for the user to withdraw
    function sendReedemRequest() pubic {}

    function _reedemFulFillRequest() internal {}
}