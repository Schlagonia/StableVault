// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {BaseStrategy, StrategyParams} from "../BaseStrategy.sol";
import {SafeERC20, SafeMath, IERC20, Address} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";

import "./SwapperLife.sol";
import "../interfaces/joe/Ijoe.sol";
import "../interfaces/joe/Ijoetroller.sol";
import "../interfaces/joe/IJoeRewarder.sol";

//Add a deposit for function to pay down other strategies debt rather than unfold

contract Joseph is BaseStrategy, SwapperLife {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IJoetroller joetroller;
    IJoeRewarder joeRewarder = IJoeRewarder(0x45B2C4139d96F44667577C0D7F7a7D170B420324);
    IERC20 joeToken = IERC20(0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd);
    

    uint256 public loops = 3; //number of loops we do
    uint256 collateralTarget =  750000000000000000;
    uint256 minimumBorrow = 1000000000000000000;  //1e18
    uint256 minInvest = 1000000000000000000;  //1e18
    uint256 constant secondsPerYear = 31536000;
    uint256 SuppliedIndex;
    uint256 BorrowedIndex;

    struct TokenInfo {
        bool added;
        bool live;
        string name;
        uint256 decimals;
        address pool;
        uint256 totalDeposited;
        uint256 totalBorrowed;
        uint256 collateralFactor;
    }

    uint256 tokens = 0;

    mapping(uint256 => address) tokenId;
    mapping(address => TokenInfo) tokenDetails;

    event tokenAdded(string name, address tokenAddress, address lendingPool, bool isLive);

    constructor(
        address _vault,
        address _joetroller,
        address _joeToken
    ) public BaseStrategy(_vault) {
        joetroller = IJoetroller(_joetroller);
        joeToken = IERC20(_joeToken);
    }

    function name() external view override returns (string memory) {
        return "Joseph Money Market";
    }

    function setLoops(uint256 _loops) external onlyStrategist {
        loops = _loops;
    }

    function setCollateralTartet(uint256 _target) external onlyStrategist {
        collateralTarget = _target;
    }

    function setMinimumBorrow(uint256 _min) external onlyStrategist {
        minimumBorrow = _min;
    }

    function setMinInvest(uint256 _min) external onlyStrategist {
        minInvest = _min;
    }

    function setJoeTroller(address _joetroller) external onlyStrategist {
        require(_joetroller != address(0), "Must be valid address");
        joetroller = IJoetroller(_joetroller);
    }

    function setJoeToken(address _token) external onlyStrategist {
        require(_token != address(0), "Must be valid address");
        joeToken = IERC20(_token);
    }

    function setMightyJoeRouter(address _router) external onlyStrategist {
        require(_router != address(0), "Must be valid address");
        _setMightyJoeRouter(_router);
    }

    function setJoeFactory(address _factory) external onlyStrategist {
        require(_factory != address(0), "Must be valid address");
        _setJoeFactory(_factory);
    }

    function setJoeRewarder(address _rewarder) external onlyStrategist {
        require(_rewarder != address(0), "Must be valid Address");
        joeRewarder = IJoeRewarder(_rewarder);
    }

    function setPTPPool(address _pool) external onlyStrategist {
        require(_pool != address(0), "Must be valid Address");
        ptpPool = IPTPPool(_pool);
    }

    //Add new tokens
    //Add base want token first to have 0 tokenId
    //Only add with decimals 18 or 6
    function addToken(
        string memory _name,
        address _token,
        bool _live,
        address _pool,
        uint256 _decimals
    ) external onlyStrategist {
        require(!tokenDetails[_token].added, "Token already added");

        uint256 newId = tokens;
        tokens++;

        require(tokenId[newId] == address(0), "ID already taken");

        tokenId[newId] = _token;

        //Need to find the debt threshhold for the token in the lending pool
        (bool isListed, uint256 collateralFactorMantissa) = joetroller.markets(_pool);
        require(isListed, "No Lending pool available");

        tokenDetails[_token] = TokenInfo({
            added: true,
            live: _live, // Is the token allowed to be used
            name: _name, // Name of the token
            decimals: _decimals, // How many decimals it uses
            pool: _pool, // Address of the lending pool
            totalDeposited: 0, //total number of shares for the token
            totalBorrowed: 0, //total number of tokens deposited
            collateralFactor: collateralFactorMantissa // @@@ need to get the max that can be borrowed with token as collateral
        });

        _enterMarket(_pool);

        //approve Pool
        IERC20(_token).approve(_pool, type(uint256).max);

        emit tokenAdded(_name, _token, _pool, _live);
    }

    function updateToken(
        string memory _name,
        address _token,
        bool _live,
        address _pool,
        uint256 _decimals
    ) external onlyStrategist {

    }

    function changeLive(address _token) external onlyStrategist {
        require(tokenDetails[_token].added, "Token not used");

        tokenDetails[_token].added = !tokenDetails[_token].added;
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
        uint256 got;
        //correct decimals if need to
        if (_decimals == 6) {
            got = jTokenBalance.mul(exchangeRateMantissa).div(1e6);
            //subtract borrowed balance
            //@dev need to account for negative balances with no positve balance
            got = got.sub(borrowBalance.mul(1e12));
        } else if (_decimals == 18) {
            got = jTokenBalance.mul(exchangeRateMantissa).div(1e18);
            got = got.sub(borrowBalance);
        }
        return got;
    }

    //returns net balance of all all free and invested token to 18 decimals
    function getStableCoinBalance() internal view returns (uint256 _total) {
        _total = 0;

        //need to account for negative balances due to dust left in boorow bools
        for (uint256 i = 0; i < tokens; i++) {
            TokenInfo storage tokenInfo = tokenDetails[tokenId[i]];
            uint256 bal = balanceOfWant(tokenId[i]);

            if (tokenInfo.decimals == 6) {
                //correct the number to be 18 decimals
                bal = bal.mul(1e12);
            }

            //add balance of vault returned in underlying
            bal = bal.add(balanceOfVault(tokenInfo.pool, tokenInfo.decimals));

            _total = _total.add(bal);
        }
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        uint256 total = 0;
        uint256 bal;

        //estimate reward token not claimed or sitting in address
        uint256 _claimable = estimateReward();
        uint256 current = balanceOfWant(address(joeToken));

        // Use touch price. it doesnt matter if we are wrong as this is not used for decision making
        uint256 estimatedWant = _checkPrice(address(joeToken), tokenId[0], _claimable.add(current));
        total = estimatedWant.mul(9).div(10); //10% pessimist

        uint256 jTokens = getStableCoinBalance();

        total = total.add(jTokens);

        return total;
    }

    function swapStable(
        address _from,
        address _to,
        uint256 _amount
    ) internal returns (uint256 actualOut) {
        uint256 ptpOut = _ptpQoute(_from, _to, _amount);
        uint256 joeOut = _checkPrice(_from, _to, _amount);

        if(ptpOut >= joeOut) {
            actualOut = _ptpSwapWithAmount(_from, _to, _amount, ptpOut);
        } else {
            actualOut = _swapFromWithAmount(_from, _to, _amount, joeOut);
        }
    }

    function checkreward() public view returns (bool) {
        //check the rewards available
        if (joeRewarder.rewardAccrued(0, address(this)) > 0) {
            return true;
        } else {
            return false;
        }
    }

    function harvesterJoe() internal {
        if (checkreward()) {
            joetroller.claimReward(0, payable(address(this)));
        }
    }

    function estimateReward() public view returns (uint256) {
        //Calculates an expected amount of claimable reward tokens
    }

    //call to find the pool that is paying the highest supply apy and the lowest borrow apy
    //Takes in to account both native rates and reward distribution
    //Returns _supplyIndex of highest and _borrowIndex of lowest
    function checkAPRs() internal view returns (uint256, uint256) {
        
        uint256 _supplyIndex;
        uint256 _borrowIndex;
        uint256 supplyApr = 0;
        uint256 borrowApr = type(uint256).max;

        //get joe price with a price check
        uint256 joePrice = _checkPrice(address(joeToken), tokenId[0], 1e18);
        
        for (uint256 i = 0; i < tokens; i++) {
            TokenInfo storage tokenInfo = tokenDetails[tokenId[i]];
            IJoe _pool = IJoe(tokenInfo.pool);
            uint256 supplyRewardFinal = 0;
            uint256 borrowRewardFinal = 0;

            uint256 rewardSupplyRate = joeRewarder.rewardSupplySpeeds(0, address(_pool));
            uint256 rewardBorrowRate = joeRewarder.rewardBorrowSpeeds(0, address(_pool));
            //get balances of borrow adn cash-reserves
            //get the dollar value of joe supply rate per second
            // rewardAPY = (joePrice * rewardRate) / totalAssets
            if(rewardSupplyRate > 0){
                uint256 totalAssets = _pool.getCash().add(_pool.totalBorrows()).sub(_pool.totalReserves());
                
                //adjust decimals since quote is in 6 decimals
                if(tokenInfo.decimals == 18) {
                    rewardSupplyRate = rewardSupplyRate.mul(1e12);
                }

                supplyRewardFinal = joePrice.mul(rewardSupplyRate).div(totalAssets);
            }

            if(rewardBorrowRate > 0){
                uint256 borrowedAssets = _pool.totalBorrows();
                //adjust decimals since quote is in 6 decimals
                if(tokenInfo.decimals == 18) {
                    rewardBorrowRate = rewardBorrowRate.mul(1e12);
                }

                borrowRewardFinal = joePrice.mul(rewardBorrowRate).div(borrowedAssets);
            }

            uint256 nativeSupplyRate = _pool.supplyRatePerSecond();
            uint256 nativeBorrowRate = _pool.borrowRatePerSecond();

            uint256 netSupply = nativeSupplyRate.add(supplyRewardFinal);
            uint256 netBorrow = 0;
            //check for overflow
            if(nativeBorrowRate > borrowRewardFinal){
                netBorrow = nativeBorrowRate.sub(borrowRewardFinal);
            } 
           
            if(netSupply > supplyApr) {
                supplyApr = netSupply;
                _supplyIndex = i;
            }

            if(netBorrow < borrowApr) {
                borrowApr = netBorrow;
                _borrowIndex = i;
            }
          
        }

        return(_supplyIndex, _borrowIndex);
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
        _profit = 0;
        _loss = 0; // for clarity. also reduces bytesize
        _debtPayment = 0;

        //claim rewards
        harvesterJoe();
        //swap rewards to main want
        //create a minimumJoe to need to meet in order to swap
        _swapFrom(address(joeToken), tokenId[0], joeToken.balanceOf(address(this)));

        //get base want balance
        uint256 wantBalance = balanceOfWant(tokenId[0]);

        //get total acount value
        uint256 balance = getStableCoinBalance();
        //get amount given to strat by vault
        uint256 debt = vault.strategies(address(this)).totalDebt;

        //Check to see if there is nothing invested
        if (balance == 0 && debt == 0) {
            return (_profit, _loss, _debtPayment);
        }

        //Balance - Total Debt is profit
        if (balance > debt) {
            _profit = balance.sub(debt);

            uint256 needed = _profit.add(_debtOutstanding);
            if (needed > wantBalance) {
                needed = needed.sub(wantBalance);
                withdrawSome(needed);

                wantBalance = balanceOfWant(tokenId[0]);

                if (wantBalance < needed) {
                    if (_profit > wantBalance) {
                        _profit = wantBalance;
                        _debtPayment = 0;
                    } else {
                        _debtPayment = Math.min(wantBalance.sub(_profit), _debtOutstanding);
                    }
                } else {
                    _debtPayment = _debtOutstanding;
                }
            } else {
                _debtPayment = _debtOutstanding;
            }
        } else {
            //we will lose money until we claim comp then we will make money
            //this has an unintended side effect of slowly lowering our total debt allowed
            _loss = debt.sub(balance);
            if (_debtOutstanding > wantBalance) {
                withdrawSome(_debtOutstanding.sub(wantBalance));
                wantBalance = balanceOfWant(tokenId[0]);
            }

            _debtPayment = Math.min(wantBalance, _debtOutstanding);
        }
    }

    function checkLiquidity() internal view returns (uint256, uint256) {
        //Get my account's total liquidity value in Compound
        (uint256 error2, uint256 liquidity, uint256 shortfall) = joetroller.getAccountLiquidity(address(this));
        if (error2 != 0) {
            revert("Comptroller.getAccountLiquidity failed.");
        }
 
        return (liquidity, shortfall);
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        // TODO: Do something to invest excess `want` tokens (from the Vault) into your positions
        // NOTE: Try to adjust positions so that `_debtOutstanding` can be freed up on *next* harvest (not immediately)
        //emergency exit is dealt with in prepareReturn
        if (emergencyExit) {
            return;
        }

        //we are spending all our cash unless we have debt outstanding
        uint256 _wantBal = balanceOfWant(tokenId[0]);
        if (_wantBal < _debtOutstanding) {
            //this is graceful withdrawal. dont use backup
            //we use more than 1 because withdrawunderlying causes problems with 1 token due to different decimals
            //check the current supplied Index
            if (balanceOfWant(tokenDetails[tokenId[SuppliedIndex]].pool) > 1) {
                withdrawSome(_debtOutstanding.sub(_wantBal));
            }

            return;
        }

        //We have something to invest
        uint256 toInvest = _wantBal.sub(_debtOutstanding);
        if(toInvest < minInvest){
            //not enough
            return;
        }
      
        //invest balance of supply
        depositSome(toInvest);
    }

    //return amount to borrow with 18 decimals
    function toBorrow() internal returns (uint256) {

        
TokenInfo storage supplyTokenInfo = tokenDetails[tokenId[SuppliedIndex]];
        TokenInfo storage borrowTokenInfo = tokenDetails[tokenId[BorrowedIndex]];
        IJoe supplyPool =  IJoe(supplyTokenInfo.pool);
        IJoe borrowPool =  IJoe(borrowTokenInfo.pool);
        
        (uint256 error, uint256 jTokenBalance, uint256 borrowBalance, uint256 exchangeRateMantissa) = supplyPool.getAccountSnapshot(
            address(this)
        );
        uint256 borrowedBalance = borrowPool.borrowBalanceStored(address(this));

        if(borrowTokenInfo.decimals == 6) {
            borrowedBalance = borrowedBalance.mul(1e12);
        }

        uint256 supply = jTokenBalance.mul(exchangeRateMantissa).div(1e18);
        
        uint256 desiredBorrow = supply.mul(collateralTarget).div(1e18);

        if(desiredBorrow < borrowedBalance) {
            //overlevereged dont borrow any more
            //should not happen
            withdrawSome(borrowedBalance.sub(desiredBorrow));
            return 0;
        }

        uint256 _toBorrow = desiredBorrow.sub(borrowedBalance);
    }

    //_amount in want decimals
    function leverage(uint256 _amount) internal {
        TokenInfo storage supplyTokenInfo = tokenDetails[tokenId[SuppliedIndex]];
        TokenInfo storage borrowTokenInfo = tokenDetails[tokenId[BorrowedIndex]];
        IJoe supplyPool =  IJoe(supplyTokenInfo.pool);
        IJoe borrowPool =  IJoe(borrowTokenInfo.pool);

        if(SuppliedIndex != 0) {
            swapStable(tokenId[0], tokenId[SuppliedIndex], _amount);
        } 
      
        supplyPool.mint(balanceOfWant(tokenId[SuppliedIndex]));

        uint256 _toBorrow = toBorrow();

        uint i = 0;
        while(_toBorrow > minimumBorrow && i < loops ) {

            if(borrowTokenInfo.decimals == 6) {
                _toBorrow = _toBorrow.div(1e12);
            }
        
            borrowPool.borrow(_toBorrow);
            swapStable(tokenId[BorrowedIndex], tokenId[SuppliedIndex], balanceOfWant(tokenId[BorrowedIndex]));

            _toBorrow = toBorrow();
            i++;
        }

    }
      
    //amount is in want decimals
    function depositSome(uint256 _amount) internal {
        bool changeSupplied = false;
        bool changeBorrowed = false;

        (uint256 _supplyIndex, uint256 _borrowIndex)  = checkAPRs();
        //check if thats where we are
        if(_supplyIndex != SuppliedIndex) {
            changeSupplied = true;
        }
        if(_borrowIndex != BorrowedIndex) {
            changeBorrowed = true;
        }

        if(!changeSupplied && !changeBorrowed) {
            leverage(_amount);
        }

    }

    function withdrawSome(uint256 _amount) internal {
        //perform logic to unwind position
        


    }

    function liquidatePosition(uint256 _amountNeeded) internal override returns (uint256 _liquidatedAmount, uint256 _loss) {
        // TODO: Do stuff here to free up to `_amountNeeded` from all positions back into `want`
        // NOTE: Maintain invariant `want.balanceOf(this) >= _liquidatedAmount`
        // NOTE: Maintain invariant `_liquidatedAmount + _loss <= _amountNeeded`

        uint256 wantBalance = balanceOfWant(tokenId[0]);
        if(wantBalance > _amountNeeded) {
            return (0, 0);
        }

        uint256 diff = _amountNeeded.sub(wantBalance);

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

    //should be able to send tokens without getting liquidated
    function prepareMigration(address _newStrategy) internal override {
        harvesterJoe();
        _swapFrom(address(joeToken), address(want), joeToken.balanceOf(address(this)));

        IJoe JToken = IJoe(tokenDetails[tokenId[0]].pool);
        JToken.transfer(_newStrategy, JToken.balanceOf(address(this)));

        //start at 1 so you dont send the want token
        for (uint256 i = 1; i < tokens; i++) {
            IERC20 token = IERC20(tokenId[i]);
            JToken = IJoe(tokenDetails[tokenId[i]].pool);
            token.transfer(_newStrategy, token.balanceOf(address(this)));
            JToken.transfer(_newStrategy, JToken.balanceOf(address(this)));
        }
    }

    // Override this to add all tokens/tokenized positions this contract manages
    // on a *persistent* basis (e.g. not just for swapping back to want ephemerally)
    // NOTE: Do *not* include `want`, already included in `sweep` below
    function protectedTokens() internal view override returns (address[] memory) {
        address[] memory protected = new address[](tokens.mul(2));
        uint256 counter = 0;
        for (uint256 i = 0; i < tokens; i++) {
            //add underlying token
            protected[counter] = tokenId[i];
            // add Jtoken
            protected[counter + 1] = tokenDetails[tokenId[i]].pool;

            counter += 2;
        }

        //replace the first item which is want with the reward token
        protected[0] = address(joeToken);

        return protected;
    }

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
