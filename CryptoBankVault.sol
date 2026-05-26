// SPDX-License-Identifier: GPL-3.0-only

// Solidity Version
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
/**
 * @title CryptoBankVault
 * @notice A vault contract that allows users to deposit ETH, receive shares
 *         proportional to their deposit, and earn ERC20 token rewards over time.
 * @dev Inherits ReentrancyGuard, Pausable, and Ownable from OpenZeppelin.
 */
contract CryptoBankVault is ReentrancyGuard, Pausable, Ownable {

    // State Variables
    // @notice Maximum ETH balance any single user is allowed to hold in the vault.
    uint256 public maxBalance;

    // @notice ETH balance deposited by each user.
    mapping(address => uint256) public userBalance;

    // @notice Total ETH held in the vault across all users.
    uint256 public totalBalance;

    // @notice Total shares issued across all users.
    uint256 public totalShare;

    // @notice ERC20 token distributed as staking rewards.
    IERC20 public rewardToken;

    // @notice Timestamp of the last deposit (or reward claim) for each user.
    //         Used to calculate time-weighted rewards.
    mapping(address => uint256) public depositTimestamp;

    // @notice Number of vault shares owned by each user.
    mapping(address => uint256) public userShares;

    // @notice Reward tokens emitted per share per second (scaled by 1e18).
    ///        Default: 1e10 — adjust to match the token's decimals and desired emission rate.
    uint256 public rewardRate = 1e10;

    // Events
    // @notice Emitted when a user deposits ETH into the vault.
    event EtherDeposit(address indexed user, uint256 amount);

    // @notice Emitted when a user withdraws ETH from the vault.
    event EtherWithdraw(address indexed user, uint256 amount);

    // @notice Emitted when a user claims their pending rewards.
    event RewardClaimed(address indexed user, uint256 reward);

    // @notice Emitted when the owner performs an emergency withdrawal.
    event EmergencyWithdraw(address indexed user, uint256 amount);

    // Constructor
    /**
     * @param maxBalance_   Maximum ETH balance allowed per user.
     * @param admin_        Address that will be set as the contract owner.
     * @param rewardToken_  Address of the ERC20 token used for rewards.
     */
    constructor(uint256 maxBalance_, address admin_, address rewardToken_) Ownable(admin_) {
        require(admin_ != address(0), "Invalid admin address");
        require(rewardToken_ != address(0), "Invalid token address");

        maxBalance  = maxBalance_;
        rewardToken = IERC20(rewardToken_);
        // Transfer ownership to the designated admin instead of leaving it with the deployer.
        transferOwnership(admin_);
    }

    // Internal Helpers
    /**
     * @notice Converts an ETH amount (assets) into vault shares.
     * @dev    On first deposit (totalBalance == 0 || totalShare == 0) shares equal assets 1:1.
     * @param  assets_ Amount of ETH to convert.
     * @return Equivalent number of shares.
     */
    function convertToShares(uint256 assets_) internal view returns (uint256) {
        if (totalBalance == 0 || totalShare == 0) {
            return assets_;
        }
        return (assets_ * totalShare) / totalBalance;
    }

    /**
     * @notice Converts vault shares back into an ETH amount (assets).
     * @dev    Inverse of convertToShares. Uses totalBalance/totalShare ratio.
     *         BUG FIX: previous version incorrectly used totalShare/totalBalance.
     * @param  shares_ Number of shares to convert.
     * @return Equivalent ETH amount.
     */
    function convertToAssets(uint256 shares_) internal view returns (uint256) {
        if (totalBalance == 0 || totalShare == 0) {
            return shares_;
        }
        return (shares_ * totalBalance) / totalShare; // fixed: was totalShare/totalBalance
    }

    // External Functions
    /**
     * @notice Deposit ETH into the vault and receive shares in return.
     * @dev    Reverts if the deposit would push the caller's balance above `maxBalance`.
     *         Protected by `whenNotPaused` so the owner can halt deposits if needed.
     */
    function depositEther() external payable whenNotPaused nonReentrant {
        require(msg.value > 0, "Deposit must be greater than zero");
        require(
            userBalance[msg.sender] + msg.value <= maxBalance,
            "MaxBalance reached"
        );

        uint256 shares = convertToShares(msg.value);

        // Update accounting before any external calls (checks-effects-interactions).
        userBalance[msg.sender] += msg.value;
        totalBalance            += msg.value;
        totalShare              += shares;
        userShares[msg.sender]  += shares;

        // Record the deposit time; used as the reward accrual start point.
        depositTimestamp[msg.sender] = block.timestamp;

        emit EtherDeposit(msg.sender, msg.value);
    }

    /**
     * @notice Withdraw ETH from the vault by redeeming shares.
     * @dev    Follows checks-effects-interactions pattern to prevent reentrancy.
     *         `nonReentrant` added as an extra safety net.
     * @param  amount_ Amount of ETH to withdraw.
     */
    function withdrawEther(uint256 amount_) external whenNotPaused nonReentrant {
        require(amount_ > 0, "Amount must be greater than zero");
        require(userBalance[msg.sender] >= amount_, "Insufficient balance");

        uint256 shares = convertToShares(amount_);

        // BUG FIX: state must be updated BEFORE the external ETH transfer
        // to prevent reentrancy (checks-effects-interactions).
        userBalance[msg.sender] -= amount_;
        totalBalance            -= amount_;
        totalShare              -= shares;
        userShares[msg.sender]  -= shares;

        (bool success, ) = msg.sender.call{value: amount_}("");
        require(success, "ETH transfer failed");

        emit EtherWithdraw(msg.sender, amount_);
    }

    /**
     * @notice Update the maximum ETH balance allowed per user.
     * @dev    Only callable by the contract owner.
     * @param  newMaxBalance_ New cap in wei.
     */
    function modifyMaxBalance(uint256 newMaxBalance_) external onlyOwner {
        maxBalance = newMaxBalance_;
    }

    /**
     * @notice Returns the total ETH currently held in the vault.
     * @return Total vault balance in wei.
     */
    function getTotalBalance() external view returns (uint256) {
        return totalBalance;
    }

    /**
     * @notice Claim accumulated ERC20 reward tokens.
     * @dev    Rewards = userShares * timeElapsed * rewardRate / 1e18.
     *         The timestamp is reset after each claim to avoid double-counting.
     */
    function claimReward() external nonReentrant {
        uint256 shares = userShares[msg.sender];
        require(shares > 0, "No shares to claim rewards for");

        uint256 timeElapsed = block.timestamp - depositTimestamp[msg.sender];
        require(timeElapsed > 0, "No time has passed since last claim");

        // BUG FIX: divide by 1e18 to normalise the reward rate scaling factor.
        uint256 reward = (shares * timeElapsed * rewardRate) / 1e18;
        require(reward > 0, "Reward too small");

        // Reset timestamp before transferring to follow checks-effects-interactions.
        depositTimestamp[msg.sender] = block.timestamp;

        require(rewardToken.transfer(msg.sender, reward), "Reward transfer failed");

        emit RewardClaimed(msg.sender, reward);
    }

    /**
     * @notice Preview the pending reward for a given user without modifying state.
     * @param  user_ Address of the user to preview.
     * @return Pending reward amount in reward token units.
     */
    function previewRewards(address user_) external view returns (uint256) {
        uint256 shares = userShares[user_];
        if (shares == 0) return 0;
        uint256 timeElapsed = block.timestamp - depositTimestamp[user_];
        return (shares * timeElapsed * rewardRate) / 1e18; // matches claimReward logic
    }

    /**
     * @notice Pause deposits and withdrawals in case of emergency.
     * @dev    Only callable by the contract owner.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Resume normal operations after a pause.
     * @dev    Only callable by the contract owner.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency withdrawal: lets ANY user exit with their full ETH balance,
     *         skipping reward accrual. Works even when the contract is paused.
     * @dev    BUG FIX: was restricted to `onlyOwner`, making it useless for regular users.
     *         Shares are burned and balances zeroed before the ETH transfer (CEI pattern).
     */
    function emergencyWithdraw() external nonReentrant {
        uint256 amount = userBalance[msg.sender];
        require(amount > 0, "Nothing to withdraw");

        // Compute shares to burn based on current ratio.
        uint256 shares = convertToShares(amount);

        // Zero out user state before external call.
        userBalance[msg.sender] = 0;
        userShares[msg.sender]  = 0;

        totalBalance -= amount;
        totalShare   -= shares;

        // No rewards paid out during an emergency exit.
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "ETH transfer failed");

        emit EmergencyWithdraw(msg.sender, amount);
    }

    /**
     * @notice Update the reward emission rate.
     * @dev    Only callable by the owner. Rate is expressed as tokens per share
     *         per second, scaled by 1e18.
     * @param  newRate_ New reward rate.
     */
    function setRewardRate(uint256 newRate_) external onlyOwner {
        rewardRate = newRate_;
    }
}
