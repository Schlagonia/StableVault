//SPDX-License-Identifier: Unlicense
pragma solidity ^0.6.12;

//import './IJoe.sol';

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
    
    /**
     * @notice Claim all the JOE/AVAX accrued by holder in the specified markets
     * @param rewardType 0 = JOE, 1 = AVAX
     * @param holder The address to claim JOE/AVAX for
     *  jTokens The list of markets to claim JOE/AVAX in
     */
    function claimReward(
        uint8 rewardType,
        address payable holder
    ) external;

    function rewardAccrued(uint8, address) external view returns (uint256);
    
}