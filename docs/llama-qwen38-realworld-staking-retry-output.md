<think>
The user wants me to write a Solidity staking contract and a TypeScript test suite. The reference context is unrelated C++ code (llama.cpp adapter code), which I should ignore as stated.

Let me design a reasonable staking contract with common features:
- Stake tokens
- Unstake tokens
- Earn rewards based on staking duration
- Admin controls
- Then write a comprehensive TypeScript test suite using Hardhat/Foundry style (I'll go with Hardhat + ethers.js as it's more common)

Let me write a staking contract that:
1. Allows users to stake ERC20 tokens
2. Tracks staking periods
3. Distributes rewards proportionally to staking time
4. Allows unstaking
5. Has admin functions for rewards

I'll write a clean, well-structured contract and a thorough test suite.
</think>

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract StakingContract is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- Structs ---
    struct StakeInfo {
        uint256 amount;        // staked amount
        uint256 timestamp;     // when staked
        uint256 rewardDebt;    // accumulated reward debt
    }

    // --- State ---
    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardsToken;

    uint256 public rewardRate;          // rewards per second
    uint256 public totalStaked;         // total amount staked
    uint256 public rewardPerTokenStored;
    uint256 public lastRewardTime;
    uint256 public minStake;            // minimum stake amount

    mapping(address => StakeInfo) public stakes;
    mapping(address => uint256) public rewards;

    // --- Events ---
    event Staked(address indexed account, uint256 amount);
    event Unstaked(address indexed account, uint256 amount);
    event RewardsPaid(address indexed account, uint256 amount);
    event RewardRateUpdated(uint256 newRate);
    event MinStakeUpdated(uint256 newMinStake);
    event RewardAdded(uint256 amount);

    // --- Errors ---
    error InsufficientStake();
    error ZeroAmount();
    error NoStake();
    error ContractNotFunded();
    error BelowMinimumStake();

    // --- Modifiers ---
    modifier updateRewards(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastRewardTime = block.timestamp;

        if (account != address(0)) {
            StakeInfo storage s = stakes[account];
            rewards[account] += earnedFor(s);
            s.rewardDebt = rewardPerTokenStored * s.amount;
        }
        _;
    }

    constructor(
        address _stakingToken,
        address _rewardsToken,
        uint256 _rewardRate,
        uint256 _minStake
    ) Ownable(msg.sender) {
        stakingToken = IERC20(_stakingToken);
        rewardsToken = IERC20(_rewardsToken);
        rewardRate = _rewardRate;
        minStake = _minStake;
        lastRewardTime = block.timestamp;
    }

    // --- Views ---

    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored +
            ((block.timestamp - lastRewardTime) * rewardRate * 1e18) / totalStaked;
    }

    function earned(address account) public view returns (uint256) {
        return earnedFor(stakes[account]);
    }

    function earnedFor(StakeInfo storage s) internal view returns (uint256) {
        return (s.amount * (rewardPerToken() - s.rewardDebt)) / 1e18;
    }

    function getStakeInfo(address account)
        public
        view
        returns (uint256 amount, uint256 timestamp, uint256 earnedRewards)