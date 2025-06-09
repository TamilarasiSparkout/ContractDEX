// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// DEXPair - Token pair liquidity pool with constant product formula
contract DEXPair is ERC20 {
    using SafeERC20 for IERC20;

    address public token0;
    address public token1;

    uint112 private reserve0;
    uint112 private reserve1;

    address public factory;

    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "DEXPair: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(address indexed sender, uint amountIn, address indexed inToken, uint amountOut, address indexed outToken, address to);
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor() ERC20("DEX LP Token", "DLP") {}

    function initialize(address _token0, address _token1) external {
        require(factory == address(0), "DEXPair: ALREADY_INITIALIZED");
        require(_token0 != _token1, "Identical addresses");
        (token0, token1) = _token0 < _token1 ? (_token0, _token1) : (_token1, _token0);
        factory = msg.sender;
    }

    function getReserves() public view returns (uint112, uint112) {
        return (reserve0, reserve1);
    }

    function _update(uint256 balance0, uint256 balance1) private {
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        emit Sync(reserve0, reserve1);
    }

    function mint(address to) external lock returns (uint liquidity) {
        (uint112 _reserve0, uint112 _reserve1) = getReserves();
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        if (totalSupply() == 0) {
            liquidity = sqrt(amount0 * amount1);
        } else {
            liquidity = min((amount0 * totalSupply()) / _reserve0, (amount1 * totalSupply()) / _reserve1);
        }

        require(liquidity > 0, "DEXPair: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(balance0, balance1);
        emit Mint(to, amount0, amount1);
    }

    function burn(address to) external lock returns (uint amount0, uint amount1) {
        (uint112 _reserve0, uint112 _reserve1) = getReserves();
        require(_reserve0 >= amount0 && _reserve1 >= amount1, "DEXPair: INSUFFICIENT_RESERVES");

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint liquidity = balanceOf(address(this));

        amount0 = (liquidity * balance0) / totalSupply();
        amount1 = (liquidity * balance1) / totalSupply();

        require(amount0 > 0 && amount1 > 0, "DEXPair: INSUFFICIENT_LIQUIDITY_BURNED");

        _burn(address(this), liquidity);
        IERC20(token0).safeTransfer(to, amount0);
        IERC20(token1).safeTransfer(to, amount1);

        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)));
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function swap(address inputToken, uint256 amountIn, address to) external lock {
        require(inputToken == token0 || inputToken == token1, "Invalid input token");

        (address inToken, address outToken, uint112 reserveIn, uint112 reserveOut) =
            inputToken == token0 ? (token0, token1, reserve0, reserve1) : (token1, token0, reserve1, reserve0);

        IERC20(inToken).safeTransferFrom(msg.sender, address(this), amountIn);

        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        uint256 amountOut = numerator / denominator;

        require(amountOut > 0 && reserveOut > amountOut, "Insufficient output");
        IERC20(outToken).safeTransfer(to, amountOut);

        uint256 newBalanceIn = IERC20(inToken).balanceOf(address(this));
        uint256 newBalanceOut = IERC20(outToken).balanceOf(address(this));
        if (inputToken == token0) _update(newBalanceIn, newBalanceOut);
        else _update(newBalanceOut, newBalanceIn);

        emit Swap(msg.sender, amountIn, inToken, amountOut, outToken, to);
    }

    // Helper math
    function min(uint x, uint y) private pure returns (uint z) {
        z = x < y ? x : y;
    }

    function sqrt(uint y) private pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
