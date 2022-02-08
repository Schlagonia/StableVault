// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IJoeRewarder {
    function pendingTokens(address user) external view returns (uint256 pending);

    function rewardAccrued(uint8, address) external view returns (uint256);

    function claimReward(uint8 rewardType, address payable holder) external;
}
