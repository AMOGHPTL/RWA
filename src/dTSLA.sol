// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/libraries/FunctionsRequest.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


/**
 * @title dTSLA
 * @author Amogh Patil
 */

contract dTSLA is ConfirmedOwner ,FunctionsClient, ERC20{
    using FunctionsRequest for FunctionsRequest.Request;

    error dTSLA__NotEnoughCollateral();

    enum MintOrReedem {
        mint,
        redeem
    }

    struct dTSLARequest{
        uint256 amountOfTokens;
        address requester;
        MintOrReedem mintOrRedeem;

    }

    // Math constants
    uint256 constant PRECISION = 1e18;
    uint256 constant ADDITIONAL_FEED_PRECISION = 1e10;
    
    address constant SEPOLIA_FUNCTIONS_ROUTER = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;
    address constant SEPOLIA_TSLA_PRICE_FEEDS = 0xc59E3633BAAC79493d908e63626716e204A45EdF; // this is actually LINK/USD for demo purpose only

    string public s_mintSourceCode;

    uint64 immutable i_subId;
    uint32 constant GAS_LIMIT = 300_000; 
    bytes32 constant DON_ID = hex"66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000";
    mapping (bytes32 requestId => dTSLARequest request) private s_requestIdToRequest ;

    uint256 private s_portfolioBalance;

    uint256 constant COLLATERAL_RATIO = 200; //200% collateral ratio
    // if we have $200 of TSLA in the brokerage we can mint AT MOST $100 of dTSLA
    uint256 constant COLLATERAL_PRECISION  = 100;

    constructor(string memory mintSourceCode, uint64 subId) ConfirmedOwner(msg.sender) FunctionsClient(SEPOLIA_FUNCTIONS_ROUTER) ERC20("dTSLA","dTSLA"){
        s_mintSourceCode = mintSourceCode;
        i_subId = subId;
    }

    // Send an http request to:
    // 1. See how many TSLA is bought 
    // 2. If there is enough TSLA in the alpaca account,
    // mint the dTSLA.
    // 2 txn function
    function sendMintRequest(uint256 amount) public onlyOwner returns (bytes32){
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavascript(s_mintSourceCode);
        bytes32 requestId = _sendRequest(req.encodeCBOR(), i_subId, GAS_LIMIT, DON_ID);
        s_requestIdToRequest[requestId] = dTSLARequest(amount ,msg.sender, MintOrReedem.mint);
        return requestId;
    }

    // Return the amount of TSLA value (in USD) is stored in our broker
    // If we have enough TSLA tokens mint the dTSLA
    function _mintFulFillRequest(bytes32 requestId, bytes memory response) internal {
        uint256 amountOfTokensToMint = s_requestIdToRequest[requestId].amountOfTokens;
        s_portfolioBalance = uint256(bytes32(response));

        // If TSLA we bought > dTSLA to mint -> mint dTSLA
        // How much TSLA in $ we have
        // How much dTSLA in $ are we minting 
        if(_getCollateralRatioAdjustedTotalBalance(amountOfTokensToMint) > s_portfolioBalance){
            revert dTSLA__NotEnoughCollateral();
        }
        if(amountOfTokensToMint != 0){
            _mint(s_requestIdToRequest[requestId].requester, amountOfTokensToMint); // Minting requester with amountOfTokensToMint if there is enoungh TSLA tokens in the brokerage
        }
    }

    /// @notice User sends a request to sell TSLA for USDC (redemptionToken)
    /// This will have our chainlink function call our alpaca (bank)
    /// and do the following :
    /// 1. Sell TSLA on brokarage
    /// 2. Buy USDC on brokarage
    /// 3. send the USDC to this contract for the user to withdraw
    function sendReedemRequest() public {}

    function _reedemFulFillRequest(bytes32 requestId, bytes memory response) internal {}

    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory /*err*/) internal override{
        if(s_requestIdToRequest[requestId].mintOrRedeem == MintOrReedem.mint){
            _mintFulFillRequest(requestId, response);
        } else {
            _reedemFulFillRequest(requestId, response);
        }
    }

    function _getCollateralRatioAdjustedTotalBalance(uint256 amountOfTokensToMint) internal view returns(uint256){
        uint256 calculatedNewTotalValue = getCalculatedNewTotalValue(amountOfTokensToMint);
        return (calculatedNewTotalValue * COLLATERAL_RATIO) / COLLATERAL_PRECISION;  
    }

    // The new expected total value in USD of all the dTSLA tokens combined
    function getCalculatedNewTotalValue(uint256 addedNumberOfTokens) internal  view returns(uint256){
        return ((totalSupply() + addedNumberOfTokens) * getTslaPrice()) / PRECISION;
    }

    function getTslaPrice() public view returns(uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(SEPOLIA_TSLA_PRICE_FEEDS);
        (,int256 price,,,) = priceFeed.latestRoundData();
        return price * ADDITIONAL_FEED_PRECISION; // So that we have 18 decimals
    }

}