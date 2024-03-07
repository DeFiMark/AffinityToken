//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./IERC20.sol";
import "./IUniswapV2Router02.sol";

interface IToken is IERC20 {
    function getOwner() external view returns (address);
}

contract TaxReceiver {

    // Main Token
    IToken public immutable token;

    // Router
    IUniswapV2Router02 public router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    // marketing cuts
    uint256 public marketingPercent = 150;
    address public marketingWallet;

    // Percentage toward reward pools
    address public rewardWallet;

    modifier onlyOwner() {
        require(
            msg.sender == token.getOwner(),
            'Only Owner'
        );
        _;
    }

    constructor(address token_) {
        token = IToken(token_);
    }

    function trigger() external {

        // ensure there is balance to distribute
        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) {
            return;
        }

        // create swap path
        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = router.WETH();

        // approve and sell
        IERC20(token).approve(address(router), balance);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(balance, 1, path, address(this), block.timestamp + 1000);

        // split ETH balance between marketing and staking
        uint256 marketing = ( address(this).balance * marketingPercent ) / 1_000;
        uint256 rewards = address(this).balance - marketing;

        // send ETH to marketing
        (bool m,) = payable(marketingWallet).call{value: marketing}("");
        require(m);

        // send ETH to staking
        (bool s,) = payable(rewardWallet).call{value: rewards}("");
        require(s);

        // clear memory
        delete path;
    }

    function setMarketingPercent(uint256 percent_) external onlyOwner {
        marketingPercent = percent_;
    }

    function setMarketingWallet(address addr_) external onlyOwner {
        marketingWallet = addr_;
    }

    function setRewardWallet(address addr_) external onlyOwner {
        rewardWallet = addr_;
    }

    function setRouter(address router_) external onlyOwner {
        router = IUniswapV2Router02(router_);
    }

    function withdraw() external onlyOwner {
        (bool s,) = payable(msg.sender).call{value: address(this).balance}("");
        require(s);
    }

    function withdrawToken(IERC20 token_) external onlyOwner {
        token_.transfer(msg.sender, token_.balanceOf(address(this)));
    }

    receive() external payable {}

}