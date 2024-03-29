//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./IUniswapV2Router02.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeMath.sol";

interface IPair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
}

interface IWETH {
    function withdraw(uint256 amount) external;
}

contract AffinitySwapper is Ownable {

    using SafeMath for uint256;

    // Fee Taken On Swaps
    uint256 public fee                     = 75;
    uint256 public affinityBuyFee          = 200;
    uint256 public affinitySellFee         = 700;
    uint256 public defaultReferralFee      = 25;
    uint256 public constant FeeDenominator = 10000;

    // Fee Recipient
    address public feeReceiver = 0x66cF1ef841908873C34e6bbF1586F4000b9fBB5D;

    // WETH
    address public constant WETH = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    // Affinity Token
    address public constant affinity = 0xF59918B07278ff20109f8c37d7255e0677B45c43;

    // Affiliate
    struct Affiliate {
        bool isApproved;
        uint fee;
    }
    mapping ( address => Affiliate ) public affiliates;

    function registerAffiliate(address recipient, uint fee_) external onlyOwner {
        require(fee_ < 100, 'Fee Too High');
        affiliates[recipient].isApproved = true;
        affiliates[recipient].fee = fee_;
    }

    function removeAffiliate(address affiliate) external onlyOwner {
        delete affiliates[affiliate];
    }

    function setFee(uint256 newFee) external onlyOwner {
        require(
            newFee <= FeeDenominator / 10,
            'Fee Too High'
        );
        fee = newFee;
    }

    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        require(
            newFeeRecipient != address(0),
            'Zero Address'
        );
        feeReceiver = newFeeRecipient;
    }

    function setDefaultReferralFee(uint256 newFee) external onlyOwner {
        require(
            newFee < 100,
            'Fee Too High'
        );
        defaultReferralFee = newFee;
    }

    function setAffinityBuyFee(uint256 newFee) external onlyOwner {
        require(
            newFee < FeeDenominator / 10,
            'Fee Too High'
        );
        affinityBuyFee = newFee;
    }

    function setAffinitySellFee(uint256 newFee) external onlyOwner {
        require(
            newFee < FeeDenominator / 10,
            'Fee Too High'
        );
        affinitySellFee = newFee;
    }

    function registerSelfAffiliate() external {
        require(
            affiliates[address(0)].isApproved,
            'Not Approved'
        );
        affiliates[msg.sender].isApproved = true;
        affiliates[msg.sender].fee = defaultReferralFee;
    }

    function swapETHForToken(address DEX, address token, uint256 amountOutMin, address recipient, address ref) external payable {
        require(
            msg.value > 0,
            'Zero Value'
        );

        if (token == affinity) {
            uint256 _totalFee = ( msg.value * ( affinityBuyFee + fee ) ) / FeeDenominator;
            _sendETH(feeReceiver, _totalFee);

            // define swap path
            address[] memory path = new address[](2);
            path[0] = WETH;
            path[1] = affinity;

            // make the swap
            IUniswapV2Router02(DEX).swapExactETHForTokensSupportingFeeOnTransferTokens{value: msg.value - _totalFee}(amountOutMin, path, address(this), block.timestamp + 300);

            // save memory
            delete path;

            // send affinity to recipient
            IERC20(affinity).transfer(recipient, IERC20(affinity).balanceOf(address(this)));
        } else {

            uint _totalFee = getFee(msg.value);
            uint _fee = _totalFee;
            if (ref != feeReceiver && ref != address(0)) {
                if (affiliates[ref].isApproved) {
                    uint hFee = ( _totalFee * affiliates[ref].fee ) / 100;
                    _fee = _totalFee - hFee;
                    if (hFee > 0) {
                        _sendETH(ref, hFee);
                    }
                }
            }
            _sendETH(feeReceiver, _fee);

            // define swap path
            address[] memory path = new address[](2);
            path[0] = WETH;
            path[1] = token;

            // make the swap
            IUniswapV2Router02(DEX).swapExactETHForTokensSupportingFeeOnTransferTokens{value: msg.value - _totalFee}(amountOutMin, path, recipient, block.timestamp + 300);

            // save memory
            delete path;
            
        }
    }

    function swapTokenForETH(address DEX, address token, uint256 amount, uint256 amountOutMin, address recipient, address ref) external {
        require(
            amount > 0,
            'Zero Value'
        );

        if (token == affinity) {
            uint256 received = _transferIn(msg.sender, address(this), token, amount);
            IERC20(affinity).approve(DEX, received);
            address[] memory sellPath = new address[](2);
            sellPath[0] = affinity;
            sellPath[1] = WETH;
            IUniswapV2Router02(DEX).swapExactTokensForETHSupportingFeeOnTransferTokens(received, amountOutMin, sellPath, address(this), block.timestamp + 300);
            uint256 _totalFee = ( address(this).balance * ( affinitySellFee + fee ) ) / FeeDenominator;
            _sendETH(feeReceiver, _totalFee);
            _sendETH(recipient, address(this).balance);
            return;
        }

        address _ref = ref;

        // liquidity pool
        IPair pair = IPair(IUniswapV2Factory(IUniswapV2Router02(DEX).factory()).getPair(token, WETH));
        _transferIn(msg.sender, address(pair), token, amount);

        // handle swap logic
        (address input, address output) = (token, WETH);
        (address token0,) = sortTokens(input, output);
        uint amountInput;
        uint amountOutput;
        { // scope to avoid stack too deep errors
        (uint reserve0, uint reserve1,) = pair.getReserves();
        (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
        amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
        amountOutput = getAmountOut(amountInput, reserveInput, reserveOutput);
        }
        
        (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));

        // make the swap
        pair.swap(amount0Out, amount1Out, address(this), new bytes(0));

        // check output amount
        uint amountOut = IERC20(WETH).balanceOf(address(this));
        require(amountOut >= amountOutMin, 'INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).withdraw(amountOut);
        
        // take fee in bnb and send rest to sender
        uint _totalFee = getFee(amountOut);
        uint _fee = _totalFee;
        if (ref != feeReceiver && ref != address(0)) {
            if (affiliates[ref].isApproved) {
                uint hFee = ( _totalFee * affiliates[_ref].fee ) / 100;
                _fee = _totalFee - hFee;
                if (hFee > 0) {
                    _sendETH(_ref, hFee);
                }
            }
        }
        _sendETH(feeReceiver, _fee);
        _sendETH(recipient, amountOut - _totalFee);
    }

    function swapTokenForToken(address DEX, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin, address recipient, address ref) external {
        require(
            amountIn > 0,
            'Zero Value'
        );
        address tokenOut_ = tokenOut;
        address recipient_ = recipient;

        // fetch fee and transfer in to receiver
        uint _totalFee = getFee(amountIn);
        uint _fee = _totalFee;
        if (ref != feeReceiver && ref != address(0)) {
            if (affiliates[ref].isApproved) {
                uint hFee = _totalFee * affiliates[ref].fee / 100;
                if (hFee > 0) {
                    _transferIn(msg.sender, ref, tokenIn, hFee);
                }
                _fee = _fee - hFee;
            }
        }
        _transferIn(msg.sender, feeReceiver, tokenIn, _fee);

        // transfer rest into liquidity pool
        IPair pair = IPair(IUniswapV2Factory(IUniswapV2Router02(DEX).factory()).getPair(tokenIn, tokenOut_));
        _transferIn(msg.sender, address(pair), tokenIn, amountIn - _totalFee);

        // handle swap logic
        (address input, address output) = (tokenIn, tokenOut_);
        (address token0,) = sortTokens(input, output);
        uint amountInput;
        uint amountOutput;
        { // scope to avoid stack too deep errors
        (uint reserve0, uint reserve1,) = pair.getReserves();
        (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
        amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
        amountOutput = getAmountOut(amountInput, reserveInput, reserveOutput);
        }
        {
        (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));

        uint before = IERC20(tokenOut_).balanceOf(recipient_);
        pair.swap(amount0Out, amount1Out, recipient_, new bytes(0));
        
        // check output amount
        require(IERC20(tokenOut_).balanceOf(recipient_).sub(before) >= amountOutMin, 'INSUFFICIENT_OUTPUT_AMOUNT');
        }
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'PancakeLibrary: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'PancakeLibrary: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(9970);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(10000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'PancakeLibrary: ZERO_ADDRESS');
    }

    function getFee(uint256 amount) public view returns (uint256) {
        return( amount * fee ) / FeeDenominator;
    }

    function _sendETH(address receiver, uint amount) internal {
        (bool s,) = payable(receiver).call{value: amount}("");
        require(s, 'Failure On ETH Transfer');
    }

    function _transferIn(address fromUser, address toUser, address token, uint256 amount) internal returns (uint256) {
        uint before = IERC20(token).balanceOf(toUser);
        IERC20(token).transferFrom(fromUser, toUser, amount);
        uint After = IERC20(token).balanceOf(toUser) - before;
        require(
            After > before,
            'Error On Transfer From'
        );
        return After - before;
    }

    receive() external payable {}
}