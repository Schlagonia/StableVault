//SPDX-License-Identifier: Unlicense
pragma solidity ^0.6.12;


interface IJoetroller {
    // checks if token has a market open
    function markets(address) external returns (bool, uint256);

    //Allows the deposit to be used as collateral
    function enterMarkets(address[] calldata)
        external
        returns (uint256[] memory);

/**
     * @notice Determine the current account liquidity wrt collateral requirements
     * @return (possible error code (semi-opaque),
                account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidity(address)
        external
        view
        returns (uint256, uint256, uint256);
    
}