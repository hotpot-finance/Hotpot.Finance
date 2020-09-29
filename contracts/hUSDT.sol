//SPDX-License-Identifier: Unlicense
pragma solidity ^0.6.0;

import "./IERC20.sol";
import "./ERC20.sol";
import "./Address.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";

contract hUSDT is ERC20, ERC20Detailed {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    IERC20 public underlyingToken;

    // Roles
    address public admin;

    // Cefi token
    uint256 public totalSupplyCefiToken;
    mapping(address => uint256) public CefiBalances;
    event TransferCefi(address indexed from, address indexed to, uint value);

    // Contract(Fund) Status
    // 0: not initialized
    // 1: funding
    // 2: running
    uint256 public fundStatus;

    // Fund Parameters
    uint256 public fundingEndTime;  // Time when funding ends
    uint256 public runningEndTime;  // Time when (fund) running ends
    uint256 public percentageOffchainFund;  // percentage of fund that will be transfered off-chain

    // Events
    event DepositCefi(address indexed investor, uint256 investAmount, uint256 mintedAmount);
    event StartFund(uint256 timeStamp, uint256 totalMintedDefiTokenAmount, uint256 totalMintedCefiTokenAmount);
    event WithdrawCefi(address indexed investor, uint256 tokenAmount, uint256 USDTAmount);
    event FundRestart(uint256 timeStamp);
    // Admin Events

    // Modifiers
    modifier funding() {
        require(fundStatus == 1, "Only when fund is in funding status");
        _;
    }

    modifier running() {
        require(fundStatus == 2, "Only when fund is in running status");
        _;
    }

    modifier isAdmin() {
        require(msg.sender == admin, "Only admin can call");
        _;
    }


    // Getter Functions

    // Get the Cefi balance of an investor
    function getCefiBalanceValue(address investor) public view returns(uint256) {
        uint256 accruedRatio = oracle.query();
        return _balances[investor].mul(accruedRatio).div(baseRatio);
    }

    // Added ERC20 functions for Cefi token
    function _mintCefiToken(address account, uint amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        totalSupplyCefiToken = totalSupplyCefiToken.add(amount);
        CefiBalances[account] = CefiBalances[account].add(amount);
        emit TransferCefi(address(0), account, amount);
    }

    function _burnCefiToken(address account, uint amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");

        CefiBalances[account] = CefiBalances[account].sub(amount, "ERC20: burn amount exceeds balance");
        totalSupplyCefiToken = totalSupplyCefiToken.sub(amount);
        emit TransferCefi(account, address(0), amount);
    }


    function deposit(uint256 depositUSDTAmount) funding public {
        require(msg.sender != admin, "Investor can not be admin");
        require(depositUSDTAmount > 0, "Deposited token amount should be greater than zero");

        uint256 toCefiAmount = depositUSDTAmount.mul(percentageOffchainFund).div(100);

        // Transfer underlying token to this contract
        underlyingToken.safeTransferFrom(msg.sender, address(this), depositUSDTAmount);

        uint256 mintedCefiTokenAmount = toCefiAmount;
        _mintCefiToken(msg.sender, mintedCefiTokenAmount);

        emit DepositCefi(msg.sender, toCefiAmount, mintedCefiTokenAmount);
    }

    // Start Investing
    // Send part of the funds offline
    // and calculate the minimum amount of fund needed to keep the fund functioning
    function start() funding isAdmin public {
        require(block.timestamp >= fundingEndTime, "Can only start when funding ends");

        uint256 expectedUnderlyingTokenAmount = totalSupplyCefiToken.mul(percentageOffchainFund).div(100);
        underlyingToken.safeTransfer(admin, expectedUnderlyingTokenAmount);

        // Start the contract
        fundStatus = 2;
        emit StartFund(now, totalSupply(), totalSupplyCefiToken);
    }

    function withdraw(uint256 CefiTokenAmount, uint32 distEventId) public {
        require(CefiBalances[msg.sender] >= CefiTokenAmount, "Not enough Cefi token to be withdrawn");

        uint256 amountUSDTForInvestor;// Can only withdraw from Cefi during funding phase
        if (fundStatus == 1 && CefiTokenAmount > 0) {
            // Query Oracle for current ratio
            uint256 CefiUSDTAmount = CefiTokenAmount;

            _burnCefiToken(msg.sender, CefiTokenAmount);
            emit WithdrawCefi(msg.sender, CefiTokenAmount, CefiUSDTAmount);
            amountUSDTForInvestor = amountUSDTForInvestor.add(CefiUSDTAmount);
        }

        underlyingToken.safeTransfer(msg.sender, amountUSDTForInvestor);
    }

    function returnCefiFundAndRestart(
        uint256 returnAmount,
        uint256 _fundingDuration,
        uint256 _runningDuration,
        uint256 _percentageOffchainFund) running isAdmin public {
        require(block.timestamp >= runningEndTime, "Can only restart when running ends");

        // Transfer underlying token to this contract
        underlyingToken.safeTransferFrom(admin, address(this), returnAmount);

        // Reset parameters
        fundingEndTime = block.timestamp.add(_fundingDuration);
        runningEndTime = fundingEndTime.add(_runningDuration);
        percentageOffchainFund = _percentageOffchainFund;

        fundStatus = 1;
        emit FundRestart(block.timestamp);
    }

    function claimWronglyTransferredToken(IERC20 _token) isAdmin public {
        require(address(_token) != address(underlyingToken), "Can not claim underlying token");

        uint256 leftOverAmount = _token.balanceOf(address(this));
        if(leftOverAmount > 0) {
            underlyingToken.safeTransfer(admin, leftOverAmount);
        }
    }

    constructor(
        address _underlyingToken,
        address _admin,
        uint256 _fundingDuration,
        uint256 _runningDuration,
        uint256 _percentageOffchainFund) ERC20Detailed("hToken-USDT", "hUSDT", 6) public {

        admin = _admin;
        underlyingToken = IERC20(_underlyingToken);

        // Set parameters
        fundingEndTime = block.timestamp.add(_fundingDuration);
        runningEndTime = fundingEndTime.add(_runningDuration);
        percentageOffchainFund = _percentageOffchainFund;

        // Initialized the contract
        fundStatus = 1;
    }
}
