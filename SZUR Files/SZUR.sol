// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Changed interface name from ITRC20 to IERC20 for Polygon standard
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender,address recipient,uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner,address indexed spender,uint256 value);
}

contract SALZJYUR is IERC20 {
    string public name = "SALZJYUR";
    string public symbol = "SZUR";
    uint8 public decimals = 18;
    uint256 private _totalSupply = 100_000_000 * 10 ** decimals;
    // Cap increased to 200M to allow minting
    uint256 public constant MAX_CAP = 200_000_000 * 10 ** 18; 

    address public owner;
    // Min transfer 0 to avoid trapping funds
    uint256 public minTransfer = 0; 
    
    // ANTI-BOT: Mapping ensures individual timers
    mapping(address => uint256) public _lastTxTime; 
    uint256 public botDelay = 45; // 45 seconds delay

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // Anti-Whale
    uint256 public maxTxPercent = 5; // 0.5%
    uint256 public maxWalletPercent = 15; // 1.5%

    // Tax distribution (Total 1%)
    uint256 public burnRate = 10;      // 0.1%
    uint256 public liquidityRate = 45; // 0.45%
    uint256 public marketingRate = 45; // 0.45%
    uint256 public constant TAX_DENOM = 10000; 

    address public liquidityWallet;
    address public marketingWallet;

    mapping(address => bool) public isExcludedFromTax;
    mapping(address => bool) public isExcludedFromLimit;

    event Burn(address indexed from, uint256 amount);
    event Mint(address indexed to, uint256 amount);

    constructor(address _liquidityWallet, address _marketingWallet) {
        owner = msg.sender;
        liquidityWallet = _liquidityWallet;
        marketingWallet = _marketingWallet;

        _balances[owner] = _totalSupply;
        
        // Exclude owner and system wallets from Taxes AND Limits
        isExcludedFromTax[owner] = true;
        isExcludedFromTax[liquidityWallet] = true;
        isExcludedFromTax[marketingWallet] = true;
        isExcludedFromTax[address(this)] = true;

        isExcludedFromLimit[owner] = true;
        isExcludedFromLimit[liquidityWallet] = true;
        isExcludedFromLimit[marketingWallet] = true;
        isExcludedFromLimit[address(this)] = true;

        emit Transfer(address(0), owner, _totalSupply);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier antiBot(address from) {
        if(!isExcludedFromTax[from]) {
            require(block.timestamp >= _lastTxTime[from] + botDelay, "Anti-bot: please wait");
            _lastTxTime[from] = block.timestamp;
        }
        _;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) external override antiBot(msg.sender) returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner_, address spender) external view override returns (uint256) {
        return _allowances[owner_][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override antiBot(sender) returns (bool) {
        uint256 currentAllowance = _allowances[sender][msg.sender];
        require(currentAllowance >= amount, "Allowance exceeded");
        
        _allowances[sender][msg.sender] = currentAllowance - amount;
        _transfer(sender, recipient, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "Transfer from zero");
        require(to != address(0), "Transfer to zero");
        require(amount >= minTransfer, "Below min transfer");

        // Limits Check
        if(!isExcludedFromLimit[from] && !isExcludedFromLimit[to]) {
            uint256 maxTxAmount = (_totalSupply * maxTxPercent) / 1000;
            require(amount <= maxTxAmount, "Exceeds max tx");

            uint256 maxWallet = (_totalSupply * maxWalletPercent) / 1000;
            require(_balances[to] + amount <= maxWallet, "Exceeds max wallet");
        }

        uint256 taxAmount = 0;
        uint256 transferAmount = amount;

        if(!isExcludedFromTax[from] && !isExcludedFromTax[to]) {
            // Calculate taxes
            uint256 bAmount = (amount * burnRate) / TAX_DENOM;
            uint256 lAmount = (amount * liquidityRate) / TAX_DENOM;
            uint256 mAmount = (amount * marketingRate) / TAX_DENOM;
            
            taxAmount = bAmount + lAmount + mAmount;
            transferAmount = amount - taxAmount;

            // Burn
            if(bAmount > 0) {
                _totalSupply -= bAmount;
                emit Burn(from, bAmount);
                emit Transfer(from, address(0), bAmount);
            }

            // Liquidity
            if(lAmount > 0) {
                _balances[liquidityWallet] += lAmount;
                emit Transfer(from, liquidityWallet, lAmount);
            }

            // Marketing
            if(mAmount > 0) {
                _balances[marketingWallet] += mAmount;
                emit Transfer(from, marketingWallet, mAmount);
            }
        }

        require(_balances[from] >= amount, "Insufficient balance");
        _balances[from] -= amount;
        _balances[to] += transferAmount;
        
        emit Transfer(from, to, transferAmount);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        require(_totalSupply + amount <= MAX_CAP, "Exceeds Cap");
        _totalSupply += amount;
        _balances[to] += amount;
        emit Mint(to, amount);
        emit Transfer(address(0), to, amount);
    }

    function excludeFromTax(address account, bool excluded) external onlyOwner {
        isExcludedFromTax[account] = excluded;
    }
    
    function excludeFromLimit(address account, bool excluded) external onlyOwner {
        isExcludedFromLimit[account] = excluded;
    }

    function setMinTransfer(uint256 _amount) external onlyOwner {
        minTransfer = _amount;
    }

    function updateWallets(address _liquidity, address _marketing) external onlyOwner {
        liquidityWallet = _liquidity;
        marketingWallet = _marketing;
    }
    
    // Updated to IERC20 for Polygon
    function rescueToken(address tokenAddress, uint256 amount) external onlyOwner {
        IERC20(tokenAddress).transfer(owner, amount);
    }
}