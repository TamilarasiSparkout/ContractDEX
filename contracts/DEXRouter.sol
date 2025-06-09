// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./DEXFactory.sol";
import "./DEXPair.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint wad) external;
    function transfer(address to, uint value) external returns (bool);
}

contract DEXRouter {
    using SafeERC20 for IERC20;

    address public immutable factory;
    address public immutable WETH;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, "DEXRouter: EXPIRED");
        _;
    }

    constructor(address _factory, address _WETH) {
        factory = _factory;
        WETH = _WETH;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    event LiquidityAdded(address indexed provider, address indexed tokenA, address indexed tokenB, uint amountA, uint amountB, uint liquidity);
    event LiquidityRemoved(address indexed provider, address indexed tokenA, address indexed tokenB, uint amountA, uint amountB);
    event LiquidityIncreased(address indexed provider, address indexed tokenA, address indexed tokenB, uint amountA, uint amountB, uint liquidity);
    event Swap(address indexed sender, address indexed tokenIn, address indexed tokenOut, uint amountIn, uint amountOut, address to);

    // ************ Utility functions ************

    function quote(uint amountA, uint reserveA, uint reserveB) public pure returns (uint amountB) {
        require(amountA > 0, "DEXRouter: INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "DEXRouter: INSUFFICIENT_LIQUIDITY");
        amountB = amountA * reserveB / reserveA;
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) public pure returns (uint amountOut) {
        require(amountIn > 0, "DEXRouter: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "DEXRouter: INSUFFICIENT_LIQUIDITY");
        uint amountInWithFee = amountIn * 997;
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) public pure returns (uint amountIn) {
        require(amountOut > 0, "DEXRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "DEXRouter: INSUFFICIENT_LIQUIDITY");
        uint numerator = reserveIn * amountOut * 1000;
        uint denominator = (reserveOut - amountOut) * 997;
        amountIn = numerator / denominator + 1;
    }

    function getReserves(address tokenA, address tokenB) public view returns (uint reserveA, uint reserveB) {
        address pair = DEXFactory(factory).getPair(tokenA, tokenB);
        require(pair != address(0), "DEXRouter: PAIR_NOT_FOUND");
        (uint reserve0, uint reserve1) = DEXPair(pair).getReserves();
        (reserveA, reserveB) = tokenA < tokenB ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // Internal helper to create pair if it doesn't exist
    function _getPair(address tokenA, address tokenB) internal returns (address pair) {
        pair = DEXFactory(factory).getPair(tokenA, tokenB);
        if (pair == address(0)) {
            pair = DEXFactory(factory).createPair(tokenA, tokenB);
        }
    }

    // Add liquidity for token-token pair
    function addLiquidity(
    address tokenA,
    address tokenB,
    uint amountADesired,
    uint amountBDesired,
    uint amountAMin,
    uint amountBMin,
    uint deadline
    ) external ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
    address pair = _getPair(tokenA, tokenB);
    (uint reserveA, uint reserveB) = getReserves(tokenA, tokenB);

    if (reserveA == 0 && reserveB == 0) {
        (amountA, amountB) = (amountADesired, amountBDesired);
    } else {
        uint amountBOptimal = quote(amountADesired, reserveA, reserveB);
        if (amountBOptimal <= amountBDesired) {
            require(amountBOptimal >= amountBMin, "DEXRouter: INSUFFICIENT_B_AMOUNT");
            (amountA, amountB) = (amountADesired, amountBOptimal);
        } else {
            uint amountAOptimal = quote(amountBDesired, reserveB, reserveA);
            require(amountAOptimal >= amountAMin, "DEXRouter: INSUFFICIENT_A_AMOUNT");
            (amountA, amountB) = (amountAOptimal, amountBDesired);
        }
    }

    IERC20(tokenA).safeTransferFrom(msg.sender, pair, amountA);
    IERC20(tokenB).safeTransferFrom(msg.sender, pair, amountB);
    liquidity = DEXPair(pair).mint(msg.sender);
    emit LiquidityAdded(msg.sender, tokenA, tokenB, amountA, amountB, liquidity);
    }

    // Add liquidity for token-ETH pair
    function addLiquidityETH(
    address token,
    uint amountTokenDesired,
    uint amountTokenMin,
    uint amountETHMin,
    uint deadline
    ) external payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
    address pair = _getPair(token, WETH);
    (uint reserveToken, uint reserveETH) = getReserves(token, WETH);

    if (reserveToken == 0 && reserveETH == 0) {
        (amountToken, amountETH) = (amountTokenDesired, msg.value);
    } else {
        uint amountETHOptimal = quote(amountTokenDesired, reserveToken, reserveETH);
        if (amountETHOptimal <= msg.value) {
            require(amountETHOptimal >= amountETHMin, "DEXRouter: INSUFFICIENT_ETH_AMOUNT");
            (amountToken, amountETH) = (amountTokenDesired, amountETHOptimal);
        } else {
            uint amountTokenOptimal = quote(msg.value, reserveETH, reserveToken);
            require(amountTokenOptimal >= amountTokenMin, "DEXRouter: INSUFFICIENT_TOKEN_AMOUNT");
            (amountToken, amountETH) = (amountTokenOptimal, msg.value);
        }
    }

    IERC20(token).safeTransferFrom(msg.sender, pair, amountToken);
    IWETH(WETH).deposit{value: amountETH}();
    assert(IWETH(WETH).transfer(pair, amountETH));

    liquidity = DEXPair(pair).mint(msg.sender);

    // refund dust ETH
    if (msg.value > amountETH) {
        payable(msg.sender).transfer(msg.value - amountETH);
    }

    emit LiquidityAdded(msg.sender, token, WETH, amountToken, amountETH, liquidity);
    }

    // Swap exact tokens for tokens
    function swapExactTokensForTokens(
    address tokenIn,
    address tokenOut,
    uint amountIn,
    uint amountOutMin,
    address to,
    uint deadline
    ) external {
    require(block.timestamp <= deadline, "DEXRouter: EXPIRED");

    address pair = _getPair(tokenIn, tokenOut);
    (uint reserveIn, uint reserveOut) = getReserves(tokenIn, tokenOut);
    uint amountOut = getAmountOut(amountIn, reserveIn, reserveOut);

    require(amountOut >= amountOutMin, "DEXRouter: INSUFFICIENT_OUTPUT");

    IERC20(tokenIn).safeTransferFrom(msg.sender, pair, amountIn);
    DEXPair(pair).swap(tokenIn, amountIn, to);

    emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut, to);
    }

    // Swap tokens for exact tokens (tokenIn -> tokenOut)
    function swapTokensForExactTokens(
    address tokenIn,
    address tokenOut,
    uint amountOut,
    uint amountInMax,
    address to,
    uint deadline
    ) external {
    require(block.timestamp <= deadline, "DEXRouter: EXPIRED");

    (uint reserveIn, uint reserveOut) = getReserves(tokenIn, tokenOut);
    uint amountIn = getAmountIn(amountOut, reserveIn, reserveOut);

    require(amountIn <= amountInMax, "DEXRouter: EXCESSIVE_INPUT");

    address pair = _getPair(tokenIn, tokenOut);
    IERC20(tokenIn).safeTransferFrom(msg.sender, pair, amountIn);
    DEXPair(pair).swap(tokenIn, amountIn, to);
    }
    
    // Swap exact ETH for tokens
    function swapExactETHForTokens(
    address tokenOut,
    uint amountOutMin,
    address to,
    uint deadline
    ) external payable {
    require(block.timestamp <= deadline, "DEXRouter: EXPIRED");
    require(msg.value > 0, "DEXRouter: INSUFFICIENT_ETH");

    address pair = _getPair(WETH, tokenOut);
    (uint reserveIn, uint reserveOut) = getReserves(WETH, tokenOut);
    uint amountOut = getAmountOut(msg.value, reserveIn, reserveOut);

    require(amountOut >= amountOutMin, "DEXRouter: INSUFFICIENT_OUTPUT");

    IWETH(WETH).deposit{value: msg.value}();
    assert(IWETH(WETH).transfer(pair, msg.value));

    DEXPair(pair).swap(WETH, msg.value, to);
    }

    // Swap tokens for exact ETH
    function swapTokensForExactETH(
    address tokenIn,
    uint amountOut,
    uint amountInMax,
    address to,
    uint deadline
    ) external {
    require(block.timestamp <= deadline, "DEXRouter: EXPIRED");

    (uint reserveIn, uint reserveOut) = getReserves(tokenIn, WETH);
    uint amountIn = getAmountIn(amountOut, reserveIn, reserveOut);
    require(amountIn <= amountInMax, "DEXRouter: EXCESSIVE_INPUT");

    address pair = _getPair(tokenIn, WETH);
    IERC20(tokenIn).safeTransferFrom(msg.sender, pair, amountIn);
    DEXPair(pair).swap(tokenIn, amountIn, address(this));

    IWETH(WETH).withdraw(amountOut);
    payable(to).transfer(amountOut);
    }

    // Swap exact tokens for ETH
    function swapExactTokensForETH(
    address tokenIn,
    uint amountIn,
    uint amountOutMin,
    address to,
    uint deadline
    ) external {
    require(block.timestamp <= deadline, "DEXRouter: EXPIRED");

    address pair = _getPair(tokenIn, WETH);
    (uint reserveIn, uint reserveOut) = getReserves(tokenIn, WETH);
    uint amountOut = getAmountOut(amountIn, reserveIn, reserveOut);
    require(amountOut >= amountOutMin, "DEXRouter: INSUFFICIENT_OUTPUT");

    IERC20(tokenIn).safeTransferFrom(msg.sender, pair, amountIn);
    DEXPair(pair).swap(tokenIn, amountIn, address(this));

    IWETH(WETH).withdraw(amountOut);
    payable(to).transfer(amountOut);
    }

    // Swap ETH for exact tokens (ETH -> tokenOut)
    function swapETHForExactTokens(
    address tokenOut,
    uint amountOut,
    address to,
    uint deadline
    ) external payable {
    require(block.timestamp <= deadline, "DEXRouter: EXPIRED");

    (uint reserveIn, uint reserveOut) = getReserves(WETH, tokenOut);
    uint amountIn = getAmountIn(amountOut, reserveIn, reserveOut);
    require(msg.value >= amountIn, "DEXRouter: INSUFFICIENT_ETH");

    address pair = _getPair(WETH, tokenOut);
    IWETH(WETH).deposit{value: amountIn}();
    assert(IWETH(WETH).transfer(pair, amountIn));

    DEXPair(pair).swap(WETH, amountIn, to);

    if (msg.value > amountIn) {
        payable(msg.sender).transfer(msg.value - amountIn);
    }
    }

    // ************ Liquidity Removal ************

    // Remove liquidity token-token
    function removeLiquidity(
    address tokenA,
    address tokenB,
    uint liquidity,
    uint amountAMin,
    uint amountBMin,
    address to,
    uint deadline
    ) external {
    require(block.timestamp <= deadline, "DEXRouter: EXPIRED");

    address pair = _getPair(tokenA, tokenB);
    IERC20(pair).safeTransferFrom(msg.sender, pair, liquidity);

    (uint amount0, uint amount1) = DEXPair(pair).burn(to);

    // Use pair's token0/token1 order to match amounts to tokenA/tokenB
    address token0 = DEXPair(pair).token0();
    (uint amountA, uint amountB) = tokenA == token0 
        ? (amount0, amount1)
        : (amount1, amount0);

    require(amountA >= amountAMin, "DEXRouter: INSUFFICIENT_A_AMOUNT");
    require(amountB >= amountBMin, "DEXRouter: INSUFFICIENT_B_AMOUNT");

    emit LiquidityRemoved(msg.sender, tokenA, tokenB, amountA, amountB);
    }

    // Remove liquidity token-ETH
    function removeLiquidityETH(
    address token,
    uint liquidity,
    uint amountTokenMin,
    uint amountETHMin,
    address to,
    uint deadline
    ) external {
    require(block.timestamp <= deadline, "DEXRouter: EXPIRED");

    address pair = _getPair(token, WETH);
    IERC20(pair).safeTransferFrom(msg.sender, pair, liquidity);

    (uint amount0, uint amount1) = DEXPair(pair).burn(address(this));

    address token0 = DEXPair(pair).token0();
    (uint amountToken, uint amountETH) = token == token0
        ? (amount0, amount1)
        : (amount1, amount0);

    require(amountToken >= amountTokenMin, "DEXRouter: INSUFFICIENT_TOKEN");
    require(amountETH >= amountETHMin, "DEXRouter: INSUFFICIENT_ETH");

    IERC20(token).safeTransfer(to, amountToken);
    IWETH(WETH).withdraw(amountETH);
    payable(to).transfer(amountETH);
    }

    // ************ Increase Liquidity ************

    function increaseLiquidity(
    address tokenA,
    address tokenB,
    uint amountADesired,
    uint amountBDesired,
    uint amountAMin,
    uint amountBMin,
    address to,
    uint deadline
    ) external returns (uint liquidity, uint amountA, uint amountB) {
    require(block.timestamp <= deadline, "DEXRouter: EXPIRED");

    (uint reserveA, uint reserveB) = getReserves(tokenA, tokenB);

    if (reserveA == 0 && reserveB == 0) {
        // First liquidity, accept desired amounts
        amountA = amountADesired;
        amountB = amountBDesired;
    } else {
        uint amountBOptimal = quote(amountADesired, reserveA, reserveB);
        if (amountBOptimal <= amountBDesired) {
            require(amountBOptimal >= amountBMin, "DEXRouter: INSUFFICIENT_B_AMOUNT");
            amountA = amountADesired;
            amountB = amountBOptimal;
        } else {
            uint amountAOptimal = quote(amountBDesired, reserveB, reserveA);
            require(amountAOptimal <= amountADesired, "DEXRouter: INSUFFICIENT_A_AMOUNT");
            require(amountAOptimal >= amountAMin, "DEXRouter: INSUFFICIENT_A_AMOUNT");
            amountA = amountAOptimal;
            amountB = amountBDesired;
        }
    }
    address pair = _getPair(tokenA, tokenB);
    IERC20(tokenA).safeTransferFrom(msg.sender, pair, amountA);
    IERC20(tokenB).safeTransferFrom(msg.sender, pair, amountB);
    liquidity = DEXPair(pair).mint(to);
    }

    // Increase liquidity token-ETH
    function increaseLiquidityETH(
    address token,
    uint amountTokenDesired,
    uint amountTokenMin,
    uint amountETHMin,
    address to,
    uint deadline
    ) external payable returns (uint liquidity, uint amountToken, uint amountETH) {
    require(block.timestamp <= deadline, "DEXRouter: EXPIRED");

    (uint reserveToken, uint reserveETH) = getReserves(token, WETH);

    if (reserveToken == 0 && reserveETH == 0) {
        amountToken = amountTokenDesired;
        amountETH = msg.value;
    } else {
        uint amountETHOptimal = quote(amountTokenDesired, reserveToken, reserveETH);
        if (amountETHOptimal <= msg.value) {
            require(amountETHOptimal >= amountETHMin, "DEXRouter: INSUFFICIENT_ETH_AMOUNT");
            amountToken = amountTokenDesired;
            amountETH = amountETHOptimal;
        } else {
            uint amountTokenOptimal = quote(msg.value, reserveETH, reserveToken);
            require(amountTokenOptimal <= amountTokenDesired, "DEXRouter: INSUFFICIENT_TOKEN_AMOUNT");
            require(amountTokenOptimal >= amountTokenMin, "DEXRouter: INSUFFICIENT_TOKEN_AMOUNT");
            amountToken = amountTokenOptimal;
            amountETH = msg.value;
        }
    }

    address pair = _getPair(token, WETH);
    IERC20(token).safeTransferFrom(msg.sender, pair, amountToken);
    IWETH(WETH).deposit{value: amountETH}();
    assert(IWETH(WETH).transfer(pair, amountETH));
    liquidity = DEXPair(pair).mint(to);

    // Refund dust ETH
    if (msg.value > amountETH) {
        payable(msg.sender).transfer(msg.value - amountETH);
    }
}
}
