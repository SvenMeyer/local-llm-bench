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
    {
        StakeInfo storage s = stakes[account];
        return (s.amount, s.timestamp, earned(account));
    }

    // --- Admin ---

    function setRewardRate(uint256 _rewardRate) external onlyOwner {
        _updateAllRewards();
        rewardRate = _rewardRate;
        emit RewardRateUpdated(_rewardRate);
    }

    function setMinStake(uint256 _minStake) external onlyOwner {
        minStake = _minStake;
        emit MinStakeUpdated(_minStake);
    }

    /// @notice Add rewards funding to the contract (caller must approve first)
    function addRewards(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        rewardsToken.safeTransferFrom(msg.sender, address(this), amount);
        emit RewardAdded(amount);
    }

    // --- Staking ---

    function stake(uint256 amount) external nonReentrant updateRewards(msg.sender) {
        if (amount == 0) revert ZeroAmount();
        if (stakes[msg.sender].amount + amount < minStake && stakes[msg.sender].amount != 0)
            revert BelowMinimumStake();

        totalStaked += amount;
        stakes[msg.sender].amount += amount;
        stakes[msg.sender].timestamp = block.timestamp;

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant updateRewards(msg.sender) {
        if (amount == 0) revert ZeroAmount();
        if (stakes[msg.sender].amount < amount) revert InsufficientStake();
        if (stakes[msg.sender].amount == 0) revert NoStake();

        // Allow full unstake even if it drops below minStake
        if (stakes[msg.sender].amount > amount &&
            stakes[msg.sender].amount - amount < minStake) {
            revert BelowMinimumStake();
        }

        totalStaked -= amount;
        stakes[msg.sender].amount -= amount;

        stakingToken.safeTransfer(msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }

    function claimRewards() external nonReentrant updateRewards(msg.sender) {
        uint256 earned_ = rewards[msg.sender];
        if (earned_ == 0) revert ZeroAmount();

        uint256 balance = rewardsToken.balanceOf(address(this));
        if (balance < earned_) revert ContractNotFunded();

        rewards[msg.sender] = 0;
        rewardsToken.safeTransfer(msg.sender, earned_);
        emit RewardsPaid(msg.sender, earned_);
    }

    // --- Internal ---

    function _updateAllRewards() internal {
        // Recalculate debt for existing stakes by resetting stored values
        rewardPerTokenStored = rewardPerToken();
        lastRewardTime = block.timestamp;
    }
}
```

```typescript
import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { StakingContract, MockERC20 } from "../typechain-types";

describe("StakingContract", function () {
    let staking: StakingContract;
    let stakeToken: MockERC20;
    let rewardToken: MockERC20;

    let owner: SignerWithAddress;
    let alice: SignerWithAddress;
    let bob: SignerWithAddress;
    let charlie: SignerWithAddress;

    const INITIAL_SUPPLY = ethers.parseEther("1000000");
    const REWARD_RATE = ethers.parseEther("1"); // 1 token/sec
    const MIN_STAKE = ethers.parseEther("10");

    beforeEach(async function () {
        [owner, alice, bob, charlie] = await ethers.getSigners();

        // Deploy mock tokens
        const MockERC20 = await ethers.getContractFactory("MockERC20");
        stakeToken = (await MockERC20.deploy("Stake Token", "STK", INITIAL_SUPPLY)) as MockERC20;
        rewardToken = (await MockERC20.deploy("Reward Token", "RWD", INITIAL_SUPPLY)) as MockERC20;

        // Deploy staking contract
        const Staking = await ethers.getContractFactory("StakingContract");
        staking = (await Staking.deploy(
            await stakeToken.getAddress(),
            await rewardToken.getAddress(),
            REWARD_RATE,
            MIN_STAKE
        )) as StakingContract;

        // Distribute stake tokens
        await stakeToken.transfer(alice.address, ethers.parseEther("5000"));
        await stakeToken.transfer(bob.address, ethers.parseEther("5000"));

        // Fund staking contract with rewards
        await rewardToken.transfer(await staking.getAddress(), ethers.parseEther("100000"));
    });

    // ─────────────────────────────────────────────
    // Deployment
    // ─────────────────────────────────────────────
    describe("Deployment", function () {
        it("should set correct owner", async function () {
            expect(await staking.owner()).to.equal(owner.address);
        });

        it("should set correct staking token", async function () {
            expect(await staking.stakingToken()).to.equal(await stakeToken.getAddress());
        });

        it("should set correct rewards token", async function () {
            expect(await staking.rewardsToken()).to.equal(await rewardToken.getAddress());
        });

        it("should set correct reward rate", async function () {
            expect(await staking.rewardRate()).to.equal(REWARD_RATE);
        });

        it("should set correct min stake", async function () {
            expect(await staking.minStake()).to.equal(MIN_STAKE);
        });
    });

    // ─────────────────────────────────────────────
    // Staking
    // ─────────────────────────────────────────────
    describe("Staking", function () {
        beforeEach(async function () {
            await stakeToken.connect(alice).approve(await staking.getAddress(), ethers.MaxUint256);
        });

        it("should allow staking", async function () {
            const amount = ethers.parseEther("100");
            await expect(staking.connect(alice).stake(amount))
                .to.emit(staking, "Staked")
                .withArgs(alice.address, amount);

            const info = await staking.getStakeInfo(alice.address);
            expect(info.amount).to.equal(amount);
        });

        it("should update totalStaked", async function () {
            const amount = ethers.parseEther("100");
            await staking.connect(alice).stake(amount);
            expect(await staking.totalStaked()).to.equal(amount);
        });

        it("should transfer tokens to contract", async function () {
            const amount = ethers.parseEther("100");
            await staking.connect(alice).stake(amount);
            expect(await stakeToken.balanceOf(await staking.getAddress())).to.equal(amount);
        });

        it("should revert on zero amount", async function () {
            await expect(staking.connect(alice).stake(0))
                .to.be.revertedWithCustomError(staking, "ZeroAmount");
        });

        it("should revert below minimum stake (first stake)", async function () {
            const belowMin = ethers.parseEther("5");
            await expect(staking.connect(alice).stake(belowMin))
                .to.be.revertedWithCustomError(staking, "BelowMinimumStake");
        });

        it("should allow additional stake above minimum", async function () {
            await staking.connect(alice).stake(ethers.parseEther("50"));
            await staking.connect(alice).stake(ethers.parseEther("20"));
            const info = await staking.getStakeInfo(alice.address);
            expect(info.amount).to.equal(ethers.parseEther("70"));
        });

        it("should revert without approval", async function () {
            await expect(staking.connect(bob).stake(ethers.parseEther("100")))
                .to.be.reverted;
        });
    });

    // ─────────────────────────────────────────────
    // Unstaking
    // ─────────────────────────────────────────────
    describe("Unstaking", function () {
        const STAKE_AMOUNT = ethers.parseEther("100");

        beforeEach(async function () {
            await stakeToken.connect(alice).approve(await staking.getAddress(), ethers.MaxUint256);
            await staking.connect(alice).stake(STAKE_AMOUNT);
        });

        it("should allow unstaking", async function () {
            await expect(staking.connect(alice).unstake(STAKE_AMOUNT))
                .to.emit(staking, "Unstaked")
                .withArgs(alice.address, STAKE_AMOUNT);
        });

        it("should return tokens on unstake", async function () {
            const balBefore = await stakeToken.balanceOf(alice.address);
            await staking.connect(alice