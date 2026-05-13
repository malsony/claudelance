// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import { IClaudelanceCore } from "./interfaces/IClaudelanceCore.sol";

/// @title ClaudelanceCore
/// @notice Onchain marketplace where workers compete to solve GitHub bounties paid in cUSD.
contract ClaudelanceCore is IClaudelanceCore, ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;

    IERC20 public immutable cUSD;
    address public ciRelayer;
    address public treasury;

    uint256 public constant PROTOCOL_FEE_BPS = 200;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint8 public constant MAX_SLOTS = 20;
    uint64 public constant MIN_DEADLINE = 1 days;
    uint64 public constant MAX_DEADLINE = 14 days;
    uint96 public constant MIN_BOUNTY = 0.5e18;
    /// @notice Delay after `deadline` during which only the poster may cancel the bounty.
    ///         Protects workers with a passing submission from a third-party cancel-race.
    uint64 public constant RESOLUTION_GRACE_PERIOD = 3 days;

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
        if (bytes(targetRepoUrl).length == 0) revert InvalidAddress();

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
        // One-shot: a worker cannot overwrite a prior submission. Otherwise a worker could
        // submit good code, get the relayer's `ciPassed=true` attestation, then quietly
        // swap to malicious code and still win on the stale attestation.
        if (s.submittedAt != 0) revert AlreadySubmitted();

        s.prUrl = prUrl;
        s.commitHash = commitHash;
        s.metadata = metadata;
        s.submittedAt = uint64(block.timestamp);

        emit PRSubmitted(bountyId, msg.sender, prUrl, commitHash);
    }

    function attestCI(uint256 bountyId, address worker, bool passed) external onlyRelayer {
        Bounty storage b = _bounties[bountyId];
        if (b.status != BountyStatus.Open) revert BountyNotOpen();
        if (!hasClaimed[bountyId][worker]) revert NotClaimer();
        Submission storage s = _submissions[bountyId][worker];
        if (s.submittedAt == 0) revert NoSubmission();

        s.ciPassed = passed;
        emit CIAttested(bountyId, worker, passed);
    }

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

        // forge-lint: disable-next-line(unsafe-typecast)
        uint96 fee = uint96((uint256(b.amount) * PROTOCOL_FEE_BPS) / BPS_DENOMINATOR);
        uint96 payout = b.amount - fee;

        earnings[winner] += payout;
        totalProtocolRevenue += fee;
        totalBountiesResolved += 1;

        emit BountyResolved(bountyId, winner, payout, fee);
        emit ProtocolRevenueAccrued(fee, totalProtocolRevenue);

        _settleStakes(bountyId, b, winner);

        if (fee > 0) {
            cUSD.safeTransfer(treasury, fee);
        }
    }

    function cancelExpired(uint256 bountyId) external nonReentrant {
        Bounty storage b = _bounties[bountyId];
        if (b.status != BountyStatus.Open) revert BountyNotOpen();
        if (block.timestamp < b.deadline) revert BountyNotExpired();
        // During the grace window the poster keeps the exclusive right to resolve or
        // cancel; a passing-CI worker cannot be cancelled out by a griefer.
        if (block.timestamp < b.deadline + RESOLUTION_GRACE_PERIOD && msg.sender != b.poster) {
            revert GracePeriodActive();
        }

        b.status = BountyStatus.Cancelled;

        uint96 refund = b.amount;
        emit BountyCancelled(bountyId, b.poster, refund);

        _settleStakes(bountyId, b, address(0));

        cUSD.safeTransfer(b.poster, refund);
    }

    function withdrawEarnings() external nonReentrant {
        uint256 amount = earnings[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        earnings[msg.sender] = 0;
        emit EarningsWithdrawn(msg.sender, amount);
        cUSD.safeTransfer(msg.sender, amount);
    }

    function _settleStakes(uint256 bountyId, Bounty storage b, address winner) internal {
        if (b.stakeRequired == 0) return;

        address[] storage claimers = _claimers[bountyId];
        uint256 len = claimers.length;
        uint96 totalForfeited;

        for (uint256 i = 0; i < len; i++) {
            address worker = claimers[i];
            Submission storage s = _submissions[bountyId][worker];
            if (s.stakeRefunded) continue;

            bool refund;
            if (worker == winner) {
                refund = true;
            } else if (s.submittedAt == 0) {
                refund = false;
            } else if (b.ciRequired) {
                refund = s.ciPassed;
            } else {
                refund = true;
            }

            s.stakeRefunded = true;
            if (refund) {
                earnings[worker] += b.stakeRequired;
                emit StakeRefunded(bountyId, worker, b.stakeRequired);
            } else {
                totalForfeited += b.stakeRequired;
                emit StakeForfeited(bountyId, worker, b.stakeRequired);
            }
        }

        if (totalForfeited > 0) {
            totalProtocolRevenue += totalForfeited;
            emit ProtocolRevenueAccrued(totalForfeited, totalProtocolRevenue);
            cUSD.safeTransfer(treasury, totalForfeited);
        }
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
        for (uint256 i = 0; i < len; i++) {
            address worker = claimers[i];
            Submission storage s = _submissions[bountyId][worker];
            if (s.submittedAt == 0) continue;
            if (b.ciRequired && !s.ciPassed) continue;
            buffer[count++] = worker;
        }

        eligible = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            eligible[i] = buffer[i];
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

    function setCIRelayer(address newRelayer) external onlyOwner {
        if (newRelayer == address(0)) revert InvalidAddress();
        address previous = ciRelayer;
        ciRelayer = newRelayer;
        emit CIRelayerUpdated(previous, newRelayer);
    }

    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert InvalidAddress();
        address previous = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(previous, newTreasury);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
