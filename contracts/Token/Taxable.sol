// SPDX-License-Identifier: MIT

/**
    Taxable.sol

    A contract designed to make a Tradable token that also has
    taxes, which go to development, marketing, and liquidity.
    These taxes are adjustable, and can be split differently
    for buys and sells.

    The constructor requires the instantiator to set a max dev
    fee and a max tax limit, which will enable the developer
    to inform their community that there is a limit to how
    high the token can be taxed.
*/

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./Tradable.sol";

abstract contract Taxable is Owned, Tradable {
    using SafeMath for uint256;

    struct Taxes {
        uint8 devFee;
        uint8 rewardsFee;
        uint8 marketingFee;
        uint8 teamFee;
        uint8 liqFee;
    }

    uint8 constant BUYTX = 1;
    uint8 constant SELLTX = 2;
    //
    address payable public _devAddress;
    address payable public _marketingAddress;
    address payable public _teamAddress;
    //
    uint256 public _liquifyThreshhold;
    bool inSwapAndLiquify;
    //
    uint8 public _maxFees;
    uint8 public _maxDevFee;
    //
    Taxes public _buyTaxes;
    uint8 public _totalBuyTaxes;
    Taxes public _sellTaxes;
    uint8 public _totalSellTaxes;
    //
    uint256 private _devTokensCollected;
    uint256 private _rewardsTokensCollected;
    uint256 private _marketingTokensCollected;
    uint256 private _teamTokensCollected;
    uint256 private _liqTokensCollected;
    //
    mapping (address => bool) private _isExcludedFromFees;

    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    constructor(string memory symbol, 
                string memory name, 
                TokenDistribution memory tokenDistribution,
                address payable devAddress,
                address payable marketingAddress,
                address payable teamAddress,
                Taxes memory buyTaxes,
                Taxes memory sellTaxes,
                uint8 maxFees, 
                uint8 maxDevFee, 
                uint256 liquifyThreshhold)
    Tradable(symbol, name, tokenDistribution) {
        _devAddress = devAddress;
        _marketingAddress = marketingAddress;
        _teamAddress = teamAddress;
        _buyTaxes = buyTaxes;
        _sellTaxes = sellTaxes;
        _totalBuyTaxes = buyTaxes.devFee + buyTaxes.rewardsFee + buyTaxes.marketingFee + buyTaxes.teamFee + buyTaxes.liqFee;
        _totalSellTaxes = sellTaxes.devFee + sellTaxes.rewardsFee + sellTaxes.marketingFee + sellTaxes.teamFee + sellTaxes.liqFee;
        _maxFees = maxFees;
        _maxDevFee = maxDevFee;
        _liquifyThreshhold = liquifyThreshhold;

        _isExcludedFromFees[owner] = true;
        _isExcludedFromFees[address(this)] = true;
        _isExcludedFromFees[marketingAddress] = true;
        _isExcludedFromFees[devAddress] = true;
    }

    function setMarketingAddress(address payable newMarketingAddress) external onlyOwner() {
        require(newMarketingAddress != _marketingAddress);
        _marketingAddress = newMarketingAddress;
    }

    function setDevAddress(address payable newDevAddress) external onlyOwner() {
        require(newDevAddress != _devAddress);
        _devAddress = newDevAddress;
    }

    function setTeamAddress(address payable newTeamAddress) external onlyOwner() {
        require(newTeamAddress != _teamAddress);
        _teamAddress = newTeamAddress;
    }

    function includeInFees(address account) public onlyOwner {
        _isExcludedFromFees[account] = false;
    }

    function excludeFromFees(address account) public onlyOwner {
        _isExcludedFromFees[account] = true;
    }

    function setBuyFees(uint8 newDevBuyFee, uint8 newRewardsBuyFee, uint8 newMarketingBuyFee, uint8 newTeamBuyFee, uint8 newLiqBuyFee) external onlyOwner {
        uint8 newTotalBuyFees = newDevBuyFee + newRewardsBuyFee + newMarketingBuyFee + newTeamBuyFee + newLiqBuyFee;
        require(!inSwapAndLiquify, "inSwapAndLiquify");
        require(newDevBuyFee <= _maxDevFee, "Cannot set dev fee higher than max");
        require(newTotalBuyFees <= _maxFees, "Cannot set total buy fees higher than max");

        _buyTaxes = Taxes({ devFee: newDevBuyFee, rewardsFee: newRewardsBuyFee, marketingFee: newMarketingBuyFee,
            teamFee: newTeamBuyFee, liqFee: newLiqBuyFee });
        _totalBuyTaxes = newTotalBuyFees;
    }

    function setSellFees(uint8 newDevSellFee, uint8 newRewardsSellFee, uint8 newMarketingSellFee, uint8 newTeamSellFee, uint8 newLiqSellFee) external onlyOwner {
        uint8 newTotalSellFees = newDevSellFee + newRewardsSellFee + newMarketingSellFee + newTeamSellFee + newLiqSellFee;
        require(!inSwapAndLiquify, "inSwapAndLiquify");
        require(newDevSellFee <= _maxDevFee, "Cannot set dev fee higher than max");
        require(newTotalSellFees <= _maxFees, "Cannot set total sell fees higher than max");

        _sellTaxes = Taxes({ devFee: newDevSellFee, rewardsFee: newRewardsSellFee, marketingFee: newMarketingSellFee,
            teamFee: newTeamSellFee, liqFee: newLiqSellFee });
        _totalSellTaxes = newTotalSellFees;
    }

    function setLiquifyThreshhold(uint256 newLiquifyThreshhold) external onlyOwner {
        _liquifyThreshhold = newLiquifyThreshhold;
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transferWithTaxes(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transferWithTaxes(sender, recipient, amount);
        approveFromOwner(sender, msg.sender, _allowances[sender][msg.sender].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function _transferWithTaxes(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        if(
            from != owner &&              // Not from Owner
            to != owner &&                // Not to Owner
            !_isExcludedFromMaxBalance[to]  // is excludedFromMaxBalance
        ) {
            require(balanceOf(to).add(amount) <= _maxBalance, "Tx would cause wallet to exceed max balance");
        }
        
        // Sell tokens for funding
        if(
            !inSwapAndLiquify &&                                // Swap is not locked
            balanceOf(address(this)) >= _liquifyThreshhold &&   // liquifyThreshhold is reached
            from != pair                                        // Not from liq pool (can't sell during a buy)
        ) {
            swapCollectedFeesForFunding();
        }

        // Send fees to contract if necessary
        uint8 txType = 0;
        if (from == pair) txType = BUYTX;
        if (to == pair) txType = SELLTX;
        if(
            txType != 0 &&
            !(_isExcludedFromFees[from] || _isExcludedFromFees[to])
            && ((txType == BUYTX && _totalBuyTaxes > 0)
            || (txType == SELLTX && _totalSellTaxes > 0))
        ) {
            uint256 feesToContract = calculateTotalFees(amount, txType);
            
            if (feesToContract > 0) {
                amount = amount.sub(feesToContract); 
                _transfer(from, address(this), feesToContract);
            }
        }

        _transfer(from, to, amount);
    }

    function calculateTotalFees(uint256 amount, uint8 txType) private returns (uint256) {
        uint256 devTokens = (txType == BUYTX) ? amount.mul(_buyTaxes.devFee).div(100) : amount.mul(_sellTaxes.devFee).div(100);
        uint256 rewardsTokens = (txType == BUYTX) ? amount.mul(_buyTaxes.rewardsFee).div(100) : amount.mul(_sellTaxes.rewardsFee).div(100);
        uint256 marketingTokens = (txType == BUYTX) ? amount.mul(_buyTaxes.marketingFee).div(100) : amount.mul(_sellTaxes.marketingFee).div(100);
        uint256 teamTokens = (txType == BUYTX) ? amount.mul(_buyTaxes.teamFee).div(100) : amount.mul(_sellTaxes.teamFee).div(100);
        uint256 liqTokens = (txType == BUYTX) ? amount.mul(_buyTaxes.liqFee).div(100) : amount.mul(_sellTaxes.liqFee).div(100);

        _devTokensCollected = _devTokensCollected.add(devTokens);
        _rewardsTokensCollected = _rewardsTokensCollected.add(rewardsTokens);
        _marketingTokensCollected = _marketingTokensCollected.add(marketingTokens);
        _teamTokensCollected = _teamTokensCollected.add(teamTokens);
        _liqTokensCollected = _liqTokensCollected.add(liqTokens);

        return devTokens.add(rewardsTokens).add(marketingTokens).add(teamTokens).add(liqTokens);
    }

    function swapCollectedFeesForFunding() private lockTheSwap {
        uint256 totalCollected = _devTokensCollected.add(_marketingTokensCollected).add(_liqTokensCollected);
        require(totalCollected > 0, "No tokens available to swap");

        uint256 initialFunds = address(this).balance;

        uint256 halfLiq = _liqTokensCollected.div(2);
        uint256 otherHalfLiq = _liqTokensCollected.sub(halfLiq);

        uint256 totalAmountToSwap = _devTokensCollected.add(_rewardsTokensCollected).add(_marketingTokensCollected)
            .add(_teamTokensCollected).add(halfLiq);

        swapTokensForNative(totalAmountToSwap);

        uint256 newFunds = address(this).balance.sub(initialFunds);

        uint256 liqFunds = newFunds.mul(halfLiq).div(totalAmountToSwap);
        uint256 marketingFunds = newFunds.mul(_marketingTokensCollected).div(totalAmountToSwap);
        uint256 rewardsFunds = newFunds.mul(_rewardsTokensCollected).div(totalAmountToSwap);
        uint256 teamFunds = newFunds.mul(_teamTokensCollected).div(totalAmountToSwap);
        uint256 devFunds = newFunds.sub(liqFunds).sub(marketingFunds);

        addLiquidity(otherHalfLiq, liqFunds);
        IERC20(router.WETH()).transfer(_marketingAddress, marketingFunds);
        IERC20(router.WETH()).transfer(_devAddress, devFunds);
        IERC20(router.WETH()).transfer(_teamAddress, teamFunds);
        try distributor.deposit{value: rewardsFunds}() {} catch {}

        _devTokensCollected = 0;
        _marketingTokensCollected = 0;
        _liqTokensCollected = 0;
        _rewardsTokensCollected = 0;
        _teamTokensCollected = 0;
    }

    function swapTokensForNative(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        approveFromOwner(address(this), address(router), tokenAmount);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, 
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        approveFromOwner(address(this), address(router), tokenAmount);

        router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, 
            0, 
            address(0),
            block.timestamp
        );
    }
}