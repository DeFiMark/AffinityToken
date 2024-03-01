//SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import "./IERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./EnumerableSet.sol";

interface IFeeReceiver {
    function trigger() external;
}

interface IDistributor {
    function setShare(address holder, uint256 balance) external;
    function process() external;
}

/**
    Modular Upgradeable Token
 */
contract AffinityToken is IERC20, Ownable {

    using SafeMath for uint256;

    // total supply
    uint256 private _totalSupply = 860_000_000_000 * 10**18;

    // token data
    string private _name = 'Affinity';
    string private _symbol = 'AFNTY';
    uint8  private constant _decimals = 18;

    // balances
    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;

    // Taxation on transfers
    uint256 public buyFee             = 400;
    uint256 public sellFee            = 900;
    uint256 public transferFee        = 0;
    uint256 public constant TAX_DENOM = 10000;

    // Maximum Sell Limit
    uint256 public max_sell_limit = 800_000_000_000 * 10**18;
    uint256 public max_sell_limit_duration = 12 hours;

    // Max Sell Limit Info
    struct UserInfo {
        uint256 totalSold;
        uint256 hourStarted;
        uint256 timeJoined;
    }

    // Address => Max Sell Limit Info
    mapping ( address => UserInfo ) public userInfo;

    // permissions
    struct Permissions {
        bool isFeeExempt;
        bool isLiquidityPool;
        bool isSellLimitExempt;
        bool isBlacklisted;
    }
    mapping ( address => Permissions ) public permissions;

    // Fee Recipients
    address public sellFeeRecipient;
    address public buyFeeRecipient;
    address public transferFeeRecipient;

    // Trigger Fee Recipients
    bool public triggerBuyRecipient = false;
    bool public triggerTransferRecipient = false;
    bool public triggerSellRecipient = false;

    // List of all holders
    EnumerableSet.AddressSet public holders;

    // Whether or not the contract is paused
    bool public paused;

    // Sell Limit Enabled
    bool public sellLimitEnabled;

    // Distributor Address
    address public distributor;

    // events
    event SetBuyFeeRecipient(address recipient);
    event SetSellFeeRecipient(address recipient);
    event SetTransferFeeRecipient(address recipient);
    event SetFeeExemption(address account, bool isFeeExempt);
    event SetSellLimitExemption(address account, bool isFeeExempt);
    event SetAutomatedMarketMaker(address account, bool isMarketMaker);
    event SetFees(uint256 buyFee, uint256 sellFee, uint256 transferFee);
    event SetAutoTriggers(bool triggerBuy, bool triggerSell, bool triggerTransfer);
    event Blacklisted(address indexed account, bool isBlacklisted);

    constructor() {

        // Owner
        address _owner = 0xEe3C1B43482bf018ac960EeA8B57d8e576368D57;

        // exempt sender for tax-free initial distribution
        permissions[_owner].isFeeExempt = true;
        permissions[_owner].isSellLimitExempt = true;

        // initial supply allocation
        _balances[_owner] = _totalSupply;
        emit Transfer(address(0), _owner, _totalSupply);

        // Set Paused
        paused = true;

        // add holder
        _addHolder(_owner);
    }

    /////////////////////////////////
    /////    ERC20 FUNCTIONS    /////
    /////////////////////////////////

    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }
    
    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public pure override returns (uint8) {
        return _decimals;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /** Transfer Function */
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        return _transferFrom(msg.sender, recipient, amount);
    }

    /** Transfer Function */
    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        _allowances[sender][msg.sender] = _allowances[sender][msg.sender].sub(amount, 'Insufficient Allowance');
        return _transferFrom(sender, recipient, amount);
    }


    /////////////////////////////////
    /////   PUBLIC FUNCTIONS    /////
    /////////////////////////////////


    function burn(uint256 amount) external returns (bool) {
        return _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) external returns (bool) {
        _allowances[account][msg.sender] = _allowances[account][msg.sender].sub(amount, 'Insufficient Allowance');
        return _burn(account, amount);
    }

    receive() external payable {
        
    }

    /////////////////////////////////
    /////    OWNER FUNCTIONS    /////
    /////////////////////////////////

    function setNameAndSymbol(string memory name_, string memory symbol_) external onlyOwner {
        _name = name_;
        _symbol = symbol_;
    }

    function setDistributor(address _distributor) external onlyOwner {
        distributor = _distributor;
    }

    function setSelllimitEnabled(bool _enabled) external onlyOwner {
        sellLimitEnabled = _enabled;
    }

    function withdraw(address token) external onlyOwner {
        require(token != address(0), 'Zero Address');
        bool s = IERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this)));
        require(s, 'Failure On Token Withdraw');
    }

    function withdrawBNB() external onlyOwner {
        (bool s,) = payable(msg.sender).call{value: address(this).balance}("");
        require(s);
    }

    function setTransferFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), 'Zero Address');
        transferFeeRecipient = recipient;
        permissions[recipient].isFeeExempt = true;
        permissions[recipient].isSellLimitExempt = true;
        emit SetTransferFeeRecipient(recipient);
    }

    function setBuyFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), 'Zero Address');
        buyFeeRecipient = recipient;
        permissions[recipient].isFeeExempt = true;
        permissions[recipient].isSellLimitExempt = true;
        emit SetBuyFeeRecipient(recipient);
    }

    function setSellFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), 'Zero Address');
        sellFeeRecipient = recipient;
        permissions[recipient].isFeeExempt = true;
        permissions[recipient].isSellLimitExempt = true;
        emit SetSellFeeRecipient(recipient);
    }

    function registerAutomatedMarketMaker(address account) external onlyOwner {
        require(account != address(0), 'Zero Address');
        require(!permissions[account].isLiquidityPool, 'Already An AMM');
        permissions[account].isLiquidityPool = true;
        emit SetAutomatedMarketMaker(account, true);
    }

    function unRegisterAutomatedMarketMaker(address account) external onlyOwner {
        require(account != address(0), 'Zero Address');
        require(permissions[account].isLiquidityPool, 'Not An AMM');
        permissions[account].isLiquidityPool = false;
        emit SetAutomatedMarketMaker(account, false);
    }

    function blackListAddress(address account) external onlyOwner {
        require(account != address(0), 'Zero Address');
        permissions[account].isBlacklisted = true;
        emit Blacklisted(account, true);
    }

    function removeBlackListFromAddress(address account) external onlyOwner {
        require(account != address(0), 'Zero Address');
        permissions[account].isBlacklisted = false;
        emit Blacklisted(account, false);
    }

    function pause() external onlyOwner {
        paused = true;
    }

    function unPause() external onlyOwner {
        paused = false;
    }

    function setAutoTriggers(
        bool autoBuyTrigger,
        bool autoTransferTrigger,
        bool autoSellTrigger
    ) external onlyOwner {
        triggerBuyRecipient = autoBuyTrigger;
        triggerTransferRecipient = autoTransferTrigger;
        triggerSellRecipient = autoSellTrigger;
        emit SetAutoTriggers(autoBuyTrigger, autoSellTrigger, autoTransferTrigger);
    }

    function setFees(uint _buyFee, uint _sellFee, uint _transferFee) external onlyOwner {
        require(
            _buyFee <= 2000,
            'Buy Fee Too High'
        );
        require(
            _sellFee <= 2000,
            'Sell Fee Too High'
        );
        require(
            _transferFee <= 2000,
            'Transfer Fee Too High'
        );

        buyFee = _buyFee;
        sellFee = _sellFee;
        transferFee = _transferFee;

        emit SetFees(_buyFee, _sellFee, _transferFee);
    }

    function setFeeExempt(address account, bool isExempt) external onlyOwner {
        require(account != address(0), 'Zero Address');
        permissions[account].isFeeExempt = isExempt;
        emit SetFeeExemption(account, isExempt);
    }

    function setMaxSellLimitExempt(address account, bool isExempt) external onlyOwner {
        require(account != address(0), 'Zero Address');
        permissions[account].isSellLimitExempt = isExempt;
        emit SetSellLimitExemption(account, isExempt);
    }

    function setMaxSellLimit(uint256 newLimit) external onlyOwner {
        require(
            newLimit >= _totalSupply / 10_000,
            'Max Sell Limit Too Low'
        );
        max_sell_limit = newLimit;
    }

    function setMaxSellLimitDuration(uint256 newDuration) external onlyOwner {
        require(
            newDuration >= 10 minutes,
            'Max Sell Limit Duration Too Low'
        );
        max_sell_limit_duration = newDuration;
    }

    
    /////////////////////////////////
    /////     READ FUNCTIONS    /////
    /////////////////////////////////

    function getTax(address sender, address recipient, uint256 amount) public view returns (uint256, address, bool) {
        if ( permissions[sender].isFeeExempt || permissions[recipient].isFeeExempt ) {
            return (0, address(0), false);
        }
        return permissions[sender].isLiquidityPool ? 
               (amount.mul(buyFee).div(TAX_DENOM), buyFeeRecipient, triggerBuyRecipient) : 
               permissions[recipient].isLiquidityPool ? 
               (amount.mul(sellFee).div(TAX_DENOM), sellFeeRecipient, triggerSellRecipient) :
               (amount.mul(transferFee).div(TAX_DENOM), transferFeeRecipient, triggerTransferRecipient);
    }

    function timeSinceLastSale(address user) public view returns (uint256) {
        uint256 last = userInfo[user].hourStarted;

        return last > block.timestamp ? 0 : block.timestamp - last;
    }

    function amountSoldInLastHour(address user) public view returns (uint256) {
        
        uint256 timeSince = timeSinceLastSale(user);

        if (timeSince >= max_sell_limit_duration) {
            return 0;
        } else {
            return userInfo[user].totalSold;
        }
    }

    function timeSinceJoined(address user) public view returns (uint256) {
        uint256 timeJoined = userInfo[user].timeJoined;
        if (timeJoined == 0) {
            return 0;
        }
        return block.timestamp > timeJoined ? block.timestamp - timeJoined : 0;
    }

    function getNumberOfHolders() external view returns (uint256) {
        return EnumerableSet.length(holders);
    }

    function viewAllHolders() external view returns (address[] memory) {
        return EnumerableSet.values(holders);
    }

    function getHolderAtIndex(uint256 index) external view returns (address) {
        if (index >= EnumerableSet.length(holders)) {
            index = 0;
        }
        if (index >= EnumerableSet.length(holders)) {
            return address(0);
        }
        return EnumerableSet.at(holders, index);
    }

    function viewHolderSlice(uint startIndex, uint endIndex) external view returns (address[] memory) {
        if (endIndex > EnumerableSet.length(holders)) {
            endIndex = EnumerableSet.length(holders);
        }
        if (startIndex > endIndex) {
            startIndex = endIndex;
        }
        address[] memory holderList = new address[](endIndex - startIndex);
        uint count = 0;
        for (uint i = startIndex; i < endIndex;) {
            holderList[count] = EnumerableSet.at(holders, i);
            unchecked { ++i; ++count; }
        }
        return holderList;
    }

    function viewAllHoldersAndTimeSince() external view returns (address[] memory, uint256[] memory timeSince, uint256[] memory balances) {
        uint256 len = EnumerableSet.length(holders);
        timeSince = new uint256[](len);
        balances = new uint256[](len);
        for (uint i = 0; i < len;) {
            address _holder = EnumerableSet.at(holders, i);
            timeSince[i] = timeSinceJoined(_holder);
            balances[i] = _balances[_holder];
            unchecked { ++i; }
        }
        return (EnumerableSet.values(holders), timeSince, balances);
    }

    function viewAllHoldersAndTimeSinceSlice(uint startIndex, uint endIndex) external view returns (address[] memory, uint256[] memory timeSince, uint256[] memory balances) {
        
        if (endIndex > holdersList.length) {
            endIndex = holdersList.length;
        }
        if (startIndex > endIndex) {
            startIndex = endIndex;
        }
        address[] memory holderList = new address[](endIndex - startIndex);
        timeSince = new uint256[](endIndex - startIndex);
        balances = new uint256[](endIndex - startIndex);
        uint count = 0;
        for (uint i = startIndex; i < endIndex;) {
            address _holder = EnumerableSet.at(holders, i);
            holderList[count] = _holder;
            timeSince[count] = timeSinceJoined(_holder);
            balances[count] = _balances[_holder];
            unchecked { ++i; ++count; }
        }
        return (holders, timeSince, balances);
    }

    //////////////////////////////////
    /////   INTERNAL FUNCTIONS   /////
    //////////////////////////////////

    /** Internal Transfer */
    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
        require(
            recipient != address(0),
            'Zero Recipient'
        );
        require(
            amount > 0,
            'Zero Amount'
        );
        require(
            amount <= balanceOf(sender),
            'Insufficient Balance'
        );
        require(
            paused == false || msg.sender == this.getOwner(),
            'Paused'
        );
        require(
            permissions[sender].isBlacklisted == false && permissions[recipient].isBlacklisted == false,
            'Blacklisted'
        );
        
        // decrement sender balance
        _balances[sender] -= amount;

        // fee for transaction
        (uint256 fee, address feeDestination, bool trigger) = getTax(sender, recipient, amount);

        // give amount to recipient less fee
        uint256 sendAmount = amount - fee;
        require(sendAmount > 0, 'Zero Amount');

        // add / remove holders if applicable
        if (_balances[recipient] == 0) {
            _addHolder(recipient);
        }

        if (_balances[sender] == 0) {
            _removeHolder(sender);
        }

        // allocate balance
        _balances[recipient] += sendAmount;
        emit Transfer(sender, recipient, sendAmount);

        // allocate fee if any
        if (fee > 0) {

            // if recipient field is valid
            bool isValidRecipient = feeDestination != address(0) && feeDestination != address(this);

            // allocate amount to recipient
            address feeRecipient = isValidRecipient ? feeDestination : address(this);

            // add fee receiver to list if new holder
            if (_balances[feeRecipient] == 0) {
                _addHolder(feeRecipient);
            }

            // allocate fee
            _balances[feeRecipient] += fee;
            emit Transfer(sender, feeRecipient, fee);

            // if valid and trigger is enabled, trigger tokenomics mid transfer
            if (trigger && isValidRecipient) {
                IFeeReceiver(feeRecipient).trigger();
            }
        }

        // apply max sell limit if applicable
        if (permissions[recipient].isLiquidityPool && !permissions[sender].isSellLimitExempt && sellLimitEnabled) {

            if (timeSinceLastSale(sender) >= max_sell_limit_duration) {

                // its been over the time duration, set total sold and reset timer
                userInfo[sender].totalSold = amount;
                userInfo[sender].hourStarted = block.timestamp;

            } else {
                
                // time limit has not been surpassed, increment total sold
                unchecked {
                    userInfo[sender].totalSold += amount;
                }

            }

            // ensure max limit is preserved
            require(
                userInfo[sender].totalSold <= max_sell_limit,
                'Sell Exceeds Max Sell Limit'
            );

        }

        if (distributor != address(0)) {
            IDistributor(distributor).setShare(sender, _balances[sender]);
            IDistributor(distributor).setShare(recipient, _balances[recipient]);
            IDistributor(distributor).process();
        }

        return true;
    }

    function _burn(address account, uint256 amount) internal returns (bool) {
        require(
            account != address(0),
            'Zero Address'
        );
        require(
            amount > 0,
            'Zero Amount'
        );
        require(
            amount <= balanceOf(account),
            'Insufficient Balance'
        );

        // delete from balance and supply
        _balances[account] = _balances[account].sub(amount, 'Balance Underflow');
        _totalSupply = _totalSupply.sub(amount, 'Supply Underflow');

        // remove account
        if (_balances[account] == 0) {
            _removeHolder(account);
        }

        // emit transfer
        emit Transfer(account, address(0), amount);
        return true;
    }

    function _removeHolder(address holder) internal {
        if (EnumerableSet.contains(holders, holder)) {
            EnumerableSet.remove(holders, holder);
        }
        delete userInfo[holder].timeJoined;
    }

    function _addHolder(address holder) internal {
        if (!EnumerableSet.contains(holders, holder)) {
            EnumerableSet.add(holders, holder);
        }
        userInfo[holder].timeJoined = block.timestamp;
    }

}