//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;
    constructor () {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}


interface IUniswapV2Router01 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountETH);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
    external
    payable
    returns (uint[] memory amounts);
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
    external
    returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
    external
    returns (uint[] memory amounts);
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
    external
    payable
    returns (uint[] memory amounts);

    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}

interface IUniswapV2Router02 is IUniswapV2Router01 {
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountETH);
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountETH);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

interface IUniswapV2Factory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
}

interface IERC20 {

    function totalSupply() external view returns (uint256);
    
    function symbol() external view returns(string memory);
    
    function name() external view returns(string memory);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);
    
    /**
     * @dev Returns the number of decimal places
     */
    function decimals() external view returns (uint8);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}


library Address {

    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // According to EIP-1052, 0x0 is the value returned for not-yet created accounts
        // and 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470 is returned
        // for accounts without code, i.e. `keccak256('')`
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly { codehash := extcodehash(account) }
        return (codehash != accountHash && codehash != 0x0);
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain`call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        return _functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        return _functionCallWithValue(target, data, value, errorMessage);
    }

    function _functionCallWithValue(address target, bytes memory data, uint256 weiValue, string memory errorMessage) private returns (bytes memory) {
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: weiValue }(data);
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }

}

interface IAffinity {
    function getOwner() external view returns (address);
    function getHolderAtIndex(uint256 index) external view returns (address);
    function getNumberOfHolders() external view returns (uint256);
}

/** Distributes Tokens To Affinity Holders */
contract Distributor is ReentrancyGuard {
    
    // Affinity Token Contract
    address public affinity;

    // Reward Token Contract
    address public rewardToken = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;

    // Uniswap Router
    IUniswapV2Router02 public constant router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    // User info
    struct UserInfo {
        uint256 balance;
        uint256 totalClaimed;
        uint256 totalClaimedTokens;
        uint256 totalExcluded;
        uint256 totalExcludedToken;
        bool isRewardExempt;
    }
    
    // shareholder fields
    mapping ( address => UserInfo ) public userInfo;
    
    // shares math and fields
    uint256 public totalShares;
    uint256 public totalDividends;
    uint256 public totalDividendsToken;
    uint256 public dividendsPerShare;
    uint256 public dividendsPerShareToken;
    uint256 private constant PRECISION = 10 ** 18;
    
    // 0.01 minimum bnb distribution
    uint256 public minDistribution = 1 * 10**16;
    uint256 public minDistributionTokens = 2 * 10**18;

    // current index in shareholder array 
    uint256 public currentIndex;
    
    // number of iterations per transaction
    uint256 public iterations_per_transfer = 10;

    modifier onlyToken() {
        require(msg.sender == affinity, 'Not Permitted'); 
        _;
    }
    
    modifier onlyTokenOwner() {
        require(msg.sender == IAffinity(affinity).getOwner(), 'Not Permitted'); 
        _;
    }

    constructor () {
        userInfo[address(this)].isRewardExempt = true;
    }
    
    ///////////////////////////////////////////////
    //////////      Only Token Owner    ///////////
    ///////////////////////////////////////////////

    function pairToken(address token) external {
        require(token != address(0), 'Zero Token');
        require(affinity == address(0), 'Already Paired');
        affinity = token;
        userInfo[token].isRewardExempt = true;
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
    function setMinDistributionTokens(uint256 _minDistributionTokens) external onlyTokenOwner {
        minDistributionTokens = _minDistributionTokens;
    }

    function setRewardToken(address token) external onlyTokenOwner {
        rewardToken = token;
    }

    function setCurrentIndex(uint256 index) external onlyTokenOwner {
        currentIndex = index;
    }

    function setIterationsPerTransfer(uint256 iterations) external onlyTokenOwner {
        iterations_per_transfer = iterations;
    }

    function setAffinity(address _affinity) external onlyTokenOwner {
        affinity = _affinity;
    }
    
    ///////////////////////////////////////////////
    //////////    Only Token Contract   ///////////
    ///////////////////////////////////////////////

    function setRewardExempt(address wallet, bool rewardless) external onlyToken {
        userInfo[wallet].isRewardExempt = rewardless;
    }
    
    /** Sets Share For User */
    function setShare(address shareholder, uint256 amount) external onlyToken {

        if (userInfo[shareholder].isRewardExempt) {
            return;
        }

        if(userInfo[shareholder].balance > 0 && !Address.isContract(shareholder)){
            _claimRewards(shareholder);
        }

        totalShares = ( totalShares + amount ) - userInfo[shareholder].balance;
        userInfo[shareholder].balance = amount;
        userInfo[shareholder].totalExcluded = getCumulativeDividends(userInfo[shareholder].balance);
        userInfo[shareholder].totalExcludedToken = getCumulativeRewardTokenDividends(userInfo[shareholder].balance);
    }
    
    ///////////////////////////////////////////////
    //////////      Public Functions    ///////////
    ///////////////////////////////////////////////
    
    function batchClaim(address[] calldata shareholders) external {
        uint len = shareholders.length;
        for (uint i = 0; i < len;) {
            _claimRewards(shareholders[i]);
            unchecked { ++i; }
        }
    }

    function claimRewards() external {
        _claimRewards(msg.sender);
    }

    function process() external {
        _process(iterations_per_transfer);
    }

    function processSetNumberOfIterations(uint256 iterations) external {
        _process(iterations);
    }

    function giveTokenRewards(uint256 amount) external {
        require(totalShares > 0, "No Shares");
        uint256 balBefore = IERC20(rewardToken).balanceOf(address(this));
        IERC20(rewardToken).transferFrom(msg.sender, address(this), amount);
        uint256 balAfter = IERC20(rewardToken).balanceOf(address(this));
        require(balAfter >= balBefore, "Transfer Failed");
        uint256 asRewardTokensReceived = balAfter - balBefore;
        unchecked {
            totalDividendsToken += asRewardTokensReceived;
            dividendsPerShareToken += ( asRewardTokensReceived * PRECISION ) / totalShares;
        }
    }

    function giveBNBRewards() external payable {
        require(totalShares > 0, "No Shares");
        unchecked {
            totalDividends += msg.value;
            dividendsPerShare += ( msg.value * PRECISION ) / totalShares;
        }
    }

    function giveRewards() external payable {
        _onReceive();
    }

    receive() external payable {
        _onReceive();
    }


    ///////////////////////////////////////////////
    //////////    Internal Functions    ///////////
    ///////////////////////////////////////////////


    function _claimRewards(address shareholder) internal nonReentrant {
        if(userInfo[shareholder].balance == 0){ return; }
        
        (uint256 amountBNB, uint256 amountTokens) = pendingRewards(shareholder);
        userInfo[shareholder].totalExcluded = getCumulativeDividends(userInfo[shareholder].balance);
        userInfo[shareholder].totalExcludedToken = getCumulativeRewardTokenDividends(userInfo[shareholder].balance);
        if (amountBNB > 0) {
            (bool s,) = payable(shareholder).call{value: amountBNB}("");
            require(s);
            unchecked {
                userInfo[shareholder].totalClaimed += amountBNB;
            }
        }
        if (amountTokens > 0) {
            IERC20(rewardToken).transfer(shareholder, amountTokens);
            unchecked {
                userInfo[shareholder].totalClaimedTokens += amountTokens;
            }
        }
    }

    function _process(uint256 iterations) internal {
        uint256 shareholderCount = IAffinity(affinity).getNumberOfHolders();
        if(shareholderCount == 0) { return; }

        for (uint i = 0; i < iterations;) {

            // if index overflows, reset to 0
            if (currentIndex >= shareholderCount) {
                currentIndex = 0;
            }

            // fetch holder at current index
            address holder = IAffinity(affinity).getHolderAtIndex(currentIndex);

            if (holder != address(0) && shouldDistribute(holder) && !Address.isContract(holder)) {
                _claimRewards(holder);
            }

            unchecked { ++i; ++currentIndex; }
        }
    }

    function _onReceive() internal {
        if (totalShares == 0) {
            return;
        }
        
        // split bnb received
        uint256 asBNB = msg.value / 2;
        uint256 asRewardTokens = msg.value - asBNB;

        // swap bnb for reward tokens
        uint256 balBefore = IERC20(rewardToken).balanceOf(address(this));
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = rewardToken;
        router.swapExactETHForTokens{value: asRewardTokens}(1, path, address(this), block.timestamp + 100);
        delete path;
        uint256 balAfter = IERC20(rewardToken).balanceOf(address(this));
        require(balAfter >= balBefore, "Swap Failed");
        uint256 asRewardTokensReceived = balAfter - balBefore;

        // add both bnb and tokens to rewards
        unchecked {
            totalDividends += asBNB;
            dividendsPerShare += ( asBNB * PRECISION ) / totalShares;

            totalDividendsToken += asRewardTokensReceived;
            dividendsPerShareToken += ( asRewardTokensReceived * PRECISION ) / totalShares;
        }
    }
    
    ///////////////////////////////////////////////
    //////////      Read Functions      ///////////
    ///////////////////////////////////////////////
    
    function shouldDistribute(address shareholder) internal view returns (bool) {
        if (userInfo[shareholder].isRewardExempt || userInfo[shareholder].balance == 0) {
            return false;
        }
        (uint256 amountBNB, uint256 amountTokens) = pendingRewards(shareholder);
        return amountBNB >= minDistribution && amountTokens >= minDistributionTokens;
    }

    function getShareForHolder(address holder) external view returns(uint256) {
        return userInfo[holder].balance;
    }

    function pendingRewards(address shareholder) public view returns (uint256 amountBNB, uint256 amountTokens) {
        if(userInfo[shareholder].balance == 0){ return (0,0); }

        uint256 shareholderTotalDividends = getCumulativeDividends(userInfo[shareholder].balance);
        uint256 shareholderTotalExcluded = userInfo[shareholder].totalExcluded;

        uint256 shareholderTotalDividendsToken = getCumulativeRewardTokenDividends(userInfo[shareholder].balance);
        uint256 shareholderTotalExcludedToken = userInfo[shareholder].totalExcludedToken;

        if ( shareholderTotalDividends > shareholderTotalExcluded ) {
            amountBNB = shareholderTotalDividends - shareholderTotalExcluded;
        }

        if ( shareholderTotalDividendsToken > shareholderTotalExcludedToken ) {
            amountTokens = shareholderTotalDividendsToken - shareholderTotalExcludedToken;
        }
    }
    
    function getCumulativeDividends(uint256 share) internal view returns (uint256) {
        return ( share * dividendsPerShare ) / PRECISION;
    }

    function getCumulativeRewardTokenDividends(uint256 share) internal view returns (uint256) {
        return ( share * dividendsPerShareToken ) / PRECISION;
    }

}