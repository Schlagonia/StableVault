// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {BaseStrategy, StrategyParams} from "../BaseStrategy.sol";
import {SafeERC20, SafeMath, IERC20, Address} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/joe/Ijoe.sol";
import "../interfaces/joe/Ijoetroller.sol";

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    Ijoetroller joetroller;

    struct TokenInfo {
        bool live;
        string name;
        uint256 decimals;
        address pool;
        uint256 totalDeposited;
        uint256 totalBorrowed;
        uint256 collateralFactor;
    }

    uint256 tokens = 0;
    // Used to add and remove twelve decimals to coins that only use 6 decimals
    uint256 twelve = 1000000000000;

    mapping(uint256 => address) tokenId;
    mapping(address => tokenInfo) tokenDetails;

    event tokenAded(string name, address tokenAddress, address lendingPool, bool isLive);

    constructor(address _vault, address _joetroller) public BaseStrategy(_vault) {
        joetroller = Ijoetroller(_joetroller);
    }

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************

    function name() external view override returns (string memory) {
        // Add your own name here, suggestion e.g. "StrategyCreamYFI"
        return "Joseph Money Market";
    }

    function setJoeTroller(address _joetroller) external onlyStrategist {
        joetroller = Ijoetroller(_joetroller);
    }

    function addToken(
        string _name,
        bool _live,
        address _pool
    ) external onlyStrategist {
        require(!tokenDetails[_token], "Token already added");

        uint256 newId = tokens;
        tokens++;

        require(tokenId[newId] == address(0), "ID already taken");

        tokenId[newId] = _token;

        //Need to find the debt threshhold for the token in the lending pool
        (bool isListed, uint256 collateralFactorMantissa) = joetroller.markets(_pool);
        require(islisted, "No Lending pool available");

        tokenDetails[_token] = TokenInfo({
            live: _live, // Is the token allowed to be used
            name: _name, // Name of the token
            decimals: IERC20(_token).decimals(), // How many decimals it uses
            pool: _pool, // Address of the lending pool
            totalDeposited: 0, //total number of shares for the token
            totalBorrowed: 0, //total number of tokens deposited
            collateralFactor: collateralFactorMantissa // @@@ need to get the max that can be borrowed with token as collateral
        });

        _enterMarket(_pool);

        emit TokenAdded(_name, _token, _pool, _live);
    }

    function _enterMarket(address _pool) internal {
        // Enter the market so you can borrow another type of asset
        address[] memory jtokens = new address[](1);
        jtokens[0] = _pool;
        uint256[] memory errors = joetroller.enterMarkets(jtokens);
        if (errors[0] != 0) {
            revert("Comptroller.enterMarkets failed.");
        }
    }

    function balanceOfWant(address _token) public view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    //returns balance of unerlying asset invested in pool at 18 decimals
    function balanceOfVault(address _pool, uint256 _decimals) public view returns (uint256) {
        (uint256 error, uint256 jTokenBalance, uint256 borrowBalance, uint256 exchangeRateMantissa) = IJoe(_pool).getAccountSnapshot(
            address(this)
        );
        
        // get deposited balanace
        uint256 got = jTokenBalance.mul(exchangeRateMantissa);
        //correct decimals if need to
        if(_decimals == 6) {
            got = got.div(1e6);
            //subtract borrowed balance
            got = got.sub(borrowBalance.mul(1e12));
        } else {
        
            got = got.sub(borrowBalance);
        }
        return got;
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        uint256 total = 0;
        uint256 bal;

        for (uint256 i = 0; i < tokens; i++) {
            TokenInfo tokenInfo = tokenDetails[tokenId[i]];

            bal = balanceOfWant(tokenId[i]);

            if (tokenInfo.decimals == 6) {
                //correct the number to be 18 decimals
                bal = bal.mul(twelve);
            }

            //assuming balance of vault returns 1e18 put it here
            bal = bal.add(balanceOfVault(tokenInfo.pool, tokenInfo.decimals));

            total = total.add(bal);
        }

        return total;
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        // TODO: Do stuff here to free up any returns back into `want`
        // NOTE: Return `_profit` which is value generated by all positions, priced in `want`
        // NOTE: Should try to free up at least `_debtOutstanding` of underlying position
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        // TODO: Do something to invest excess `want` tokens (from the Vault) into your positions
        // NOTE: Try to adjust positions so that `_debtOutstanding` can be freed up on *next* harvest (not immediately)
    }

    function liquidatePosition(uint256 _amountNeeded) internal override returns (uint256 _liquidatedAmount, uint256 _loss) {
        // TODO: Do stuff here to free up to `_amountNeeded` from all positions back into `want`
        // NOTE: Maintain invariant `want.balanceOf(this) >= _liquidatedAmount`
        // NOTE: Maintain invariant `_liquidatedAmount + _loss <= _amountNeeded`

        uint256 totalAssets = want.balanceOf(address(this));
        if (_amountNeeded > totalAssets) {
            _liquidatedAmount = totalAssets;
            _loss = _amountNeeded.sub(totalAssets);
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        // TODO: Liquidate all positions and return the amount freed.
        return want.balanceOf(address(this));
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary

    function prepareMigration(address _newStrategy) internal override {
        // TODO: Transfer any non-`want` tokens to the new strategy
        // NOTE: `migrate` will automatically forward all `want` in this strategy to the new one
    }

    // Override this to add all tokens/tokenized positions this contract manages
    // on a *persistent* basis (e.g. not just for swapping back to want ephemerally)
    // NOTE: Do *not* include `want`, already included in `sweep` below
    //
    // Example:
    //
    //    function protectedTokens() internal override view returns (address[] memory) {
    //      address[] memory protected = new address[](3);
    //      protected[0] = tokenA;
    //      protected[1] = tokenB;
    //      protected[2] = tokenC;
    //      return protected;
    //    }
    function protectedTokens() internal view override returns (address[] memory) {}

    /**
     * @notice
     *  Provide an accurate conversion from `_amtInWei` (denominated in wei)
     *  to `want` (using the native decimal characteristics of `want`).
     * @dev
     *  Care must be taken when working with decimals to assure that the conversion
     *  is compatible. As an example:
     *
     *      given 1e17 wei (0.1 ETH) as input, and want is USDC (6 decimals),
     *      with USDC/ETH = 1800, this should give back 1800000000 (180 USDC)
     *
     * @param _amtInWei The amount (in wei/1e-18 ETH) to convert to `want`
     * @return The amount in `want` of `_amtInEth` converted to `want`
     **/
    function ethToWant(uint256 _amtInWei) public view virtual override returns (uint256) {
        // TODO create an accurate price oracle
        return _amtInWei;
    }
}
