// SPDX-License-Identifier: MIT

/**
    Tradable.sol

    A contract designed to simplify creating a DEX-tradable token,
    with an adjustable max wallet and max transaction amount.
*/

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./DividendDistributor.sol";
import "./IDEXFactory.sol";
import "./IDEXRouter.sol";
import "../Utils/Owned.sol";

abstract contract Tradable is IERC20, Owned {
    using SafeMath for uint256;

    struct TokenDistribution {
        uint256 totalSupply;
        uint8 decimals;
        uint256 maxBalance;
        uint256 maxTx;
    }

    uint256 public _totalSupply;
    uint8 public _decimals;
    string public _symbol;
    string public _name;
    uint256 public _maxBalance;
    uint256 public _maxTx;
    //
    IDEXRouter public router;
    address public pair;
    //
    DividendDistributor public distributor;
    uint256 distributorGas = 500000;
    //
    mapping (address => uint256) public _balances;
    //
    mapping (address => mapping (address => uint256)) public _allowances;
    //
    mapping (address => bool) public _isDividendExempt;
    //
    mapping (address => bool) public _isExcludedFromMaxBalance;
    //
    mapping (address => bool) public _isExcludedFromMaxTx;

    constructor(string memory tokenSymbol, string memory tokenName, TokenDistribution memory tokenDistribution) {
        _totalSupply = tokenDistribution.totalSupply;
        _decimals = tokenDistribution.decimals;
        _symbol = tokenSymbol;
        _name = tokenName;
        _maxBalance = tokenDistribution.maxBalance;
        _maxTx = tokenDistribution.maxTx;

        // router = IDEXRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E); //Mainnet
        router = IDEXRouter(0xD99D1c33F9fC3444f8101754aBC46c52416550D1); //Testnet 
        pair = IDEXFactory(router.factory()).createPair(router.WETH(), address(this)); // Create a uniswap pair for this new token

        distributor = new DividendDistributor(address(router));

        _isDividendExempt[pair] = true;
        _isDividendExempt[address(this)] = true;

        _isExcludedFromMaxBalance[owner] = true;
        _isExcludedFromMaxBalance[address(this)] = true;
        _isExcludedFromMaxBalance[pair] = true;

        _isExcludedFromMaxTx[owner] = true;
        _isExcludedFromMaxTx[address(this)] = true;
    }

    // To recieve BNB from anyone, including the router when swapping
    receive() external payable {}

    // If you need to withdraw BNB, tokens, or anything else that's been sent to the contract
    function withdrawToken(address _tokenContract, uint256 _amount) external onlyOwner {
        IERC20 tokenContract = IERC20(_tokenContract);
        
        // transfer the token from address of this contract
        // to address of the user (executing the withdrawToken() function)
        tokenContract.transfer(msg.sender, _amount);
    }

    // If PancakeSwap sets a new iteration on their router and we need to migrate where LP
    // goes, change it here!
    function setNewPair(address newPairAddress) external onlyOwner {
        require(newPairAddress != pair);
        pair = newPairAddress;
        _isExcludedFromMaxBalance[pair] = true;
    }

    // If PancakeSwap sets a new iteration on their router, change it here!
    function setNewRouter(address newAddress) external onlyOwner {
        require(newAddress != address(router));
        router = IDEXRouter(newAddress);
    }

    function setMaxBalancePercentage(uint256 newMaxBalancePercentage) external onlyOwner() {
        uint256 newMaxBalance = _totalSupply.mul(newMaxBalancePercentage).div(100);

        require(newMaxBalance != _maxBalance, "Cannot set new max balance to the same value as current max balance");
        require(newMaxBalance >= _totalSupply.mul(2).div(100), "Cannot set max balance lower than 2 percent");

        _maxBalance = newMaxBalance;
    }

    // Set the max transaction percentage in increments of 0.1%.
    function setMaxTxPercentage(uint256 newMaxTxPercentage) external onlyOwner {
        uint256 newMaxTx = _totalSupply.mul(newMaxTxPercentage).div(1000);

        require(newMaxTx != _maxTx, "Cannot set new max transaction to the same value as current max transaction");
        require(newMaxTx >= _totalSupply.mul(5).div(1000), "Cannot set max transaction lower than 0.5 percent");

        _maxTx = newMaxTx;
    }

    function includeInMaxBalance(address account) public onlyOwner {
        _isExcludedFromMaxBalance[account] = false;
    }

    function excludeFromMaxBalance(address account) public onlyOwner {
        _isExcludedFromMaxBalance[account] = true;
    }

    function includeInMaxTx(address account) public onlyOwner {
        _isExcludedFromMaxTx[account] = false;
    }

    function excludeFromMaxTx(address account) public onlyOwner {
        _isExcludedFromMaxTx[account] = true;
    }

    function setIsDividendExempt(address holder, bool exempt) external onlyOwner {
        require(holder != address(this) && holder != pair);
        _isDividendExempt[holder] = exempt;
        if(exempt){
            distributor.setShare(holder, 0);
        }else{
            distributor.setShare(holder, balanceOf(holder));
        }
    }

    function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution) external onlyOwner {
        distributor.setDistributionCriteria(_minPeriod, _minDistribution);
    }

    function setDistributorSettings(uint256 gas) external onlyOwner {
        require(gas < 900000);
        distributorGas = gas;
    }

    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function decimals() external view returns (uint8) { return _decimals; }
    function symbol() external view returns (string memory) { return _symbol; }
    function name() external view returns (string memory) { return _name; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function allowance(address owner, address spender) external view override returns (uint256) { return _allowances[owner][spender]; }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function approveFromOwner(address owner, address spender, uint256 amount) public returns (bool) {
        _approve(owner, spender, amount);
        return true;
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    function _approve(address holder, address spender, uint256 amount) private {
        require(holder != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[holder][spender] = amount;
        emit Approval(holder, spender, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        if(!(_isExcludedFromMaxTx[from] || _isExcludedFromMaxTx[to])) {
            require(amount < _maxTx, "Transfer amount exceeds limit");
        }

        if(
            from != owner &&              // Not from Owner
            to != owner &&                // Not to Owner
            !_isExcludedFromMaxBalance[to]  // is excludedFromMaxBalance
        ) {
            require(balanceOf(to).add(amount) <= _maxBalance, "Tx would cause recipient to exceed max balance");
        }

        _balances[from] = _balances[from].sub(amount, "ERC20: transfer amount exceeds balance");
        _balances[to] = _balances[to].add(amount);

        // Dividend tracker
        if(!_isDividendExempt[from]) {
            try distributor.setShare(from, balanceOf(from)) {} catch {}
        }

        if(!_isDividendExempt[to]) {
            try distributor.setShare(to, balanceOf(to)) {} catch {} 
        }

        try distributor.process(distributorGas) {} catch {}

        emit Transfer(from, to, amount);
    }
}