// SPDX-License-Identifier: MIT

/**
    #CATMAO

    15% buy and sell tax

    2% rewards - busd 

    2% lp

    10% development - 5%marketing/3%team/2%charity

    1% dev

    Dynamic dev tax, not to exceed 1%
    Dynamic buy/sell taxes for marketing and liquidity,
    not to exceed 15% total (incl dev tax)
 */

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./Taxable.sol";
import "./Tradable.sol";

contract Catmao is Context, Owned, Taxable {
	using SafeMath for uint256;
	using Address for address;

    string private _Cname = "Catmao";
    string private _Csymbol = "CATMAO";
    // 9 Decimals
    uint8 private _Cdecimals = 18;
    // 1B Supply
    uint256 private _CtotalSupply = 10**7 * 10**_Cdecimals;
    // 2% Max Wallet
    uint256 private _CmaxBalance = _CtotalSupply.mul(2).div(100);
    // 0.5% Max Transaction
    uint256 private _CmaxTx = _CtotalSupply.mul(5).div(1000);
    // 12% Max Fees
    uint8 private _CmaxFees = 15;
    // 2% Max Dev Fee
    uint8 private _CmaxDevFee = 1;
    // Contract sell at 3M tokens
    uint256 private _CliquifyThreshhold = 3 * 10**5 * 10**_Cdecimals;
    TokenDistribution private _CtokenDistribution = 
        TokenDistribution({ totalSupply: _CtotalSupply, decimals: _Cdecimals, maxBalance: _CmaxBalance, maxTx: _CmaxTx });

    // TODO VERY IMPORTANT! These are testnet wallets
    address payable _CdevAddress = payable(address(0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65));
    address payable _CmarketingAddress = payable(address(0x90F79bf6EB2c4f870365E785982E1f101E93b906));
    address payable _CteamAddress = payable(address(0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65));

    // Buy and sell fees will start at 99% to prevent bots/snipers at launch, 
    // but will not be allowed to be set this high ever again.
    constructor () 
    Owned(_msgSender())
    Taxable(_Csymbol, _Cname, _CtokenDistribution, _CdevAddress, _CmarketingAddress, _CteamAddress,
            Taxes({ devFee: 1, rewardsFee: 2, marketingFee: 31, teamFee: 5, liqFee: 60 }), 
            Taxes({ devFee: 1, rewardsFee: 2, marketingFee: 31, teamFee: 5, liqFee: 60 }), 
            _CmaxFees, _CmaxDevFee, _CliquifyThreshhold) {
        _balances[_msgSender()] = _totalSupply;
        emit Transfer(address(0), _msgSender(), _totalSupply);
    }
}