// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./IUniswapV2.sol";

contract Token is IERC20, Ownable {
  using SafeMath for uint256;

  mapping(address => uint256) private _rOwned;
  mapping(address => uint256) private _tOwned;
  mapping(address => mapping(address => uint256)) private _allowances;

  mapping(address => bool) private _isExcludedFromFee;

  mapping(address => bool) private _isExcluded;
  address[] private _excluded;

  uint256 private constant MAX = ~uint256(0);

  uint256 private _tTotal = 100000000 * 10**18;
  uint256 private _rTotal = (MAX - (MAX % _tTotal));
  uint256 private _tFeeTotal;

  string private _name = "TOKEN";
  string private _symbol = "TKN";
  uint8 private _decimals = 18;

  address public developmentWallet = 0x0000000000000000000000000000000000000000; //change this address to an actual one
  address public burnAddress = 0x000000000000000000000000000000000000dEaD; //dead wallet

  uint256 public _devFee = 3;
  uint256 private _previosDevFee = _devFee;

  uint256 public _burnFee = 2;
  uint256 private _previosBurnFee = _burnFee;

  //BUY FEES
  uint256 public _buyReflectionFee = 2;
  uint256 private _previosBuyReflectionFee = _buyReflectionFee;

  uint256 public _buyLiquidityFee = 2;
  uint256 private _previosBuyLiquidityFee = _buyLiquidityFee;

  //SELL FEES
  uint256 public _sellReflectionFee = 3;
  uint256 private _previosSellReflectionFee = _sellReflectionFee;

  uint256 public _sellLiquidityFee = 3;
  uint256 private _previosSellLiquidityFee = _sellLiquidityFee;

  bool public feesRemovedForever = false;

  IUniswapV2Router02 public immutable uniswapV2Router;
  address public immutable uniswapV2Pair;

  bool inSwapAndLiquify;
  bool public swapAndLiquifyEnabled = true;

  uint256 public _maxTxAmount = 1000000 * 10**18; 
  uint256 private numTokensSellToAddToLiquidity = 10000 * 10**18;

  event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);
  event SwapAndLiquifyEnabledUpdated(bool enabled);
  event SwapAndLiquify(
    uint256 tokensSwapped,
    uint256 ethReceived,
    uint256 tokensIntoLiqudity
  );

  modifier lockTheSwap() {
    inSwapAndLiquify = true;
    _;
    inSwapAndLiquify = false;
  }

  constructor() {
    _rOwned[_msgSender()] = _rTotal;

    IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
      0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3 // pancakeswap v2 testnet
    );
    // Create a uniswap pair for this new token
    uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(
      address(this),
      _uniswapV2Router.WETH()
    );

    // set the rest of the contract variables
    uniswapV2Router = _uniswapV2Router;

    //exclude owner and this contract from fee
    _isExcludedFromFee[owner()] = true;
    _isExcludedFromFee[address(this)] = true;

    emit Transfer(address(0), _msgSender(), _tTotal);
  }

  function name() public view returns (string memory) {
    return _name;
  }

  function symbol() public view returns (string memory) {
    return _symbol;
  }

  function decimals() public view returns (uint8) {
    return _decimals;
  }

  function totalSupply() public view override returns (uint256) {
    return _tTotal;
  }

  function balanceOf(address account) public view override returns (uint256) {
    if (_isExcluded[account]) return _tOwned[account];
    return tokenFromReflection(_rOwned[account]);
  }

  function transfer(address recipient, uint256 amount)
    public
    override
    returns (bool)
  {
    _transfer(_msgSender(), recipient, amount);
    return true;
  }

  function allowance(address owner, address spender)
    public
    view
    override
    returns (uint256)
  {
    return _allowances[owner][spender];
  }

  function approve(address spender, uint256 amount)
    public
    override
    returns (bool)
  {
    _approve(_msgSender(), spender, amount);
    return true;
  }

  function transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) public override returns (bool) {
    _transfer(sender, recipient, amount);
    _approve(
      sender,
      _msgSender(),
      _allowances[sender][_msgSender()].sub(
        amount,
        "ERC20: transfer amount exceeds allowance"
      )
    );
    return true;
  }

  function increaseAllowance(address spender, uint256 addedValue)
    public
    virtual
    returns (bool)
  {
    _approve(
      _msgSender(),
      spender,
      _allowances[_msgSender()][spender].add(addedValue)
    );
    return true;
  }

  function decreaseAllowance(address spender, uint256 subtractedValue)
    public
    virtual
    returns (bool)
  {
    _approve(
      _msgSender(),
      spender,
      _allowances[_msgSender()][spender].sub(
        subtractedValue,
        "ERC20: decreased allowance below zero"
      )
    );
    return true;
  }

  function isExcludedFromReward(address account) public view returns (bool) {
    return _isExcluded[account];
  }

  function totalFees() public view returns (uint256) {
    return _tFeeTotal;
  }

  function deliver(uint256 tAmount) public {
    address sender = _msgSender();
    require(
      !_isExcluded[sender],
      "Excluded addresses cannot call this function"
    );
    uint256 rAmount = _getValues(tAmount, true)[0];
    _rOwned[sender] = _rOwned[sender].sub(rAmount);
    _rTotal = _rTotal.sub(rAmount);
    _tFeeTotal = _tFeeTotal.add(tAmount);
  }

  function reflectionFromToken(uint256 tAmount, bool deductTransferFee)
    public
    view
    returns (uint256)
  {
    require(tAmount <= _tTotal, "Amount must be less than supply");
    if (!deductTransferFee) {
      uint256 rAmount = _getValues(tAmount, true)[0];
      return rAmount;
    } else {
      uint256 rTransferAmount = _getValues(tAmount, true)[1];
      return rTransferAmount;
    }
  }

  function tokenFromReflection(uint256 rAmount) public view returns (uint256) {
    require(rAmount <= _rTotal, "Amount must be less than total reflections");
    uint256 currentRate = _getRate();
    return rAmount.div(currentRate);
  }

  function excludeFromReward(address account) public onlyOwner {
    // require(account != 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, 'We can not exclude Uniswap router.');
    require(!_isExcluded[account], "Account is already excluded");
    if (_rOwned[account] > 0) {
      _tOwned[account] = tokenFromReflection(_rOwned[account]);
    }
    _isExcluded[account] = true;
    _excluded.push(account);
  }

  function includeInReward(address account) external onlyOwner {
    require(_isExcluded[account], "Account is already excluded");
    for (uint256 i = 0; i < _excluded.length; i++) {
      if (_excluded[i] == account) {
        _excluded[i] = _excluded[_excluded.length - 1];
        _tOwned[account] = 0;
        _isExcluded[account] = false;
        _excluded.pop();
        break;
      }
    }
  }

  function _transferBothExcluded(
    address sender,
    address recipient,
    uint256 tAmount,
    bool isSell
  ) private {
    uint256[] memory values = _getValues(tAmount, isSell);

    _tOwned[sender] = _tOwned[sender].sub(tAmount);
    _rOwned[sender] = _rOwned[sender].sub(values[0]);
    _tOwned[recipient] = _tOwned[recipient].add(values[3]);
    _rOwned[recipient] = _rOwned[recipient].add(values[1]);
    _takeLiquidity(values[5]);
    _takeDevelopment(values[6]);
    _takeBurn(values[7]);
    _reflectFee(values[2], values[4]);
    emit Transfer(sender, recipient, values[3]);
  }

  function excludeFromFee(address account) public onlyOwner {
    _isExcludedFromFee[account] = true;
  }

  function includeInFee(address account) public onlyOwner {
    _isExcludedFromFee[account] = false;
  }

  function setMaxTxPercent(uint256 maxTxPercent) external onlyOwner {
    _maxTxAmount = _tTotal.mul(maxTxPercent).div(10**2);
  }

  function setSwapAndLiquifyEnabled(bool _enabled) public onlyOwner {
    swapAndLiquifyEnabled = _enabled;
    emit SwapAndLiquifyEnabledUpdated(_enabled);
  }

  //to recieve ETH from uniswapV2Router when swaping
  receive() external payable {}

  function _reflectFee(uint256 rFee, uint256 tFee) private {
    _rTotal = _rTotal.sub(rFee);
    _tFeeTotal = _tFeeTotal.add(tFee);
  }

  function _getValues(uint256 tAmount, bool isSell)
    private
    view
    returns (uint256[] memory)
  {
    (
      uint256 tTransferAmount,
      uint256 tFee,
      uint256 tLiquidity,
      uint256 tDev,
      uint256 tBurn
    ) = _getTValues(tAmount, isSell);

    (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(
      tAmount,
      tFee,
      tLiquidity,
      tDev,
      tBurn,
      _getRate()
    );

    uint256[] memory returnArry = new uint256[](8);
    returnArry[0] = rAmount;
    returnArry[1] = rTransferAmount;
    returnArry[2] = rFee;
    returnArry[3] = tTransferAmount;
    returnArry[4] = tFee;
    returnArry[5] = tLiquidity;
    returnArry[6] = tDev;
    returnArry[7] = tBurn;

    return returnArry;
  }

  function _getTValues(uint256 tAmount, bool isSell)
    private
    view
    returns (
      uint256,
      uint256,
      uint256,
      uint256,
      uint256
    )
  {
    uint256 tFee = calculateTaxFee(tAmount, isSell);
    uint256 tLiquidity = calculateLiquidityFee(tAmount, isSell);
    uint256 tDev = calculateDevFee(tAmount);
    uint256 tBurn = calculateBurnFee(tAmount);
    uint256 totalFee = tFee + tLiquidity + tDev + tBurn;
    uint256 tTransferAmount = tAmount.sub(totalFee);
    return (tTransferAmount, tFee, tLiquidity, tDev, tBurn);
  }

  function _getRValues(
    uint256 tAmount,
    uint256 tFee,
    uint256 tLiquidity,
    uint256 tDev,
    uint256 tBurn,
    uint256 currentRate
  )
    private
    pure
    returns (
      uint256,
      uint256,
      uint256
    )
  {
    uint256 rAmount = tAmount.mul(currentRate);
    uint256 rFee = tFee.mul(currentRate);
    uint256 rLiquidity = tLiquidity.mul(currentRate);
    uint256 rDev = tDev.mul(currentRate);
    uint256 rBurn = tBurn.mul(currentRate);
    uint256 rTransferAmount = rAmount.sub(rFee).sub(rLiquidity).sub(rDev).sub(
      rBurn
    );
    return (rAmount, rTransferAmount, rFee);
  }

  function _getRate() private view returns (uint256) {
    (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
    return rSupply.div(tSupply);
  }

  function _getCurrentSupply() private view returns (uint256, uint256) {
    uint256 rSupply = _rTotal;
    uint256 tSupply = _tTotal;
    for (uint256 i = 0; i < _excluded.length; i++) {
      if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply)
        return (_rTotal, _tTotal);
      rSupply = rSupply.sub(_rOwned[_excluded[i]]);
      tSupply = tSupply.sub(_tOwned[_excluded[i]]);
    }
    if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
    return (rSupply, tSupply);
  }

  function _takeLiquidity(uint256 tLiquidity) private {
    uint256 currentRate = _getRate();
    uint256 rLiquidity = tLiquidity.mul(currentRate);
    _rOwned[address(this)] = _rOwned[address(this)].add(rLiquidity);
    if (_isExcluded[address(this)])
      _tOwned[address(this)] = _tOwned[address(this)].add(tLiquidity);
  }

  function _takeDevelopment(uint256 tDev) private {
    uint256 currentRate = _getRate();
    uint256 rDev = tDev.mul(currentRate);
    _rOwned[developmentWallet] = _rOwned[developmentWallet].add(rDev);
    if (_isExcluded[developmentWallet])
      _tOwned[developmentWallet] = _tOwned[developmentWallet].add(tDev);
  }

  function _takeBurn(uint256 tBurn) private {
    uint256 currentRate = _getRate();
    uint256 rBurn = tBurn.mul(currentRate);
    _rOwned[burnAddress] = _rOwned[burnAddress].add(rBurn);
    if (_isExcluded[burnAddress])
      _tOwned[burnAddress] = _tOwned[burnAddress].add(tBurn);
  }

  function calculateTaxFee(uint256 _amount, bool _isSell)
    private
    view
    returns (uint256)
  {
    uint256 fee = _isSell ? _sellLiquidityFee : _buyLiquidityFee;
    return _amount.mul(fee).div(10**2);
  }

  function calculateLiquidityFee(uint256 _amount, bool _isSell)
    private
    view
    returns (uint256)
  {
    uint256 fee = _isSell ? _sellLiquidityFee : _buyLiquidityFee;
    return _amount.mul(fee).div(10**2);
  }

  function calculateDevFee(uint256 _amount) private view returns (uint256) {
    return _amount.mul(_devFee).div(10**2);
  }

  function calculateBurnFee(uint256 _amount) private view returns (uint256) {
    return _amount.mul(_burnFee).div(10**2);
  }

  function removeAllFee() private {
    _previosBuyReflectionFee = _buyReflectionFee;
    _previosBuyLiquidityFee = _buyLiquidityFee;
    _previosSellReflectionFee = _sellReflectionFee;
    _previosSellLiquidityFee = _sellLiquidityFee;
    _previosDevFee = _devFee;
    _previosBurnFee = _burnFee;

    _buyReflectionFee = 0;
    _buyLiquidityFee = 0;
    _sellLiquidityFee = 0;
    _sellLiquidityFee = 0;
    _devFee = 0;
    _burnFee = 0;
  }

  function restoreAllFee() private {
    require(!feesRemovedForever, "YOU_CANT_CHANGE_FEE");

    _buyReflectionFee = _previosBuyReflectionFee;
    _buyLiquidityFee = _previosBuyLiquidityFee;
    _sellReflectionFee = _previosSellReflectionFee;
    _sellLiquidityFee = _previosSellLiquidityFee;
    _devFee = _previosDevFee;
    _burnFee = _previosBurnFee;
  }

  function isExcludedFromFee(address account) public view returns (bool) {
    return _isExcludedFromFee[account];
  }

  function _approve(
    address owner,
    address spender,
    uint256 amount
  ) private {
    require(owner != address(0), "ERC20: approve from the zero address");
    require(spender != address(0), "ERC20: approve to the zero address");

    _allowances[owner][spender] = amount;
    emit Approval(owner, spender, amount);
  }

  function _transfer(
    address from,
    address to,
    uint256 amount
  ) private {
    require(from != address(0), "ERC20: transfer from the zero address");
    require(to != address(0), "ERC20: transfer to the zero address");
    require(amount > 0, "Transfer amount must be greater than zero");
    if (from != owner() && to != owner())
      require(
        amount <= _maxTxAmount,
        "Transfer amount exceeds the maxTxAmount."
      );

    // is the token balance of this contract address over the min number of
    // tokens that we need to initiate a swap + liquidity lock?
    // also, don't get caught in a circular liquidity event.
    // also, don't swap & liquify if sender is uniswap pair.
    uint256 contractTokenBalance = balanceOf(address(this));

    if (contractTokenBalance >= _maxTxAmount) {
      contractTokenBalance = _maxTxAmount;
    }

    bool overMinTokenBalance = contractTokenBalance >=
      numTokensSellToAddToLiquidity;
    if (
      overMinTokenBalance &&
      !inSwapAndLiquify &&
      from != uniswapV2Pair &&
      swapAndLiquifyEnabled
    ) {
      contractTokenBalance = numTokensSellToAddToLiquidity;
      //add liquidity
      swapAndLiquify(contractTokenBalance);
    }

    //indicates if fee should be deducted from transfer
    bool takeFee = true;

    //if any account belongs to _isExcludedFromFee account then remove the fee
    if (_isExcludedFromFee[from] || _isExcludedFromFee[to]) {
      takeFee = false;
    }

    bool isSell = from != uniswapV2Pair ? true : false;

    //transfer amount, it will take tax, burn, liquidity fee
    _tokenTransfer(from, to, amount, takeFee, isSell);
  }

  function swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
    // split the contract balance into halves
    uint256 half = contractTokenBalance.div(2);
    uint256 otherHalf = contractTokenBalance.sub(half);

    // capture the contract's current ETH balance.
    // this is so that we can capture exactly the amount of ETH that the
    // swap creates, and not make the liquidity event include any ETH that
    // has been manually sent to the contract
    uint256 initialBalance = address(this).balance;

    // swap tokens for ETH
    swapTokensForEth(half); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

    // how much ETH did we just swap into?
    uint256 newBalance = address(this).balance.sub(initialBalance);

    // add liquidity to uniswap
    addLiquidity(otherHalf, newBalance);

    emit SwapAndLiquify(half, newBalance, otherHalf);
  }

  function swapTokensForEth(uint256 tokenAmount) private {
    // generate the uniswap pair path of token -> weth
    address[] memory path = new address[](2);
    path[0] = address(this);
    path[1] = uniswapV2Router.WETH();

    _approve(address(this), address(uniswapV2Router), tokenAmount);

    // make the swap
    uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
      tokenAmount,
      0, // accept any amount of ETH
      path,
      address(this),
      block.timestamp
    );
  }

  function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
    // approve token transfer to cover all possible scenarios
    _approve(address(this), address(uniswapV2Router), tokenAmount);

    // add the liquidity
    uniswapV2Router.addLiquidityETH{ value: ethAmount }(
      address(this),
      tokenAmount,
      0, // slippage is unavoidable
      0, // slippage is unavoidable
      owner(),
      block.timestamp
    );
  }

  //this method is responsible for taking all fee, if takeFee is true
  function _tokenTransfer(
    address sender,
    address recipient,
    uint256 amount,
    bool takeFee,
    bool isSell
  ) private {
    if (!takeFee && !feesRemovedForever) removeAllFee();

    if (_isExcluded[sender] && !_isExcluded[recipient]) {
      _transferFromExcluded(sender, recipient, amount, isSell);
    } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
      _transferToExcluded(sender, recipient, amount, isSell);
    } else if (!_isExcluded[sender] && !_isExcluded[recipient]) {
      _transferStandard(sender, recipient, amount, isSell);
    } else if (_isExcluded[sender] && _isExcluded[recipient]) {
      _transferBothExcluded(sender, recipient, amount, isSell);
    } else {
      _transferStandard(sender, recipient, amount, isSell);
    }

    if (!takeFee && !feesRemovedForever) restoreAllFee();
  }

  function _transferStandard(
    address sender,
    address recipient,
    uint256 tAmount,
    bool isSell
  ) private {
    uint256[] memory values = _getValues(tAmount, isSell);

    _rOwned[sender] = _rOwned[sender].sub(values[0]);
    _rOwned[recipient] = _rOwned[recipient].add(values[1]);
    _takeLiquidity(values[5]);
    _takeDevelopment(values[6]);
    _takeBurn(values[7]);
    _reflectFee(values[2], values[4]);
    emit Transfer(sender, recipient, values[3]);
  }

  function _transferToExcluded(
    address sender,
    address recipient,
    uint256 tAmount,
    bool isSell
  ) private {
    uint256[] memory values = _getValues(tAmount, isSell);

    _rOwned[sender] = _rOwned[sender].sub(values[0]);
    _tOwned[recipient] = _tOwned[recipient].add(values[3]);
    _rOwned[recipient] = _rOwned[recipient].add(values[1]);
    _takeLiquidity(values[5]);
    _takeDevelopment(values[6]);
    _takeBurn(values[7]);
    _reflectFee(values[2], values[4]);
    emit Transfer(sender, recipient, values[3]);
  }

  function _transferFromExcluded(
    address sender,
    address recipient,
    uint256 tAmount,
    bool isSell
  ) private {
    uint256[] memory values = _getValues(tAmount, isSell);

    _tOwned[sender] = _tOwned[sender].sub(tAmount);
    _rOwned[sender] = _rOwned[sender].sub(values[0]);
    _rOwned[recipient] = _rOwned[recipient].add(values[1]);
    _takeLiquidity(values[5]);
    _takeDevelopment(values[6]);
    _takeBurn(values[7]);
    _reflectFee(values[2], values[4]);
    emit Transfer(sender, recipient, values[3]);
  }

  function setDevWallet(address _newDevWallet) external onlyOwner {
    developmentWallet = _newDevWallet;
  }

  function setDevFee(uint256 _fee) external onlyOwner {
    require(!feesRemovedForever, "YOU_CANT_CHANGE_FEE");
    _devFee = _fee;
  }

  function setBurnFee(uint256 _fee) external onlyOwner {
    require(!feesRemovedForever, "YOU_CANT_CHANGE_FEE");
    _burnFee = _fee;
  }

  function setBuyReflectionFee(uint256 _fee) external onlyOwner {
    require(!feesRemovedForever, "YOU_CANT_CHANGE_FEE");
    _buyReflectionFee = _fee;
  }

  function setSellReflectionFee(uint256 _fee) external onlyOwner {
    require(!feesRemovedForever, "YOU_CANT_CHANGE_FEE");
    _sellReflectionFee = _fee;
  }

  function setBuyLiquidityFee(uint256 _fee) external onlyOwner {
    require(!feesRemovedForever, "YOU_CANT_CHANGE_FEE");
    _buyLiquidityFee = _fee;
  }

  function setSellLiquidityFee(uint256 _fee) external onlyOwner {
    require(!feesRemovedForever, "YOU_CANT_CHANGE_FEE");
    _sellLiquidityFee = _fee;
  }

  function removeFeesForever() external onlyOwner {
    if (feesRemovedForever) return;

    feesRemovedForever = true;

    removeAllFee();
    setSwapAndLiquifyEnabled(false);
  }
}
