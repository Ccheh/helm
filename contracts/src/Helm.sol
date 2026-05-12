// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IMetricOracle} from "./interfaces/IMetricOracle.sol";

/// @title  Helm — Futarchy for Autonomous Agent Coordination
/// @notice An on-chain implementation of Robin Hanson's *futarchy* mechanism:
///         decisions are made by comparing prediction-market prices on
///         conditional outcomes. The branch whose conditional market predicts
///         the higher expected metric is the chosen decision; bets on the
///         rejected branch are refunded.
///
///         **Why for agents specifically.** Futarchy has been theoretically
///         attractive for 30 years (Hanson, 1996) but has never been deployed
///         at meaningful scale. The two main reasons humans don't adopt it:
///         (a) people get attached to predictions and bet emotionally; (b)
///         bet sizes are too coarse for fine-grained signal. Agents on Arc
///         don't have problem (a) — they have no ego — and Arc's sub-cent
///         USDC-native gas eliminates problem (b). This makes agent groups
///         the first plausible deployment audience for futarchy at scale.
///
///         **What Helm does NOT try to be.** A general prediction market
///         (use Polymarket / UMA for that). A governance token system (no
///         token — Helm has no native asset). An oracle (Helm consumes
///         oracles via IMetricOracle).
///
/// @dev    Each issue has 4 parimutuel pools:
///           pool[X][YES], pool[X][NO]       — bets conditional on X chosen
///           pool[NOT_X][YES], pool[NOT_X][NO] — bets conditional on NOT_X chosen
///
///         Lifecycle:
///           None -> Open (after proposeIssue)
///           Open -> Decided (after decide() at decideAt)
///           Decided -> Resolved (after resolve() at resolveAt with oracle data)
///
///         Decision rule (futarchy):
///           p_X     = pool[X][YES] / (pool[X][YES] + pool[X][NO])
///           p_NOT_X = pool[NOT_X][YES] / (pool[NOT_X][YES] + pool[NOT_X][NO])
///           winner = X if p_X > p_NOT_X else NOT_X
///         Comparison is done by cross-multiplication to avoid division.
///
///         Settlement rule (parimutuel):
///           Rejected-branch bets are fully refunded.
///           In the chosen branch:
///             if metric > threshold: YES pool wins, splits the NO pool pro-rata
///             else:                  NO pool wins,  splits the YES pool pro-rata
///
/// @dev    No admin keys. No upgrade proxy. No protocol fees in v0.
contract Helm is ReentrancyGuard {
    /* ------------------------------------------------------------------- */
    /*                              constants                              */
    /* ------------------------------------------------------------------- */

    /// @notice Minimum single bet. Filters dust and protects the parimutuel
    ///         math from precision issues. 0.0001 ether-units of native USDC.
    uint256 public constant MIN_BET = 0.0001 ether;

    /// @notice Branch identifier: 0 = X, 1 = NOT_X.
    uint8 public constant BRANCH_X     = 0;
    uint8 public constant BRANCH_NOT_X = 1;

    /// @notice Side identifier: 0 = YES (metric > threshold), 1 = NO (else).
    uint8 public constant SIDE_YES = 0;
    uint8 public constant SIDE_NO  = 1;

    /* ------------------------------------------------------------------- */
    /*                              types                                  */
    /* ------------------------------------------------------------------- */

    enum Status { None, Open, Decided, Resolved }

    struct Issue {
        address proposer;
        address metricOracle;
        bytes32 metricKey;
        uint256 threshold;
        uint64  decideAt;
        uint64  resolveAt;
        uint8   defaultDecision;    // branch chosen if no bets / tie
        Status  status;
        uint8   chosenBranch;       // set in decide()
        bool    metricMet;          // set in resolve(): metric > threshold
        uint256 metricValue;        // observed value, for transparency
    }

    /* ------------------------------------------------------------------- */
    /*                              storage                                */
    /* ------------------------------------------------------------------- */

    /// @notice issueId => Issue
    mapping(bytes32 => Issue) public issues;

    /// @notice issueId => branch => side => total parimutuel pool
    mapping(bytes32 => mapping(uint8 => mapping(uint8 => uint256))) public totalPool;

    /// @notice issueId => branch => side => user => their stake in pool
    mapping(bytes32 => mapping(uint8 => mapping(uint8 => mapping(address => uint256)))) public userBet;

    /// @notice Monotonic counter for deterministic issueId derivation.
    uint256 public issueCount;

    /* ------------------------------------------------------------------- */
    /*                              events                                 */
    /* ------------------------------------------------------------------- */

    event IssueProposed(
        bytes32 indexed issueId,
        address indexed proposer,
        address indexed metricOracle,
        bytes32 metricKey,
        uint256 threshold,
        uint64  decideAt,
        uint64  resolveAt,
        uint8   defaultDecision
    );
    event BetPlaced(
        bytes32 indexed issueId,
        address indexed bettor,
        uint8 branch,
        uint8 side,
        uint256 amount,
        uint256 newPoolTotal
    );
    event IssueDecided(bytes32 indexed issueId, uint8 chosenBranch, uint256 pX_yes_x_totalNotX, uint256 pNotX_yes_x_totalX);
    event IssueResolved(bytes32 indexed issueId, uint8 chosenBranch, bool metricMet, uint256 metricValue);
    event Claimed(bytes32 indexed issueId, address indexed user, uint256 amount);

    /* ------------------------------------------------------------------- */
    /*                              errors                                 */
    /* ------------------------------------------------------------------- */

    error ZeroAmount();
    error BetBelowMin();
    error InvalidBranch();
    error InvalidSide();
    error InvalidDefault();
    error InvalidTimes();
    error IssueExists();
    error IssueNotOpen();
    error IssueNotDecided();
    error IssueNotResolved();
    error DecideTooEarly();
    error ResolveTooEarly();
    error OracleNotReady();
    error NothingToClaim();
    error TransferFailed();

    /* ------------------------------------------------------------------- */
    /*                              propose                                */
    /* ------------------------------------------------------------------- */

    /// @notice Propose a new futarchy issue. The issueId is deterministic and
    ///         derived from `(proposer, issueCount, block.chainid)`. No fee.
    ///
    /// @param metricOracle      Contract implementing IMetricOracle.
    /// @param metricKey         Opaque key the oracle uses to identify this issue.
    /// @param threshold         Value the observed metric is compared against
    ///                          (YES wins if metric > threshold).
    /// @param decideAt          Timestamp after which decide() may be called.
    /// @param resolveAt         Timestamp after which resolve() may be called.
    ///                          Must be strictly later than decideAt.
    /// @param defaultDecision   0 (X) or 1 (NOT_X); used if a branch has zero
    ///                          bets or the comparison is exactly equal.
    function proposeIssue(
        address metricOracle,
        bytes32 metricKey,
        uint256 threshold,
        uint64  decideAt,
        uint64  resolveAt,
        uint8   defaultDecision
    ) external returns (bytes32 issueId) {
        if (decideAt <= block.timestamp || resolveAt <= decideAt) revert InvalidTimes();
        if (defaultDecision > 1) revert InvalidDefault();

        unchecked { issueCount++; }
        issueId = keccak256(abi.encode(msg.sender, issueCount, block.chainid));

        if (issues[issueId].status != Status.None) revert IssueExists();

        issues[issueId] = Issue({
            proposer:        msg.sender,
            metricOracle:    metricOracle,
            metricKey:       metricKey,
            threshold:       threshold,
            decideAt:        decideAt,
            resolveAt:       resolveAt,
            defaultDecision: defaultDecision,
            status:          Status.Open,
            chosenBranch:    0,
            metricMet:       false,
            metricValue:     0
        });

        emit IssueProposed(
            issueId,
            msg.sender,
            metricOracle,
            metricKey,
            threshold,
            decideAt,
            resolveAt,
            defaultDecision
        );
    }

    /* ------------------------------------------------------------------- */
    /*                              bet                                    */
    /* ------------------------------------------------------------------- */

    /// @notice Place a parimutuel bet on a (branch, side) pool. Sends USDC
    ///         (native gas) as msg.value.
    function bet(bytes32 issueId, uint8 branch, uint8 side) external payable nonReentrant {
        if (msg.value < MIN_BET) revert BetBelowMin();
        if (branch > 1) revert InvalidBranch();
        if (side > 1) revert InvalidSide();

        Issue storage iss = issues[issueId];
        if (iss.status != Status.Open) revert IssueNotOpen();
        if (block.timestamp >= iss.decideAt) revert IssueNotOpen();   // betting closes at decideAt

        userBet[issueId][branch][side][msg.sender] += msg.value;
        uint256 newTotal = totalPool[issueId][branch][side] + msg.value;
        totalPool[issueId][branch][side] = newTotal;

        emit BetPlaced(issueId, msg.sender, branch, side, msg.value, newTotal);
    }

    /* ------------------------------------------------------------------- */
    /*                              decide                                 */
    /* ------------------------------------------------------------------- */

    /// @notice Pick the winning branch by comparing conditional P(YES) prices.
    ///         Anyone can call after decideAt. The rejected branch's bets
    ///         become refundable via claim().
    function decide(bytes32 issueId) external {
        Issue storage iss = issues[issueId];
        if (iss.status != Status.Open) revert IssueNotOpen();
        if (block.timestamp < iss.decideAt) revert DecideTooEarly();

        uint256 xYes     = totalPool[issueId][BRANCH_X][SIDE_YES];
        uint256 xNo      = totalPool[issueId][BRANCH_X][SIDE_NO];
        uint256 notxYes  = totalPool[issueId][BRANCH_NOT_X][SIDE_YES];
        uint256 notxNo   = totalPool[issueId][BRANCH_NOT_X][SIDE_NO];

        uint256 totalX    = xYes + xNo;
        uint256 totalNotX = notxYes + notxNo;

        uint8 chosen;
        // Compare P(YES|X) vs P(YES|NOT_X) = xYes/totalX vs notxYes/totalNotX
        // by cross-multiplication: xYes * totalNotX vs notxYes * totalX
        if (totalX == 0 && totalNotX == 0) {
            chosen = iss.defaultDecision;
        } else if (totalX == 0) {
            // No bets on X — pick NOT_X (X is informationless)
            chosen = BRANCH_NOT_X;
        } else if (totalNotX == 0) {
            chosen = BRANCH_X;
        } else {
            uint256 lhs = xYes * totalNotX;
            uint256 rhs = notxYes * totalX;
            if (lhs > rhs) chosen = BRANCH_X;
            else if (lhs < rhs) chosen = BRANCH_NOT_X;
            else chosen = iss.defaultDecision;
        }

        iss.chosenBranch = chosen;
        iss.status = Status.Decided;
        emit IssueDecided(issueId, chosen, xYes * totalNotX, notxYes * totalX);
    }

    /* ------------------------------------------------------------------- */
    /*                              resolve                                */
    /* ------------------------------------------------------------------- */

    /// @notice Consult the oracle, mark the issue resolved, and unlock claims
    ///         for the chosen branch.
    function resolve(bytes32 issueId, bytes calldata oracleData) external {
        Issue storage iss = issues[issueId];
        if (iss.status != Status.Decided) revert IssueNotDecided();
        if (block.timestamp < iss.resolveAt) revert ResolveTooEarly();
        if (!IMetricOracle(iss.metricOracle).isReady(issueId)) revert OracleNotReady();

        uint256 value = IMetricOracle(iss.metricOracle).getMetric(issueId, oracleData);
        bool met = value > iss.threshold;

        iss.metricValue = value;
        iss.metricMet = met;
        iss.status = Status.Resolved;

        emit IssueResolved(issueId, iss.chosenBranch, met, value);
    }

    /* ------------------------------------------------------------------- */
    /*                              claim                                  */
    /* ------------------------------------------------------------------- */

    /// @notice Withdraw any payout owed to msg.sender for this issue.
    ///         Callable any time after decide(). Calling again after resolve()
    ///         pays out chosen-branch winnings. Idempotent; zeroes user state
    ///         as it goes.
    function claim(bytes32 issueId) external nonReentrant returns (uint256 payout) {
        Issue storage iss = issues[issueId];
        if (iss.status < Status.Decided) revert IssueNotDecided();

        uint8 chosen   = iss.chosenBranch;
        uint8 rejected = chosen == BRANCH_X ? BRANCH_NOT_X : BRANCH_X;

        // 1. Refund all rejected-branch bets (full principal, both sides).
        uint256 refundYes = userBet[issueId][rejected][SIDE_YES][msg.sender];
        uint256 refundNo  = userBet[issueId][rejected][SIDE_NO][msg.sender];
        if (refundYes > 0) {
            payout += refundYes;
            userBet[issueId][rejected][SIDE_YES][msg.sender] = 0;
        }
        if (refundNo > 0) {
            payout += refundNo;
            userBet[issueId][rejected][SIDE_NO][msg.sender] = 0;
        }

        // 2. If resolved, pay out chosen-branch winners and zero loser bets.
        if (iss.status == Status.Resolved) {
            uint8 winnerSide = iss.metricMet ? SIDE_YES : SIDE_NO;
            uint8 loserSide  = winnerSide == SIDE_YES ? SIDE_NO : SIDE_YES;

            uint256 winnerBet = userBet[issueId][chosen][winnerSide][msg.sender];
            if (winnerBet > 0) {
                uint256 winnerPool = totalPool[issueId][chosen][winnerSide];
                uint256 loserPool  = totalPool[issueId][chosen][loserSide];
                // payout += principal + share of loser pool
                payout += winnerBet + (winnerBet * loserPool) / winnerPool;
                userBet[issueId][chosen][winnerSide][msg.sender] = 0;
            }
            // Zero loser-side bets (no payout, but ensures idempotency).
            userBet[issueId][chosen][loserSide][msg.sender] = 0;
        }

        if (payout == 0) revert NothingToClaim();
        emit Claimed(issueId, msg.sender, payout);

        (bool ok,) = msg.sender.call{value: payout}("");
        if (!ok) revert TransferFailed();
    }

    /* ------------------------------------------------------------------- */
    /*                              views                                  */
    /* ------------------------------------------------------------------- */

    /// @notice Snapshot of an issue's 4 pool totals.
    function pools(bytes32 issueId)
        external
        view
        returns (uint256 xYes, uint256 xNo, uint256 notxYes, uint256 notxNo)
    {
        xYes    = totalPool[issueId][BRANCH_X][SIDE_YES];
        xNo     = totalPool[issueId][BRANCH_X][SIDE_NO];
        notxYes = totalPool[issueId][BRANCH_NOT_X][SIDE_YES];
        notxNo  = totalPool[issueId][BRANCH_NOT_X][SIDE_NO];
    }

    /// @notice Current implied P(YES | branch) for each branch, scaled by 1e18.
    ///         Returns 0 for a branch with no bets.
    function prices(bytes32 issueId) external view returns (uint256 pX, uint256 pNotX) {
        uint256 xYes    = totalPool[issueId][BRANCH_X][SIDE_YES];
        uint256 xNo     = totalPool[issueId][BRANCH_X][SIDE_NO];
        uint256 notxYes = totalPool[issueId][BRANCH_NOT_X][SIDE_YES];
        uint256 notxNo  = totalPool[issueId][BRANCH_NOT_X][SIDE_NO];
        uint256 totalX    = xYes + xNo;
        uint256 totalNotX = notxYes + notxNo;
        pX     = totalX    == 0 ? 0 : (xYes    * 1e18) / totalX;
        pNotX  = totalNotX == 0 ? 0 : (notxYes * 1e18) / totalNotX;
    }
}
