//SPDX-License-Identifier: Unlicense
pragma solidity ^0.6.12;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import '@openzeppelin/contracts/math/SafeMath.sol';

import '../interfaces/joe/IJoeRouter.sol';
import '../interfaces/joe/IJoeFactory.sol';
import '../interfaces/joe/IJoePair.sol';
import "../interfaces/PTP/IPTPSwap.sol";

import {JoeLibrary} from '../Libraries/JoeLibrary.sol';


contract SwapperLife {

    using SafeMath for uint256;

    IJoeRouter joeRouter = IJoeRouter(0x60aE616a2155Ee3d9A68541Ba4544862310933d4);
    IJoeFactory joeFactory = IJoeFactory(0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10);
    IPTPPool ptpPool = IPTPPool(0x66357dCaCe80431aee0A7507e2E361B7e2402370);

    function _setMightyJoeRouter(address _router) internal {
        joeRouter = IJoeRouter(_router);
    }

    function _setJoeFactory(address _factory) internal {
        joeFactory = IJoeFactory(_factory); 
    }

    function _setPTPPool(address _pool) internal {
        ptpPool = IPTPPool(_pool);
    }

    function _ptpQoute(
        address _from,
        address _to,
        uint256 _amount
    ) internal view returns (uint256) {
        (uint256 amountOut, ) = ptpPool.quotePotentialSwap(_from, _to, _amount);

        return amountOut;
    }

    function _ptpSwapWithAmount(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _amountOut
    ) internal returns (uint256 actualOut) {
        IERC20(_from).approve(address(ptpPool), _amountIn);

        (actualOut, ) = ptpPool.swap(_from, _to, _amountIn, _amountOut, address(this), block.timestamp);
    }

    function _ptpSwap(
        address _from,
        address _to,
        uint256 _amount
    ) internal returns (uint256){
        uint256 amountOut = _ptpQoute(_from, _to, _amount); 

        return _ptpSwapWithAmount(_from, _to, _amount, amountOut);
    }


    function _checkPrice(address _from, address _to, uint256 _amount) internal view returns (uint256) {
    
        if(_amount == 0 || joeFactory.getPair(_from, _to) == address(0)) {
            return 0;
        }

        (uint256 fromReserve, uint256 toReserve) = JoeLibrary.getReserves(address(joeFactory), _from, _to);

        return JoeLibrary.getAmountOut(_amount, fromReserve, toReserve);

    }

    function _swapFromWithAmount(address _from, address _to, uint256 _amountIn, uint256 _amountOut) internal returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = _from;
        path[1] = _to;

        IERC20(_from).approve(address(joeRouter), _amountIn);
        
        uint256[] memory amounts = joeRouter.swapExactTokensForTokens(_amountIn, _amountOut, path, address(this), block.timestamp);

        return amounts[1];
    }

    function _swapFrom(address _from, address _to, uint256 _amountIn) internal returns(uint256){

        uint256 amountOut = _checkPrice(_from, _to, _amountIn);
        
        return _swapFromWithAmount(_from, _to, _amountIn, amountOut);
    }

    function _swapTo(address _from, address _to, uint256 _amountTo) internal returns(uint256) {

        if(_amountTo == 0 || joeFactory.getPair(_from, _to) == address(0)) {
            return 0;
        }
        (uint256 fromReserve, uint256 toReserve) = JoeLibrary.getReserves(address(joeFactory), _from, _to);

        uint256 amountIn = JoeLibrary.getAmountIn(_amountTo, fromReserve, toReserve);
        
        address[] memory path = new address[](2);
        path[0] = _from;
        path[1] = _to;

        IERC20(_from).approve(address(joeRouter), amountIn);
        
        uint256[] memory amounts = joeRouter.swapTokensForExactTokens(_amountTo, amountIn, path, address(this), block.timestamp);

        return amounts[1];
    }




}