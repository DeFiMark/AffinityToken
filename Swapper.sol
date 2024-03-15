//SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import "./Ownable.sol";
import "./IUniswapV2Router02.sol";
import "./IERC20.sol";
import "./TransferHelper.sol";

contract AffinitySwapper is Ownable {

    struct TokenPartner {
        uint256 fee;
        address router;
        address[] sellPath;
        address[] buyPath;
    }

    mapping ( address => TokenPartner ) public tokens;

    uint256 public defaultFee = 75;
    uint256 private constant FEE_DENOM = 10_000;

    address public feeRecipient;

    constructor(
        uint256 fee_,
        address feeRecipient_
    ) {
        defaultFee = fee_;
        feeRecipient = feeRecipient_;
    }

    function listToken(
        address token,
        uint256 fee_,
        address router_,
        address[] memory sellPath_,
        address[] memory buyPath_
    ) external onlyOwner {
        tokens[token].fee = fee_;
        tokens[token].router = router_;
        tokens[token].sellPath = swapPath_;
        tokens[token].buyPath = buyPath_;
    }

    function getFee(address token) public view returns (uint256) {
        return tokens[token].fee == 0 ? defaultFee : tokens[token].fee;
    }

    function setDefaultFee(uint256 fee_) external onlyOwner {
        require(fee_ < FEE_DENOM, "AffinitySwapper: fee must be less than 100%");
        defaultFee = fee_;
    }

    function setFeeForToken(address token, uint256 fee_) external onlyOwner {
        require(fee_ < FEE_DENOM, "AffinitySwapper: fee must be less than 100%");
        tokens[token] = fee_;
    }

    function setFeeRecipient(address feeRecipient_) external onlyOwner {
        feeRecipient = feeRecipient_;
    }

    function setRouter(address router_) external onlyOwner {
        router = IUniswapV2Router02(router_);
    }

    function buy(address token, uint256 minOut) external payable { 
        _buy(token, minOut);
    }

    receive() external payable {}

    function _buy(address token, uint256 minOut) internal {

        // split up value
        uint256 bnbFee = ( msg.value * getFee(token) ) / FEE_DENOM;
        uint256 swapAmount = msg.value - bnbFee;

        // send fee to fee recipient
        TransferHelper.safeTransferETH(feeRecipient, bnbFee);

        // instantiate router
        IUniswapV2Router02 router = IUniswapV2Router02(tokens[token].router);

        // swap into affinity, sending to address(this)
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: swapAmount}(
            minOut,
            tokens[token].buyPath,
            address(this),
            block.timestamp + 300
        );

        // transfer token to sender
        TransferHelper.safeTransfer(token, msg.sender, IERC20(token).balanceOf(address(this)));
    }

    function sell(address token, uint256 amount, uint256 minOut) external {
        require(
            IERC20(token).balanceOf(msg.sender) >= amount,
            "AffinitySwapper: Insufficient Balance"
        );
        require(
            IERC20(token).allowance(msg.sender, address(this)) >= amount,
            "AffinitySwapper: Insufficient Allowance"
        );

        uint256 amountBefore = IERC20(token).balanceOf(address(this));
        TransferHelper.safeTransferFrom(token, msg.sender, address(this), amount);
        uint256 amountAfter = IERC20(token).balanceOf(address(this));
        require(
            amountAfter > amountBefore,
            "AffinitySwapper: Zero Received"
        );
        uint256 amountToSwap = amountAfter - amountBefore;

        IUniswapV2Router02 router = IUniswapV2Router02(tokens[token].router);

        IERC20(token).approve(address(router), amountToSwap);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            minOut,
            tokens[token].sellPath,
            address(this),
            block.timestamp + 300
        );

        // take fee in bnb
        uint256 feeAmount = ( address(this).balance * getFee(token) ) / FEE_DENOM;
        TransferHelper.safeTransferETH(feeRecipient, feeAmount);

        // send remaining bnb to user
        TransferHelper.safeTransferETH(msg.sender, address(this).balance);
    }

}