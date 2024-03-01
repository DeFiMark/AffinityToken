//SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import "./IERC20.sol";
import "./ReentrantGuard.sol";

/** Distributes Vault Tokens and Surge Tokens To Holders Varied on Weight */
contract Distributor is ReentrancyGuard {
    
    // Affinity Token Contract
    address public immutable affinity;

    struct UserInfo {
        uint256 balance;
        uint256 totalExcluded;
    }
    
    // Share of Vault
    struct Share {
        uint256 amount;
        uint256 totalExcluded;
    }
    
    // shareholder fields
    address[] shareholders;
    mapping (address => uint256) shareholderIndexes;
    mapping (address => uint256) shareholderClaims;
    mapping (address => Share) public shares;
    
    // shares math and fields
    uint256 public totalShares;
    uint256 public totalDividends;
    uint256 public dividendsPerShare;
    uint256 constant dividendsPerShareAccuracyFactor = 10 ** 18;
    
    // blocks until next distribution
    uint256 public minPeriod = 3600;
    // auto claim every 10 minutes if able
    uint256 public constant minAutoPeriod = 200;
    // 0.01 minimum bnb distribution
    uint256 public minDistribution = 1 * 10**16;

    // current index in shareholder array 
    uint256 currentIndex;
    
    // owner of token contract - used to pair with Vault Token
    address _master;

    uint256 pullDataIndex;

    mapping ( address => bool ) rewardlessWallets;
    
    modifier onlyToken() {
        require(msg.sender == affinity); _;
    }
    
    modifier onlyMaster() {
        require(msg.sender == _master, 'Invalid Entry'); _;
    }

    constructor (address token) {
        affinity = token;
        rewardlessWallets[address(this)] = true;
    }
    
    ///////////////////////////////////////////////
    //////////      Only Token Owner    ///////////
    ///////////////////////////////////////////////

    function pullDataFromOldDistributor(uint256 iterations) external onlyMaster returns (bool) {
        IDistributor oldDistributor = IDistributor(payable(0x9F2D2E24a98f1841D186DB13CFf00e8773b1001B));

        address[] memory holders = oldDistributor.getShareholders();
        uint256 amount;

        for (uint i = 0; i < iterations; i++) {
            if (pullDataIndex >= holders.length) {
                pullDataIndex = 0;
                return true;
            }
            addShareholder(holders[pullDataIndex]);
            amount = oldDistributor.getShareForHolder(holders[pullDataIndex]);
            totalShares += amount;
            shares[holders[pullDataIndex]].amount = amount;
            pullDataIndex++;
        }
        return false;
    }

    function setRewardlessWallet(address wallet, bool rewardless) external onlyMaster {
        rewardlessWallets[wallet] = rewardless;
    }

    function transferOwnership(address newOwner) external onlyMaster {
        _master = newOwner;
        emit TransferedOwnership(newOwner);
    }
    
    /** Withdraw Assets Mistakingly Sent To Distributor, And For Upgrading If Necessary */
    function withdraw(bool bnb, address token, uint256 amount) external onlyMaster {
        if (bnb) {
            (bool s,) = payable(_master).call{value: amount}("");
            require(s);
        } else {
            IERC20(token).transfer(_master, amount);
        }
    }
    
    /** Sets Distibution Criteria */
    function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution) external onlyMaster {
        minPeriod = _minPeriod;
        minDistribution = _minDistribution;
        emit UpdateDistributorCriteria(_minPeriod, _minDistribution);
    }
    
    ///////////////////////////////////////////////
    //////////    Only Token Contract   ///////////
    ///////////////////////////////////////////////
    
    /** Sets Share For User */
    function setShare(address shareholder, uint256 amount) external override onlyToken {

        if (rewardlessWallets[shareholder]) {
            return;
        }

        if(shares[shareholder].amount > 0 && !Address.isContract(shareholder)){
            distributeDividend(shareholder);
        }

        if(amount > 0 && shares[shareholder].amount == 0){
            addShareholder(shareholder);
        }else if(amount == 0 && shares[shareholder].amount > 0){
            removeShareholder(shareholder);
        }

        totalShares = totalShares.sub(shares[shareholder].amount).add(amount);
        shares[shareholder].amount = amount;
        shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);
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
    //             distributeDividend(shareholders[currentIndex]);
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


    function addShareholder(address shareholder) internal {
        shareholderIndexes[shareholder] = shareholders.length;
        shareholders.push(shareholder);
        emit AddedShareholder(shareholder);
    }

    function removeShareholder(address shareholder) internal { 
        shareholders[shareholderIndexes[shareholder]] = shareholders[shareholders.length-1];
        shareholderIndexes[shareholders[shareholders.length-1]] = shareholderIndexes[shareholder]; 
        shareholders.pop();
        delete shareholderIndexes[shareholder];
        emit RemovedShareholder(shareholder);
    }
    

    function distributeDividend(address shareholder) internal nonReentrant {
        if(shares[shareholder].amount == 0){ return; }
        
        uint256 amount = getUnpaidMainEarnings(shareholder);
        if(amount > 0){
            payable(shareholder).transfer(amount);
            shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);
            shareholderClaims[shareholder] = block.number;
        }
    }
    
    function _claimDividend(address shareholder) private {
        require(shareholderClaims[shareholder] + minAutoPeriod < block.number, 'Timeout');
        require(shares[shareholder].amount > 0, 'Zero Balance');
        uint256 amount = getUnpaidMainEarnings(shareholder);
        require(amount > 0, 'Zero To Claim');

        shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);
        shareholderClaims[shareholder] = block.number;
        
        (bool s,) = payable(shareholder).call{value: amount}("");
        require(s, 'Failure on BNB Received');
    }

    function _reinvestRewards() private {
        require(shareholderClaims[msg.sender] + minAutoPeriod < block.number, 'Timeout');
        require(shares[msg.sender].amount > 0, 'Zero Balance');
        uint256 amount = getUnpaidMainEarnings(msg.sender);
        require(amount > 0, 'Zero To Claim');

        shares[msg.sender].totalExcluded = getCumulativeDividends(shares[msg.sender].amount);
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
        return shareholderClaims[shareholder] + minPeriod < block.number
        && getUnpaidMainEarnings(shareholder) >= minDistribution
        && !Address.isContract(shareholder);
    }
    
    function getShareholders() external view override returns (address[] memory) {
        return shareholders;
    }
    
    function getShareForHolder(address holder) external view override returns(uint256) {
        return shares[holder].amount;
    }

    function getUnpaidMainEarnings(address shareholder) public view returns (uint256) {
        if(shares[shareholder].amount == 0){ return 0; }

        uint256 shareholderTotalDividends = getCumulativeDividends(shares[shareholder].amount);
        uint256 shareholderTotalExcluded = shares[shareholder].totalExcluded;

        if(shareholderTotalDividends <= shareholderTotalExcluded){ return 0; }

        return shareholderTotalDividends.sub(shareholderTotalExcluded);
    }
    
    function getCumulativeDividends(uint256 share) internal view returns (uint256) {
        return share.mul(dividendsPerShare).div(dividendsPerShareAccuracyFactor);
    }

    function getNumShareholdersForDistributor(address distributor) external view returns(uint256) {
        return IDistributor(distributor).getShareholders().length;
    }
    
    function getNumShareholders() external view returns(uint256) {
        return shareholders.length;
    }

    // EVENTS 
    event TokenPaired(address pairedToken);
    event UpgradeDistributor(address newDistributor);
    event AddedShareholder(address shareholder);
    event RemovedShareholder(address shareholder);
    event TransferedOwnership(address newOwner);
    event UpdateDistributorCriteria(uint256 minPeriod, uint256 minDistribution);

    receive() external payable {
        totalDividends = totalDividends.add(msg.value);
        dividendsPerShare = dividendsPerShare.add(dividendsPerShareAccuracyFactor.mul(msg.value).div(totalShares));
    }

}