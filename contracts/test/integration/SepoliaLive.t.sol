// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test, console2 } from "forge-std/Test.sol";
import { stdJson } from "forge-std/StdJson.sol";

import { ClaudelanceCore } from "../../src/ClaudelanceCore.sol";
import { IClaudelanceCore } from "../../src/interfaces/IClaudelanceCore.sol";
import { MockCUSD } from "../../src/mocks/MockCUSD.sol";

/// @title  SepoliaLiveTest
/// @notice Integration suite that forks Celo Sepolia and exercises the live
///         ClaudelanceCore deployment recorded in `deployments/celo-sepolia.json`.
///         Skips automatically when `CELO_SEPOLIA_RPC` is unset, so the default
///         `forge test` run on a developer machine stays cheap.
///
/// Run only this suite:
///   forge test --match-path "test/integration/SepoliaLive.t.sol" -vvv
///
/// These tests do NOT broadcast — Foundry creates a local fork and the deployed
/// bytecode is exercised in memory. State pollution on the actual chain comes
/// only from the broadcast scripts (`SeedBounties`, `IntegrationE2E`).
contract SepoliaLiveTest is Test {
    using stdJson for string;

    ClaudelanceCore internal core;
    MockCUSD internal cusd;
    address internal coreAddr;
    address internal cusdAddr;
    address internal liveOwner;
    address internal liveTreasury;
    address internal liveRelayer;

    address internal poster = makeAddr("fork-poster");
    address internal w1 = makeAddr("fork-w1");
    address internal w2 = makeAddr("fork-w2");
    address internal stranger = makeAddr("fork-stranger");

    uint96 internal constant AMOUNT = 5e18;
    uint96 internal constant STAKE = 0.25e18;
    uint8 internal constant SLOTS = 5;
    uint64 internal constant DEADLINE = 2 days;

    function setUp() public {
        string memory rpc = vm.envOr("CELO_SEPOLIA_RPC", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }

        vm.createSelectFork(rpc);

        string memory deployJson = vm.readFile("./deployments/celo-sepolia.json");
        coreAddr = deployJson.readAddress(".core");
        cusdAddr = deployJson.readAddress(".cUSD");

        core = ClaudelanceCore(coreAddr);
        cusd = MockCUSD(cusdAddr);

        liveOwner = core.owner();
        liveTreasury = core.treasury();
        liveRelayer = core.ciRelayer();

        // MockCUSD has permissionless mint — give every fork actor enough headroom
        // to post bounties, claim stakes, and absorb fees.
        cusd.mint(poster, 1_000e18);
        cusd.mint(w1, 100e18);
        cusd.mint(w2, 100e18);

        vm.prank(poster);
        cusd.approve(coreAddr, type(uint256).max);
        vm.prank(w1);
        cusd.approve(coreAddr, type(uint256).max);
        vm.prank(w2);
        cusd.approve(coreAddr, type(uint256).max);
    }

    function _post() internal returns (uint256) {
        vm.prank(poster);
        return core.postBounty(
            0,
            "github.com/yeheskieltame/claudelance-sandbox",
            "github.com/yeheskieltame/claudelance-sandbox/issues/integration",
            keccak256("fork-test"),
            AMOUNT,
            SLOTS,
            STAKE,
            DEADLINE,
            true
        );
    }

    function _claim(uint256 id, address w) internal {
        vm.prank(w);
        core.claimSlot(id);
    }

    function _submit(uint256 id, address w, string memory pr) internal {
        vm.prank(w);
        core.submitPR(id, pr, keccak256(abi.encodePacked(pr)), "");
    }

    function _attest(uint256 id, address w, bool ok) internal {
        vm.prank(liveRelayer);
        core.attestCI(id, w, ok);
    }

    function test_Live_ConstantsMatchSource() public view {
        assertEq(core.PROTOCOL_FEE_BPS(), 200);
        assertEq(core.BPS_DENOMINATOR(), 10_000);
        assertEq(core.MAX_SLOTS(), 20);
        assertEq(core.MIN_DEADLINE(), 1 days);
        assertEq(core.MAX_DEADLINE(), 14 days);
        assertEq(core.MIN_BOUNTY(), 0.5e18);
        assertEq(core.RESOLUTION_GRACE_PERIOD(), 3 days);
    }

    function test_Live_RolesMatchDeployment() public view {
        string memory deployJson = vm.readFile("./deployments/celo-sepolia.json");
        assertEq(liveOwner, deployJson.readAddress(".owner"));
        assertEq(liveTreasury, deployJson.readAddress(".treasury"));
        assertEq(liveRelayer, deployJson.readAddress(".ciRelayer"));
        assertEq(address(core.cUSD()), cusdAddr);
    }

    function test_Live_cUSDIsMockMintAndSymbolMatch() public view {
        assertEq(cusd.symbol(), "cUSD");
        assertEq(cusd.decimals(), 18);
        assertGe(cusd.balanceOf(poster), 1_000e18);
    }

    function test_Live_FullLifecycle_ResolvesAndCreditsAtomically() public {
        uint256 startVolume = core.totalBountyVolume();
        uint256 startResolved = core.totalBountiesResolved();
        uint256 startRevenue = core.totalProtocolRevenue();
        uint256 treasuryBefore = cusd.balanceOf(liveTreasury);

        uint256 id = _post();

        _claim(id, w1);
        _claim(id, w2);
        _submit(id, w1, "github.com/yeheskieltame/claudelance-sandbox/pull/A");
        _submit(id, w2, "github.com/yeheskieltame/claudelance-sandbox/pull/B");
        _attest(id, w1, true);
        _attest(id, w2, true);

        vm.prank(poster);
        core.pickWinner(id, w1);

        uint96 expectedFee = uint96((uint256(AMOUNT) * 200) / 10_000);
        uint96 expectedPayout = AMOUNT - expectedFee;

        assertEq(core.earnings(w1), uint256(expectedPayout) + STAKE, "winner: payout + stake refund");
        assertEq(core.earnings(w2), STAKE, "good-faith loser: stake refund only");
        assertEq(cusd.balanceOf(liveTreasury), treasuryBefore + expectedFee, "treasury credited fee");
        assertEq(core.totalBountyVolume(), startVolume + AMOUNT, "volume += AMOUNT");
        assertEq(core.totalBountiesResolved(), startResolved + 1, "resolved counter +1");
        assertEq(core.totalProtocolRevenue(), startRevenue + expectedFee, "revenue += fee");

        uint256 w1Balance = cusd.balanceOf(w1);
        vm.prank(w1);
        core.withdrawEarnings();
        assertEq(cusd.balanceOf(w1), w1Balance + uint256(expectedPayout) + STAKE);
        assertEq(core.earnings(w1), 0);
    }

    function test_Live_GracePeriodBlocksThirdPartyCancel() public {
        uint256 id = _post();
        _claim(id, w1);
        _submit(id, w1, "github.com/yeheskieltame/claudelance-sandbox/pull/C");
        _attest(id, w1, true);

        vm.warp(block.timestamp + DEADLINE + 1);

        vm.expectRevert(ClaudelanceCore.GracePeriodActive.selector);
        vm.prank(stranger);
        core.cancelExpired(id);

        IClaudelanceCore.Bounty memory b = core.getBounty(id);
        assertEq(uint8(b.status), uint8(IClaudelanceCore.BountyStatus.Open));
    }

    function test_Live_AfterGrace_PublicCancelSettlesGoodFaith() public {
        uint256 id = _post();
        _claim(id, w1);
        _claim(id, w2);
        _submit(id, w1, "github.com/yeheskieltame/claudelance-sandbox/pull/D");
        _attest(id, w1, true);

        uint256 posterBefore = cusd.balanceOf(poster);
        uint256 treasuryBefore = cusd.balanceOf(liveTreasury);

        vm.warp(block.timestamp + DEADLINE + core.RESOLUTION_GRACE_PERIOD() + 1);
        vm.prank(stranger);
        core.cancelExpired(id);

        assertEq(cusd.balanceOf(poster), posterBefore + AMOUNT, "poster refunded");
        assertEq(core.earnings(w1), STAKE, "passing-CI loser keeps stake");
        assertEq(core.earnings(w2), 0, "no-submission worker forfeits");
        assertEq(cusd.balanceOf(liveTreasury), treasuryBefore + STAKE, "treasury collects forfeited stake");
    }

    function test_Live_SubmitPRIsOneShot() public {
        uint256 id = _post();
        _claim(id, w1);
        _submit(id, w1, "github.com/yeheskieltame/claudelance-sandbox/pull/E");

        vm.expectRevert(ClaudelanceCore.AlreadySubmitted.selector);
        _submit(id, w1, "github.com/yeheskieltame/claudelance-sandbox/pull/E-malicious");
    }

    function test_Live_StatsViewMatchesAccumulators() public view {
        (uint256 vol, uint256 rev, uint256 res, uint256 posters, uint256 workers) = core.getStats();
        assertEq(vol, core.totalBountyVolume());
        assertEq(rev, core.totalProtocolRevenue());
        assertEq(res, core.totalBountiesResolved());
        assertEq(posters, core.uniquePosterCount());
        assertEq(workers, core.uniqueWorkerCount());
    }
}
