//SPDX-License-Identifier: Unlicense
pragma solidity ^0.6.12;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import '@openzeppelin/contracts/math/SafeMath.sol';

import '../interfaces/joe/IJoeRouter.sol';
import '../interfaces/joe/IJoeFactory.sol';
import '../interfaces/joe/IJoePair.sol';

import {JoeLibrary} from '../Libraries/JoeLibrary.sol';


contract SwapperJoe {

    using SafeMath for uint256;

    IJoeRouter joeRouter = IJoeRouter(0x60aE616a2155Ee3d9A68541Ba4544862310933d4);
    IJoeFactory joeFactory = IJoeFactory(0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10);

    function _setMightyJoeRouter(address _router) internal {
        joeRouter = IJoeRouter(_router);
    }

    function _setJoeFactory(address _factory) internal {
        joeFactory = IJoeFactory(_factory); 
    }

    function _swapFrom(uint256 _amount, address _from, address _to) internal {

        require(joeFactory.getPair(_from, _to) != address(0), "No Trading Pair for tokens");

        (uint256 fromReserve, uint256 toReserve) = JoeLibrary.getReserves(address(joeFactory), _from, _to);

        uint256 amountOut = JoeLibrary.getAmountOut(_amount, fromReserve, toReserve);
        
        address[] memory path = new address[](2);
        path[0] = _from;
        path[1] = _to;

        IERC20(_from).approve(address(joeRouter), _amount);
        
        joeRouter.swapExactTokensForTokens(_amount, amountOut, path, address(this), block.timestamp);
       
    }

    function _swapTo(uint256 _amountTo, address _from, address _to) internal {

        require(joeFactory.getPair(_from, _to) != address(0), "No Trading Pair for tokens");

        (uint256 fromReserve, uint256 toReserve) = JoeLibrary.getReserves(address(joeFactory), _from, _to);

        uint256 amountIn = JoeLibrary.getAmountIn(_amountTo, fromReserve, toReserve);
        
        address[] memory path = new address[](2);
        path[0] = _from;
        path[1] = _to;

        IERC20(_from).approve(address(joeRouter), amountIn);
        
        joeRouter.swapTokensForExactTokens(_amountTo, amountIn, path, address(this), block.timestamp);
        
    }




}