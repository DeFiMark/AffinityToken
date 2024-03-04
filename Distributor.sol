//SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import "./IERC20.sol";
import "./ReentrantGuard.sol";

interface IAffinity {
    function getOwner() external view returns (address);
    function getHolderAtIndex(uint256 index) external view returns (address);
    function getNumberOfHolders() external view returns (uint256);
}

/** Distributes Tokens To Affinity Holders */
contract Distributor is ReentrancyGuard {
    
    // Affinity Token Contract
    address public immutable affinity;

    // User info
    struct UserInfo {
        uint256 balance;
        uint256 totalClaim;
        uint256 totalExcluded;
        bool isRewardExempt;
    }
    
    // shareholder fields
    mapping ( address => UserInfo ) public userInfo;
    
    // shares math and fields
    uint256 public totalShares;
    uint256 public totalDividends;
    uint256 public dividendsPerShare;
    uint256 private constant PRECISION = 10 ** 18;
    
    // 0.01 minimum bnb distribution
    uint256 public minDistribution = 1 * 10**16;

    // current index in shareholder array 
    uint256 public currentIndex;
    
    modifier onlyToken() {
        require(msg.sender == affinity); 
        _;
    }
    
    modifier onlyTokenOwner() {
        require(msg.sender == IAffinity(affinity).getOwner(), 'Not Permitted'); 
        _;
    }

    constructor (address token) {
        affinity = token;
        userInfo[address(this)].isRewardExempt = true;
        userInfo[affinity].isRewardExempt = true;
    }
    
    ///////////////////////////////////////////////
    //////////      Only Token Owner    ///////////
    ///////////////////////////////////////////////

    function setRewardExempt(address wallet, bool rewardless) external onlyTokenOwner {
        userInfo[wallet].isRewardExempt = rewardless;
    }
    
    /** Withdraw Assets Mistakingly Sent To Distributor, And For Upgrading If Necessary */
    function withdraw(bool bnb, address token, uint256 amount) external onlyTokenOwner {
        if (bnb) {
            (bool s,) = payable(msg.sender).call{value: amount}("");
            require(s);
        } else {
            IERC20(token).transfer(msg.sender, amount);
        }
    }
    
    /** Sets Distibution Criteria */
    function setMinDistribution(uint256 _minDistribution) external onlyTokenOwner {
        minDistribution = _minDistribution;
    }
    
    ///////////////////////////////////////////////
    //////////    Only Token Contract   ///////////
    ///////////////////////////////////////////////
    
    /** Sets Share For User */
    function setShare(address shareholder, uint256 amount) external override onlyToken {

        if (userInfo[shareholder].isRewardExempt) {
            return;
        }

        if(userInfo[shareholder].balance > 0 && !Address.isContract(shareholder)){
            claimRewards(shareholder);
        }

        totalShares = ( totalShares + amount ) - userInfo[shareholder].balance;
        userInfo[shareholder].balance = amount;
        userInfo[shareholder].totalExcluded = getCumulativeDividends(userInfo[shareholder].balance);
    }
    
    ///////////////////////////////////////////////
    //////////      Public Functions    ///////////
    ///////////////////////////////////////////////
    
    function claimDividendForUser(address shareholder) external nonReentrant {
        _claimDividend(shareholder);
    }

    function reinvestRewards() external nonReentrant {
        _reinvestRewards();
    }
    
    function claimDividend() external nonReentrant {
        _claimDividend(msg.sender);
    }

    function process() external {
        _process(iterations_per_transfer);
    }

    function processSetNumberOfIterations(uint256 iterations) {
        _process(iterations);
    }

    function _process(uint256 iterations) internal {

    }
    
    // function process(uint256 gas) external override {
    //     uint256 shareholderCount = shareholders.length;

    //     if(shareholderCount == 0) { return; }

    //     uint256 gasUsed = 0;
    //     uint256 gasLeft = gasleft();

    //     uint256 iterations = 0;
        
    //     while(gasUsed < gas && iterations < shareholderCount) {
    //         if(currentIndex >= shareholderCount){
    //             currentIndex = 0;
    //         }
            
    //         if(shouldDistribute(shareholders[currentIndex])){
    //             claimRewards(shareholders[currentIndex]);
    //         }
            
    //         gasUsed += (gasLeft - gasleft());
    //         gasLeft = gasleft();
    //         currentIndex++;
    //         iterations++;
    //     }
    // }


    ///////////////////////////////////////////////
    //////////    Internal Functions    ///////////
    ///////////////////////////////////////////////


    function claimRewards(address shareholder) internal nonReentrant {
        if(userInfo[shareholder].balance == 0){ return; }
        
        uint256 amount = pendingRewards(shareholder);
        userInfo[shareholder].totalExcluded = getCumulativeDividends(userInfo[shareholder].balance);
        if(amount > 0){
            payable(shareholder).transfer(amount);
        }
    }

    function _reinvestRewards() private {
        require(shareholderClaims[msg.sender] + minAutoPeriod < block.number, 'Timeout');
        require(userInfo[msg.sender].balance > 0, 'Zero Balance');
        uint256 amount = pendingRewards(msg.sender);
        require(amount > 0, 'Zero To Claim');

        userInfo[msg.sender].totalExcluded = getCumulativeDividends(userInfo[msg.sender].balance);
        shareholderClaims[msg.sender] = block.number;

        uint256 before = IERC20(_token).balanceOf(address(this));
        (bool s,) = payable(_token).call{value: amount}("");
        require(s, 'Failure on BNB Received');

        uint256 diff = IERC20(_token).balanceOf(address(this)) - before;
        require(diff > 0, 'Zero Tokens Purchased');

        IERC20(_token).transfer(msg.sender, diff);
    }
    
    ///////////////////////////////////////////////
    //////////      Read Functions      ///////////
    ///////////////////////////////////////////////
    
    function shouldDistribute(address shareholder) internal view returns (bool) {
        if (userInfo[shareholder].isRewardExempt || userInfo[shareholder].balance == 0) {
            return false;
        }
        return pendingRewards(shareholder) >= minDistribution;
    }

    function getShareForHolder(address holder) external view override returns(uint256) {
        return userInfo[holder].balance;
    }

    function pendingRewards(address shareholder) public view returns (uint256) {
        if(userInfo[shareholder].balance == 0){ return 0; }

        uint256 shareholderTotalDividends = getCumulativeDividends(userInfo[shareholder].balance);
        uint256 shareholderTotalExcluded = userInfo[shareholder].totalExcluded;

        if(shareholderTotalDividends <= shareholderTotalExcluded){ return 0; }

        return shareholderTotalDividends.sub(shareholderTotalExcluded);
    }
    
    function getCumulativeDividends(uint256 share) internal view returns (uint256) {
        return ( share * dividendsPerShare ) / PRECISION;
    }

    receive() external payable {
        unchecked {
            totalDividends += msg.value;
            dividendsPerShare += ( msg.value * PRECISION ) / totalShares;
        }
    }

}