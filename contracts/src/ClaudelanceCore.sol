// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import { IClaudelanceCore } from "./interfaces/IClaudelanceCore.sol";

/// @title ClaudelanceCore
/// @notice Onchain marketplace where workers compete to solve GitHub bounties paid in cUSD.
contract ClaudelanceCore is IClaudelanceCore, ReentrancyGuard, Ownable2Step, Pausable {
    using SafeERC20 for IERC20;

    IERC20 public immutable cUSD;
    address public ciRelayer;
    address public treasury;

    PendingAddress public pendingTreasury;
    PendingAddress public pendingCIRelayer;

    uint256 public constant PROTOCOL_FEE_BPS = 200;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint8 public constant MAX_SLOTS = 20;
    uint64 public constant MIN_DEADLINE = 1 days;
    uint64 public constant MAX_DEADLINE = 14 days;
    uint96 public constant MIN_BOUNTY = 0.5e18;
    uint64 public constant RESOLUTION_GRACE_PERIOD = 3 days;
    uint64 public constant ADMIN_TIMELOCK = 2 days;
    uint64 public constant PROPOSAL_VALIDITY_WINDOW = 14 days;

    uint256 public totalBountyVolume;
    uint256 public totalProtocolRevenue;
    uint256 public totalBountiesResolved;
    uint256 public uniquePosterCount;
    uint256 public uniqueWorkerCount;
    mapping(uint8 => uint256) public bountyCountByType;

    uint256 public bountyCount;
    mapping(uint256 => Bounty) private _bounties;
    mapping(uint256 => address[]) private _claimers;
    mapping(uint256 => mapping(address => bool)) public hasClaimed;
    mapping(uint256 => mapping(address => Submission)) private _submissions;
    mapping(address => uint256) public earnings;
    mapping(address => bool) public hasPosted;
    mapping(address => bool) public hasWorked;

    error InvalidAmount();
    error InvalidSlots();
    error InvalidDeadline();
    error InvalidAddress();
    error InvalidUrl();
    error BountyNotOpen();
    error BountyNotExpired();
    error DeadlinePassed();
    error SlotsFull();
    error AlreadyClaimed();
    error NotClaimer();
    error NoSubmission();
    error AlreadySubmitted();
    error WinnerInvalid();
    error NotPoster();
    error NotRelayer();
    error NothingToWithdraw();
    error GracePeriodActive();
    error CannotRescueCUSD();
    error NoPendingChange();
    error TimelockNotElapsed();
    error ProposalExpired();
    error BountyNotResolved();
    error StakeAlreadySettled();
    error NoStakeRequired();

    modifier onlyRelayer() {
        if (msg.sender != ciRelayer) revert NotRelayer();
        _;
    }

    constructor(IERC20 _cUSD, address _treasury, address _ciRelayer, address _owner) Ownable(_owner) {
        if (address(_cUSD) == address(0) || _treasury == address(0) || _ciRelayer == address(0)) {
            revert InvalidAddress();
        }
        cUSD = _cUSD;
        treasury = _treasury;
        ciRelayer = _ciRelayer;

        emit TreasuryUpdated(address(0), _treasury);
        emit CIRelayerUpdated(address(0), _ciRelayer);
    }

    function postBounty(
        uint8 bountyType,
        string calldata targetRepoUrl,
        string calldata instructionUrl,
        bytes32 requirementsHash,
        uint96 amount,
        uint8 maxSlots,
        uint96 stake,
        uint64 deadline,
        bool ciRequired
    ) external whenNotPaused nonReentrant returns (uint256 bountyId) {
        if (amount < MIN_BOUNTY) revert InvalidAmount();
        if (maxSlots == 0 || maxSlots > MAX_SLOTS) revert InvalidSlots();
        if (deadline < MIN_DEADLINE || deadline > MAX_DEADLINE) revert InvalidDeadline();
        if (bytes(targetRepoUrl).length == 0 || bytes(instructionUrl).length == 0) revert InvalidUrl();

        bountyId = ++bountyCount;
        uint64 absoluteDeadline = uint64(block.timestamp) + deadline;

        _bounties[bountyId] = Bounty({
            poster: msg.sender,
            amount: amount,
            winner: address(0),
            stakeRequired: stake,
            deadline: absoluteDeadline,
            maxSlots: maxSlots,
            claimedSlots: 0,
            bountyType: bountyType,
            ciRequired: ciRequired,
            status: BountyStatus.Open,
            targetRepoUrl: targetRepoUrl,
            instructionUrl: instructionUrl,
            requirementsHash: requirementsHash
        });

        totalBountyVolume += amount;
        bountyCountByType[bountyType] += 1;
        if (!hasPosted[msg.sender]) {
            hasPosted[msg.sender] = true;
            uniquePosterCount += 1;
        }

        cUSD.safeTransferFrom(msg.sender, address(this), amount);

        emit BountyPosted(bountyId, msg.sender, bountyType, amount, maxSlots, targetRepoUrl, requirementsHash);
    }

    function claimSlot(uint256 bountyId) external whenNotPaused nonReentrant {
        Bounty storage b = _bounties[bountyId];
        if (b.status != BountyStatus.Open) revert BountyNotOpen();
        if (block.timestamp >= b.deadline) revert DeadlinePassed();
        if (b.claimedSlots >= b.maxSlots) revert SlotsFull();
        if (hasClaimed[bountyId][msg.sender]) revert AlreadyClaimed();

        hasClaimed[bountyId][msg.sender] = true;
        b.claimedSlots += 1;
        _claimers[bountyId].push(msg.sender);

        if (!hasWorked[msg.sender]) {
            hasWorked[msg.sender] = true;
            uniqueWorkerCount += 1;
        }

        if (b.stakeRequired > 0) {
            cUSD.safeTransferFrom(msg.sender, address(this), b.stakeRequired);
        }

        emit SlotClaimed(bountyId, msg.sender);
    }

    function submitPR(uint256 bountyId, string calldata prUrl, bytes32 commitHash, string calldata metadata)
        external
        whenNotPaused
    {
        Bounty storage b = _bounties[bountyId];
        if (b.status != BountyStatus.Open) revert BountyNotOpen();
        if (block.timestamp >= b.deadline) revert DeadlinePassed();
        if (!hasClaimed[bountyId][msg.sender]) revert NotClaimer();
        if (bytes(prUrl).length == 0) revert NoSubmission();

        Submission storage s = _submissions[bountyId][msg.sender];
        // One-shot: blocks the stale-CI-attestation swap attack.
        if (s.submittedAt != 0) revert AlreadySubmitted();

        s.prUrl = prUrl;
        s.commitHash = commitHash;
        s.metadata = metadata;
        s.submittedAt = uint64(block.timestamp);

        emit PRSubmitted(bountyId, msg.sender, prUrl, commitHash);
    }

    function attestCI(uint256 bountyId, address worker, bool passed) external whenNotPaused onlyRelayer {
        Bounty storage b = _bounties[bountyId];
        if (b.status != BountyStatus.Open) revert BountyNotOpen();
        if (!hasClaimed[bountyId][worker]) revert NotClaimer();
        Submission storage s = _submissions[bountyId][worker];
        if (s.submittedAt == 0) revert NoSubmission();

        s.ciPassed = passed;
        emit CIAttested(bountyId, worker, passed);
    }

    /// @notice Resolves the bounty in O(1). Stakes are settled separately via `settleStake`.
    function pickWinner(uint256 bountyId, address winner) external nonReentrant {
        Bounty storage b = _bounties[bountyId];
        if (b.status != BountyStatus.Open) revert BountyNotOpen();
        if (msg.sender != b.poster) revert NotPoster();
        if (!hasClaimed[bountyId][winner]) revert WinnerInvalid();

        Submission storage ws = _submissions[bountyId][winner];
        if (ws.submittedAt == 0) revert WinnerInvalid();
        if (b.ciRequired && !ws.ciPassed) revert WinnerInvalid();

        b.status = BountyStatus.Resolved;
        b.winner = winner;

        uint96 amount = b.amount;
        // forge-lint: disable-next-line(unsafe-typecast)
        uint96 fee = uint96((uint256(amount) * PROTOCOL_FEE_BPS) / BPS_DENOMINATOR);
        uint96 payout = amount - fee;

        earnings[winner] += payout;
        if (fee > 0) {
            earnings[treasury] += fee;
            uint256 newRevenue = totalProtocolRevenue + fee;
            totalProtocolRevenue = newRevenue;
            emit ProtocolRevenueAccrued(fee, newRevenue);
        }
        unchecked { ++totalBountiesResolved; }

        emit BountyResolved(bountyId, winner, payout, fee);
    }

    /// @notice After `deadline`, anyone may cancel — but during the grace window only the
    ///         poster, so a third party cannot race a passing-CI worker out of their win.
    function cancelExpired(uint256 bountyId) external nonReentrant {
        Bounty storage b = _bounties[bountyId];
        if (b.status != BountyStatus.Open) revert BountyNotOpen();
        uint64 deadline = b.deadline;
        if (block.timestamp < deadline) revert BountyNotExpired();
        address poster_ = b.poster;
        if (block.timestamp < deadline + RESOLUTION_GRACE_PERIOD && msg.sender != poster_) {
            revert GracePeriodActive();
        }

        b.status = BountyStatus.Cancelled;

        uint96 refund = b.amount;
        earnings[poster_] += refund;
        emit BountyCancelled(bountyId, poster_, refund);
    }

    /// @notice Permissionless stake settlement. Refund-vs-forfeit rules:
    ///         winner → refund; non-submitter → forfeit;
    ///         CI required → refund iff `ciPassed`; CI not required → refund.
    ///         Forfeits credit `treasury` and bump `totalProtocolRevenue`.
    function settleStake(uint256 bountyId, address worker) external nonReentrant {
        Bounty storage b = _bounties[bountyId];
        BountyStatus status = b.status;
        if (status == BountyStatus.Open) revert BountyNotResolved();
        if (!hasClaimed[bountyId][worker]) revert NotClaimer();
        uint96 stake = b.stakeRequired;
        if (stake == 0) revert NoStakeRequired();

        Submission storage s = _submissions[bountyId][worker];
        if (s.stakeRefunded) revert StakeAlreadySettled();
        s.stakeRefunded = true;

        bool refund;
        if (status == BountyStatus.Resolved && worker == b.winner) {
            refund = true;
        } else if (s.submittedAt == 0) {
            refund = false;
        } else if (b.ciRequired) {
            refund = s.ciPassed;
        } else {
            refund = true;
        }

        if (refund) {
            earnings[worker] += stake;
            emit StakeRefunded(bountyId, worker, stake);
        } else {
            earnings[treasury] += stake;
            uint256 newRevenue = totalProtocolRevenue + stake;
            totalProtocolRevenue = newRevenue;
            emit StakeForfeited(bountyId, worker, stake);
            emit ProtocolRevenueAccrued(stake, newRevenue);
        }
    }

    /// @notice Always callable, even when paused, so users can always exit.
    function withdrawEarnings() external nonReentrant {
        uint256 amount = earnings[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        earnings[msg.sender] = 0;
        emit EarningsWithdrawn(msg.sender, amount);
        cUSD.safeTransfer(msg.sender, amount);
    }

    function getBounty(uint256 bountyId) external view returns (Bounty memory) {
        return _bounties[bountyId];
    }

    function getSubmission(uint256 bountyId, address worker) external view returns (Submission memory) {
        return _submissions[bountyId][worker];
    }

    function getClaimers(uint256 bountyId) external view returns (address[] memory) {
        return _claimers[bountyId];
    }

    function getEligibleSubmissions(uint256 bountyId) external view returns (address[] memory eligible) {
        Bounty storage b = _bounties[bountyId];
        address[] storage claimers = _claimers[bountyId];
        uint256 len = claimers.length;

        address[] memory buffer = new address[](len);
        uint256 count;
        for (uint256 i = 0; i < len;) {
            address worker = claimers[i];
            Submission storage s = _submissions[bountyId][worker];
            if (s.submittedAt != 0 && (!b.ciRequired || s.ciPassed)) {
                buffer[count] = worker;
                unchecked { ++count; }
            }
            unchecked { ++i; }
        }

        eligible = new address[](count);
        for (uint256 i = 0; i < count;) {
            eligible[i] = buffer[i];
            unchecked { ++i; }
        }
    }

    function getStats()
        external
        view
        returns (uint256 volume, uint256 revenue, uint256 resolved, uint256 posters, uint256 workers)
    {
        return
            (totalBountyVolume, totalProtocolRevenue, totalBountiesResolved, uniquePosterCount, uniqueWorkerCount);
    }

    function proposeCIRelayer(address newRelayer) external onlyOwner {
        if (newRelayer == address(0)) revert InvalidAddress();
        uint64 effectiveAt = uint64(block.timestamp) + ADMIN_TIMELOCK;
        pendingCIRelayer = PendingAddress({ proposed: newRelayer, effectiveAt: effectiveAt });
        emit CIRelayerProposed(newRelayer, effectiveAt);
    }

    function applyCIRelayer() external {
        PendingAddress memory p = pendingCIRelayer;
        if (p.proposed == address(0)) revert NoPendingChange();
        if (block.timestamp < p.effectiveAt) revert TimelockNotElapsed();
        if (block.timestamp > uint256(p.effectiveAt) + PROPOSAL_VALIDITY_WINDOW) revert ProposalExpired();
        address previous = ciRelayer;
        ciRelayer = p.proposed;
        delete pendingCIRelayer;
        emit CIRelayerUpdated(previous, p.proposed);
    }

    function cancelPendingCIRelayer() external onlyOwner {
        address proposed = pendingCIRelayer.proposed;
        if (proposed == address(0)) revert NoPendingChange();
        delete pendingCIRelayer;
        emit CIRelayerProposalCancelled(proposed);
    }

    function proposeTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0) || newTreasury == address(this)) revert InvalidAddress();
        uint64 effectiveAt = uint64(block.timestamp) + ADMIN_TIMELOCK;
        pendingTreasury = PendingAddress({ proposed: newTreasury, effectiveAt: effectiveAt });
        emit TreasuryProposed(newTreasury, effectiveAt);
    }

    function applyTreasury() external {
        PendingAddress memory p = pendingTreasury;
        if (p.proposed == address(0)) revert NoPendingChange();
        if (block.timestamp < p.effectiveAt) revert TimelockNotElapsed();
        if (block.timestamp > uint256(p.effectiveAt) + PROPOSAL_VALIDITY_WINDOW) revert ProposalExpired();
        address previous = treasury;
        treasury = p.proposed;
        delete pendingTreasury;
        emit TreasuryUpdated(previous, p.proposed);
    }

    function cancelPendingTreasury() external onlyOwner {
        address proposed = pendingTreasury.proposed;
        if (proposed == address(0)) revert NoPendingChange();
        delete pendingTreasury;
        emit TreasuryProposalCancelled(proposed);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice cUSD excluded — it is held legitimately for bounties / stakes / earnings.
    function rescueERC20(IERC20 token, address to, uint256 amount) external onlyOwner {
        if (address(token) == address(cUSD)) revert CannotRescueCUSD();
        if (to == address(0)) revert InvalidAddress();
        emit ERC20Rescued(address(token), to, amount);
        token.safeTransfer(to, amount);
    }
}
