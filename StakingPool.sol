// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "https://github.com/Uniswap/uniswap-v2-periphery/blob/master/contracts/interfaces/IUniswapV2Router02.sol";


contract StakingPool{
    uint public totalOriginalTokenDeposited;
    uint public totalCakeDeposited;

    address public owner;
    address private vice;

    // apy percentages
    uint public cakeApy = 500;
    uint public originalTokenApy = 50;

    uint private dateRange = 365 * 24 * 60 * 60; // fixed one year for the apy

    ERC20 public originalToken;
    ERC20 public cakeLpToken;

    struct user{
        uint lastOriginalTokenClaimTime;
        uint totalOriginalTokenStaked;
        uint lastCakeClaimTime; 
        uint totalCakeStaked; //same originalToken tokens but for those staking their cake
        uint totalActualCakeStaked; // shows their actual cake
        // uint totalOriginalTokenStaked;
    }
    mapping(address => user) public stakingDetails;

    IUniswapV2Router02 public uniswapV2Router;

    constructor(ERC20 _tokenAddress, ERC20 _lpAddress){
        originalToken = _tokenAddress;
        cakeLpToken = _lpAddress;
        owner = vice = msg.sender;
        uniswapV2Router = IUniswapV2Router02(0xD99D1c33F9fC3444f8101754aBC46c52416550D1); // v1 router testnet
        //uniswapV2Router = IUniswapV2Router02(); remember to use current router for deploy
    }

    modifier onlyOwner{
        require(owner == msg.sender || vice == msg.sender);
        _;
    }
    modifier hasOriginalTokenStaked{
        require(stakingDetails[msg.sender].totalOriginalTokenStaked > 0,"You have not staked any tokens");
        _;
    }
    modifier hasCakeStaked{
        require(stakingDetails[msg.sender].totalCakeStaked > 0,"You have not staked any cake");
        _;
    }

    function depositOriginalToken(uint _amount) public{
        originalToken.transferFrom(msg.sender,address(this),_amount);
        stakingDetails[msg.sender].lastOriginalTokenClaimTime = block.timestamp;
        stakingDetails[msg.sender].totalOriginalTokenStaked += _amount;
        totalOriginalTokenDeposited += _amount;
    }

    function depositCake(uint _amount) public{
        cakeLpToken.transferFrom(msg.sender,address(this),_amount);
        stakingDetails[msg.sender].totalCakeStaked += swapCakeBalanceForToken(_amount);
        stakingDetails[msg.sender].totalActualCakeStaked += _amount;
        stakingDetails[msg.sender].lastCakeClaimTime = block.timestamp;
        totalCakeDeposited += _amount;
    }

    function originalTokenBalance() public view returns (uint){
        return originalToken.balanceOf(address(this));
    }

    function cakeBalance() public view returns (uint){
        return cakeLpToken.balanceOf(address(this));
    }

    function setCakeApy(uint _cakeApy) public onlyOwner{
        cakeApy = _cakeApy;
    }

    function setOriginalTokenApy(uint _originalTokenApy) public onlyOwner{
        originalTokenApy = _originalTokenApy;
    }

    function calculateUserOriginalTokenEarnings(address _user) public view returns(uint){
        if(stakingDetails[_user].totalOriginalTokenStaked > 0){
            uint timePassed = block.timestamp - stakingDetails[_user].lastOriginalTokenClaimTime;
            uint currentPercentageReturns = (((timePassed * originalTokenApy) / dateRange) * stakingDetails[_user].totalOriginalTokenStaked) / 100;
            return currentPercentageReturns;
        }
        return 0;
    }

    function calculateUserCakeEarnings(address _user) public view returns(uint){
        if(stakingDetails[_user].totalCakeStaked > 0){
            uint timePassed = block.timestamp - stakingDetails[_user].lastCakeClaimTime;
            uint currentPercentageReturns = (((timePassed * cakeApy) / dateRange) * stakingDetails[_user].totalCakeStaked) / 100;
            return currentPercentageReturns;
        }
        return 0;
    }

    function compoundOriginalTokenStake() public hasOriginalTokenStaked {
        // get the current profits and add it to the stake
        uint currentPercentageReturns = calculateUserOriginalTokenEarnings(msg.sender);
        stakingDetails[msg.sender].totalOriginalTokenStaked += currentPercentageReturns;
        stakingDetails[msg.sender].lastOriginalTokenClaimTime = block.timestamp;
    }

    function compoundCakeStake() public hasCakeStaked {
        // get the current profits and add it to the stake
        uint currentPercentageReturns = calculateUserCakeEarnings(msg.sender);
        stakingDetails[msg.sender].totalCakeStaked += currentPercentageReturns;
        stakingDetails[msg.sender].lastCakeClaimTime = block.timestamp;
    }

    function withdrawOriginalToken(uint _amount) public hasOriginalTokenStaked {
        compoundOriginalTokenStake();
        // withdrawing from staked amount and make the transfer
        require(_amount <= stakingDetails[msg.sender].totalOriginalTokenStaked, "Insufficient staking balance");
        stakingDetails[msg.sender].totalOriginalTokenStaked -= _amount;
        stakingDetails[msg.sender].lastOriginalTokenClaimTime = block.timestamp;
        originalToken.approve(address(this),_amount);
        originalToken.transferFrom(address(this),msg.sender,_amount);
    }

    function withdrawCake(uint _amount) public hasCakeStaked {
        compoundCakeStake();
        // withdrawing from staked amount and make the transfer
        require(_amount <= stakingDetails[msg.sender].totalCakeStaked, "Insufficient staking balance");
        stakingDetails[msg.sender].totalCakeStaked -= _amount;
        stakingDetails[msg.sender].lastCakeClaimTime = block.timestamp;
        stakingDetails[msg.sender].totalActualCakeStaked = 0;
        originalToken.approve(address(this),_amount);
        originalToken.transferFrom(address(this),msg.sender,_amount);
    }

    //New Pancakeswap router version?
    //No problem, just change it!
    function setRouterAddress(address newRouter) public onlyOwner() {
       //Thank you FreezyEx
        IUniswapV2Router02 _newPancakeRouter = IUniswapV2Router02(newRouter);
        uniswapV2Router = _newPancakeRouter;
    }

    function swapCakeBalanceForToken(uint256 tokenAmount) private returns(uint){
        // to get the amount received afterwards
        uint previousBalance = originalTokenBalance();

        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(cakeLpToken);
        path[1] = address(originalToken);

        cakeLpToken.approve(address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of cake
            path,
            address(this),
            block.timestamp
        );

        uint originalTokenReceived = originalTokenBalance() - previousBalance;
        return originalTokenReceived;
    }

    /* Remember to add these
        1) ownership transfer
        2) ownership activities
        */

        function changeOriginalToken(ERC20 _tokenAddress) public onlyOwner {
            originalToken = _tokenAddress;
        }
        function changeCakeToken(ERC20 _tokenAddress) public onlyOwner {
            cakeLpToken = _tokenAddress;
        }
        function transferOwnership(address _owner) public onlyOwner{
            owner = _owner;
        }

}