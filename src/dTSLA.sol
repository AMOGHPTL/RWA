// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/libraries/FunctionsRequest.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";


/**
 * @title dTSLA
 * @author Amogh Patil
 */

contract dTSLA is ConfirmedOwner ,FunctionsClient, ERC20{
    using FunctionsRequest for FunctionsRequest.Request;
    using Strings for uint256; 

    error dTSLA__NotEnoughCollateral();
    error dTSLA__LessThanMinimumWithdrawlAmount();
    error dTSLA__FailedToTransfer();

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
    address constant SEPOLIA_USDC_PRICE_FEEDS = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E; // USDC/USD
    address constant SEPOLIA_USDC = 0xf08A50178dfcDe18524640EA6618a1f965821715; // sepolia USDC address

    string public s_mintSourceCode;
    string public s_redeemSourceCode;

    uint64 immutable i_subId;
    uint32 constant GAS_LIMIT = 300_000; 
    bytes32 constant DON_ID = hex"66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000";
    mapping (bytes32 requestId => dTSLARequest request) private s_requestIdToRequest ;
    mapping (address user => uint256 pendingWithdrawlAmount) private s_userToWithdrawlAmount;

    uint256 private s_portfolioBalance;

    uint256 constant COLLATERAL_RATIO = 200; //200% collateral ratio
    // if we have $200 of TSLA in the brokerage we can mint AT MOST $100 of dTSLA
    uint256 constant COLLATERAL_PRECISION  = 100;
    uint256 constant MINIMUM_WITHDRAWL_AMOUNT = 100e18;

    uint8 donHostedSecretsSlotId = 0; // slot id where the DON is hosting the secret for the alpaca brokerage api key
    uint64 donHosteedSecretsVersion = 1777488370; // version of the secret being hosted by the DON

    constructor(string memory mintSourceCode, uint64 subId, string memory redeemSourceCode) ConfirmedOwner(msg.sender) FunctionsClient(SEPOLIA_FUNCTIONS_ROUTER) ERC20("dTSLA","dTSLA"){
        s_mintSourceCode = mintSourceCode;
        i_subId = subId;
        s_redeemSourceCode = redeemSourceCode;
    }

    // Send an http request to:
    // 1. See how many TSLA is bought 
    // 2. If there is enough TSLA in the alpaca account,
    // mint the dTSLA.
    // 2 txn function
    function sendMintRequest(uint256 amount) public onlyOwner returns (bytes32){
        FunctionsRequest.Request memory req;
        req.initializeRequest(
    FunctionsRequest.Location.Inline,
    FunctionsRequest.CodeLanguage.JavaScript,
    s_mintSourceCode
);
        req.addDONHostedSecret(donHostedSecretsSlotId, donHosteedSecretsVersion); // this is how we pass the alpaca api key securely to the chainlink function
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
    function sendReedemRequest(uint256 amountdTSLA) public returns(bytes32){
      uint256 amountTslaInUsdc = getUsdcValueOfUsd(getUsdValueOfTsla(amountdTSLA));
      if(amountTslaInUsdc < MINIMUM_WITHDRAWL_AMOUNT){
        revert dTSLA__LessThanMinimumWithdrawlAmount();
      }

       FunctionsRequest.Request memory req;
       req.initializeRequest(
    FunctionsRequest.Location.Inline,
    FunctionsRequest.CodeLanguage.JavaScript,
    s_redeemSourceCode
);

        string[] memory args = new string[](2);
        args[0] = amountdTSLA.toString(); // we are telling the brokerage to sell this much TSLA and 
        args[1] = amountTslaInUsdc.toString(); // send this much USDC back to the contract for the user to redeem
        req.setArgs(args);

        bytes32 requestId = _sendRequest(req.encodeCBOR(), i_subId, GAS_LIMIT, DON_ID);
        s_requestIdToRequest[requestId] = dTSLARequest(amountdTSLA ,msg.sender, MintOrReedem.redeem);
        

        _burn(msg.sender, amountdTSLA); // In order to get USDC the user has to burn the dTSLA.

        return requestId;
    }

    function _reedemFulFillRequest(bytes32 requestId, bytes memory response) internal {
        // assume for now this has 18 decimals
        uint256 usdcAmount = uint256(bytes32(response));
        if(usdcAmount == 0){
            uint256 amountOfdTSLABurned = s_requestIdToRequest[requestId].amountOfTokens;
            _mint(s_requestIdToRequest[requestId].requester, amountOfdTSLABurned);
            return;
        }

        s_userToWithdrawlAmount[s_requestIdToRequest[requestId].requester] += usdcAmount;
    }

    function withdraw() external {
        uint256 amountToWithdraw = s_userToWithdrawlAmount[msg.sender];
        s_userToWithdrawlAmount[msg.sender] = 0;

        bool success = ERC20(SEPOLIA_USDC).transfer(msg.sender, amountToWithdraw);
        if(!success){
            revert dTSLA__FailedToTransfer();
        }     
    }

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

    function getUsdcValueOfUsd(uint256 usdAmount) public view returns(uint256){
        return (usdAmount * getUsdcPrice()) / PRECISION;
    }

    function getUsdValueOfTsla(uint256 tslaAmount) public view returns(uint256){
        return (tslaAmount * getTslaPrice()) / PRECISION;
    }

    function getTslaPrice() public view returns(uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(SEPOLIA_TSLA_PRICE_FEEDS);
        (,int256 price,,,) = priceFeed.latestRoundData();
        return uint256(price) * ADDITIONAL_FEED_PRECISION; // So that we have 18 decimals
    }

    function getUsdcPrice() public view returns(uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(SEPOLIA_USDC_PRICE_FEEDS);
        (,int256 price,,,) = priceFeed.latestRoundData();
        return uint256(price) * ADDITIONAL_FEED_PRECISION; // So that we have 18 decimals

    }

    ///////////////////********************* view and getter functions *********************//////////////////////////

    function getPortfolioBalance() public view returns(uint256){
        return s_portfolioBalance;
    }

    function getRequestInfo(bytes32 requestId) public view returns(dTSLARequest memory){
        return s_requestIdToRequest[requestId];
    }

    function getPendingWithdrawlAmount(address user) public view returns(uint256){
        return s_userToWithdrawlAmount[user];
    }

    function getMintSourceCode() public view returns(string memory){
        return s_mintSourceCode;
    }

    function getRedeemSourceCode() public view returns(string memory){
        return s_redeemSourceCode; 
    }

    function getCollateralRatio() public pure returns(uint256){
        return COLLATERAL_RATIO;
    }

     function getMinimumWithdrawlAmount() public pure returns(uint256){
        return MINIMUM_WITHDRAWL_AMOUNT;
    }

    function getCollateralPrecision() public pure returns(uint256){
        return COLLATERAL_PRECISION;
    }

}