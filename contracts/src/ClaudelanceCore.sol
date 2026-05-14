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
    /// @notice Delay after `deadline` during which only the poster may cancel the bounty.
    ///         Protects workers with a passing submission from a third-party cancel-race.
    uint64 public constant RESOLUTION_GRACE_PERIOD = 3 days;
    /// @notice Mandatory delay between proposing a treasury / relayer rotation and applying it.
    ///         Gives the community a window to react if an owner key is compromised.
    uint64 public constant ADMIN_TIMELOCK = 2 days;

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
    /// @notice Outstanding cUSD credited to an account (workers, poster refunds, treasury fees + forfeits).
    ///         All outbound cUSD flows through this mapping + `withdrawEarnings()` (pull pattern) so a
    ///         single misbehaving recipient cannot brick bounty resolution for everyone else.
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

    /// @notice Post a new bounty. Transfers `amount` cUSD from the caller into the
    ///         contract; the deposit is held until `pickWinner` resolves it or anyone
    ///         calls `cancelExpired` after `deadline + RESOLUTION_GRACE_PERIOD`.
    /// @param  bountyType        Numeric bounty category (Phase 1 UI uses 0 = Code).
    /// @param  targetRepoUrl     GitHub repo to which workers will open PRs.
    /// @param  instructionUrl    GitHub issue or spec link describing the work.
    /// @param  requirementsHash  keccak256 of the off-chain bounty config JSON.
    /// @param  amount            Bounty reward in cUSD wei. Must be >= MIN_BOUNTY.
    /// @param  maxSlots          Maximum number of workers that can claim (1..MAX_SLOTS).
    /// @param  stake             cUSD required as anti-sybil collateral per claimer.
    /// @param  deadline          Bounty lifetime in seconds (MIN_DEADLINE..MAX_DEADLINE).
    /// @param  ciRequired        If true, only CI-passing submissions are eligible to win.
    /// @return bountyId          The newly minted, monotonically increasing bounty id.
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

    /// @notice Claim a worker slot for `bountyId`. Locks the bounty's `stakeRequired`
    ///         cUSD from the caller. Reverts after the bounty deadline or once all
    ///         slots are filled.
    /// @param  bountyId Target bounty.
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

    /// @notice Record a worker's PR submission for `bountyId`. One-shot: a worker may
    ///         not overwrite a prior submission (prevents stale-CI bypass attacks).
    /// @param  bountyId   Target bounty.
    /// @param  prUrl      Canonical GitHub PR URL.
    /// @param  commitHash The PR's head commit hash.
    /// @param  metadata   Free-form JSON the worker wants to attach (capabilities, notes).
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

    /// @notice Relayer-only CI attestation. May be re-called to flip a prior decision
    ///         (e.g. after a re-run on the same submission). Honors `Pausable` so that
    ///         pausing the contract freezes a compromised relayer until rotated.
    /// @param  bountyId Target bounty.
    /// @param  worker   Submitter address.
    /// @param  passed   New attestation value.
    function attestCI(uint256 bountyId, address worker, bool passed) external whenNotPaused onlyRelayer {
        Bounty storage b = _bounties[bountyId];
        if (b.status != BountyStatus.Open) revert BountyNotOpen();
        if (!hasClaimed[bountyId][worker]) revert NotClaimer();
        Submission storage s = _submissions[bountyId][worker];
        if (s.submittedAt == 0) revert NoSubmission();

        s.ciPassed = passed;
        emit CIAttested(bountyId, worker, passed);
    }

    /// @notice Poster selects the winning submission. Atomic settlement: credits the
    ///         winner's payout (minus the 2% protocol fee) and the fee to `treasury`
    ///         via the `earnings` mapping. Refunds good-faith stakes to losers with
    ///         passing CI; forfeits stakes to `treasury` for submissions that missed
    ///         or failed CI. All outbound cUSD is pulled via `withdrawEarnings()`.
    /// @param  bountyId Target bounty.
    /// @param  winner   Must be a slot claimer with a submitted and (if required) CI-passing PR.
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
        if (fee > 0) {
            earnings[treasury] += fee;
            totalProtocolRevenue += fee;
            emit ProtocolRevenueAccrued(fee, totalProtocolRevenue);
        }
        totalBountiesResolved += 1;

        emit BountyResolved(bountyId, winner, payout, fee);

        _settleStakes(bountyId, b, winner);
    }

    /// @notice Cancel an unresolved bounty after `deadline`. During the
    ///         `RESOLUTION_GRACE_PERIOD` only the poster may cancel; after grace,
    ///         anyone may call. Credits the poster the full `amount` via `earnings`
    ///         and settles claimer stakes with the same good-faith / forfeit rules
    ///         as `pickWinner`.
    /// @param  bountyId Target bounty.
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
        earnings[b.poster] += refund;
        emit BountyCancelled(bountyId, b.poster, refund);

        _settleStakes(bountyId, b, address(0));
    }

    /// @notice Pull-pattern withdrawal of all cUSD credited to the caller (worker payouts,
    ///         stake refunds, poster cancellation refunds, treasury fees). Always callable,
    ///         even when paused, so users can always exit.
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
            earnings[treasury] += totalForfeited;
            totalProtocolRevenue += totalForfeited;
            emit ProtocolRevenueAccrued(totalForfeited, totalProtocolRevenue);
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

    /// @notice Aggregate marketplace metrics. Judge-friendly read for dashboards.
    /// @return volume   Cumulative cUSD deposited into bounties.
    /// @return revenue  Cumulative protocol fee + forfeited stake credited to treasury.
    /// @return resolved Number of bounties that reached the Resolved state.
    /// @return posters  Unique poster count.
    /// @return workers  Unique slot-claimer count.
    function getStats()
        external
        view
        returns (uint256 volume, uint256 revenue, uint256 resolved, uint256 posters, uint256 workers)
    {
        return
            (totalBountyVolume, totalProtocolRevenue, totalBountiesResolved, uniquePosterCount, uniqueWorkerCount);
    }

    // ---------------------------------------------------------------------- //
    //                          Admin: timelock rotation                      //
    // ---------------------------------------------------------------------- //

    /// @notice Stage a new CI relayer address. Becomes applicable after
    ///         `ADMIN_TIMELOCK` via `applyCIRelayer()`.
    function proposeCIRelayer(address newRelayer) external onlyOwner {
        if (newRelayer == address(0)) revert InvalidAddress();
        uint64 effectiveAt = uint64(block.timestamp) + ADMIN_TIMELOCK;
        pendingCIRelayer = PendingAddress({ proposed: newRelayer, effectiveAt: effectiveAt });
        emit CIRelayerProposed(newRelayer, effectiveAt);
    }

    /// @notice Apply a previously proposed CI relayer rotation. Anyone may call
    ///         once the timelock has elapsed (owner has the burden to monitor).
    function applyCIRelayer() external {
        PendingAddress memory p = pendingCIRelayer;
        if (p.proposed == address(0)) revert NoPendingChange();
        if (block.timestamp < p.effectiveAt) revert TimelockNotElapsed();
        address previous = ciRelayer;
        ciRelayer = p.proposed;
        delete pendingCIRelayer;
        emit CIRelayerUpdated(previous, p.proposed);
    }

    /// @notice Cancel a pending CI relayer proposal (e.g. wrong address typed).
    function cancelPendingCIRelayer() external onlyOwner {
        address proposed = pendingCIRelayer.proposed;
        if (proposed == address(0)) revert NoPendingChange();
        delete pendingCIRelayer;
        emit CIRelayerProposalCancelled(proposed);
    }

    /// @notice Stage a new treasury address. Becomes applicable after
    ///         `ADMIN_TIMELOCK` via `applyTreasury()`.
    function proposeTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0) || newTreasury == address(this)) revert InvalidAddress();
        uint64 effectiveAt = uint64(block.timestamp) + ADMIN_TIMELOCK;
        pendingTreasury = PendingAddress({ proposed: newTreasury, effectiveAt: effectiveAt });
        emit TreasuryProposed(newTreasury, effectiveAt);
    }

    /// @notice Apply a previously proposed treasury rotation. Anyone may call
    ///         once the timelock has elapsed.
    function applyTreasury() external {
        PendingAddress memory p = pendingTreasury;
        if (p.proposed == address(0)) revert NoPendingChange();
        if (block.timestamp < p.effectiveAt) revert TimelockNotElapsed();
        address previous = treasury;
        treasury = p.proposed;
        delete pendingTreasury;
        emit TreasuryUpdated(previous, p.proposed);
    }

    /// @notice Cancel a pending treasury proposal.
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

    /// @notice Rescue ERC20 tokens accidentally sent to the contract. cUSD is excluded
    ///         because it is held legitimately on behalf of bounties, stakes, and
    ///         pending earnings withdrawals.
    /// @param  token  ERC20 token to rescue. Must not equal `cUSD`.
    /// @param  to     Recipient address. Cannot be the zero address.
    /// @param  amount Token amount to transfer.
    function rescueERC20(IERC20 token, address to, uint256 amount) external onlyOwner {
        if (address(token) == address(cUSD)) revert CannotRescueCUSD();
        if (to == address(0)) revert InvalidAddress();
        emit ERC20Rescued(address(token), to, amount);
        token.safeTransfer(to, amount);
    }
}
