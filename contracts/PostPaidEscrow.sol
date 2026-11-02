// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title PostPaidEscrow
/// @notice USDC milestone escrow with pull payments and optional arbitration.
/// @dev Submission is allowed at timestamp <= dueBy; refunds require timestamp > dueBy.
/// Review actions require timestamp < submittedAt + reviewPeriod; timeout claims require >=.
/// Approval has no review deadline. Only creation is paused. USDC-blocklisted accounts
/// remain credited and cannot redirect withdrawals. renounceOwnership is disabled so the owner
/// can never strand the contract in a paused state with nobody able to unpause.
contract PostPaidEscrow is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum DealStatus { Open, Active, Cancelled, Closed }
    enum MilestoneStatus { Pending, Submitted, Disputed, Released, Refunded, Split }
    enum ReleaseReason { Approved, Timeout }

    struct Deal {
        address brand;
        address creator;
        address arbiter;
        uint64 createdAt;
        uint32 reviewPeriod;
        uint16 feeBps;
        uint8 maxRevisions;
        DealStatus status;
        uint256 totalAmount;
        uint256 escrowed;
        string title;
        string briefURI;
    }
    struct Milestone {
        string label;
        uint256 amount;
        uint64 dueBy;
        uint64 submittedAt;
        uint64 disputedAt;
        uint8 revisionsUsed;
        MilestoneStatus status;
        string proofURI;
    }

    uint256 public constant MIN_MILESTONE = 10_000;
    uint256 public constant MAX_MILESTONES = 10;
    uint256 public constant MIN_REVIEW_PERIOD = 5 minutes;
    uint256 public constant MAX_REVIEW_PERIOD = 30 days;
    uint256 public constant MAX_REVISIONS = 3;
    uint256 public constant MAX_FEE_BPS = 200;
    uint256 public constant DISPUTE_TIMEOUT = 14 days;
    uint256 public constant BPS = 10_000;

    IERC20 public immutable usdc;
    uint256 public nextDealId = 1;
    uint256 public totalEscrowed;
    uint256 public totalWithdrawable;
    uint16 public protocolFeeBps;
    address public feeRecipient;
    mapping(address => uint256) public withdrawable;
    mapping(uint256 => Deal) private _deals;
    mapping(uint256 => Milestone[]) private _milestones;
    mapping(address => uint256[]) private _dealsOfBrand;
    mapping(address => uint256[]) private _dealsOfCreator;
    mapping(address => uint256[]) private _dealsOfArbiter;

    error NotBrand();
    error NotCreator();
    error NotArbiter();
    error InvalidParams();
    error InvalidDealStatus();
    error InvalidMilestoneStatus();
    error PastDue();
    error NotYetDue();
    error ReviewWindowClosed();
    error ReviewWindowOpen();
    error NoRevisionsLeft();
    error NoArbiter();
    error DisputeNotStale();
    error AmountMismatch();
    error NothingToWithdraw();
    error FeeTooHigh();

    event DealCreated(uint256 indexed dealId, address indexed brand, address indexed creator,
        address arbiter, uint256 totalAmount, uint16 feeBps, uint32 reviewPeriod, string title, string briefURI);
    event DealAccepted(uint256 indexed dealId, address indexed creator);
    event DealCancelled(uint256 indexed dealId, uint256 refunded);
    event DealClosed(uint256 indexed dealId);
    event CreatorExited(uint256 indexed dealId, uint256 refunded);
    event MilestoneSubmitted(uint256 indexed dealId, uint256 index, string proofURI);
    event RevisionRequested(uint256 indexed dealId, uint256 index, string note, uint64 newDueBy);
    event DisputeOpened(uint256 indexed dealId, uint256 index, string reason);
    event DisputeResolved(uint256 indexed dealId, uint256 index, uint16 creatorBps,
        uint256 creatorNet, uint256 brandPart, uint256 fee);
    event MilestoneReleased(uint256 indexed dealId, uint256 index, uint256 creatorNet, uint256 fee, ReleaseReason reason);
    event MilestoneRefunded(uint256 indexed dealId, uint256 index, uint256 amount);
    event Withdrawn(address indexed account, uint256 amount);
    event ProtocolFeeUpdated(uint16 oldBps, uint16 newBps);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);

    /// @notice Anyone may deploy with nonzero token, owner and fee recipient, and a fee <= 200 bps.
    constructor(IERC20 usdc_, address initialOwner, address feeRecipient_, uint16 initialFeeBps)
        Ownable(_validAddress(initialOwner))
    {
        _validAddress(address(usdc_));
        _validAddress(feeRecipient_);
        if (initialFeeBps > MAX_FEE_BPS) revert FeeTooHigh();
        usdc = usdc_;
        feeRecipient = feeRecipient_;
        protocolFeeBps = initialFeeBps;
    }

    /// @notice Any brand may fund a new deal when unpaused; every dueBy must be strictly in the future.
    /// @param creator The creator who must accept; not the caller and not zero.
    /// @param arbiter Optional dispute arbiter (zero disables disputes); not the brand or creator.
    /// @param title Deal title, 1..80 bytes.
    /// @param briefURI Link to the brief, 0..256 bytes.
    /// @param labels Milestone labels, 1..64 bytes each.
    /// @param amounts Milestone amounts in 6-decimal USDC units, each >= MIN_MILESTONE.
    /// @param dueBys Submission deadlines, each strictly after now.
    /// @param reviewPeriod Brand review window in seconds (5 minutes..30 days).
    /// @param maxRevisions Revisions allowed per milestone (0..3).
    /// @dev Requires approved USDC. Title 1..80, brief 0..256, labels 1..64 bytes;
    /// 1..10 matching milestones, amounts >= MIN_MILESTONE, review 5 minutes..30 days, revisions <= 3.
    /// @return dealId The newly funded deal identifier.
    function createDeal(address creator, address arbiter, string memory title, string memory briefURI,
        string[] memory labels, uint256[] memory amounts, uint64[] memory dueBys,
        uint32 reviewPeriod, uint8 maxRevisions) external whenNotPaused nonReentrant returns (uint256 dealId)
    {
        Deal memory d;
        d.brand = msg.sender;
        d.creator = creator;
        d.arbiter = arbiter;
        d.title = title;
        d.briefURI = briefURI;
        d.reviewPeriod = reviewPeriod;
        d.maxRevisions = maxRevisions;
        return _createDeal(d, labels, amounts, dueBys);
    }

    /// @notice Only the brand may cancel an Open deal at any time; all funds are credited back.
    function cancelDeal(uint256 dealId) external {
        Deal storage d = _deal(dealId);
        if (msg.sender != d.brand) revert NotBrand();
        if (d.status != DealStatus.Open) revert InvalidDealStatus();
        uint256 refunded = d.escrowed;
        Milestone[] storage ms = _milestones[dealId];
        for (uint256 i; i < ms.length; ++i) ms[i].status = MilestoneStatus.Refunded;
        d.status = DealStatus.Cancelled;
        _debit(d, refunded);
        _credit(d.brand, refunded);
        emit DealCancelled(dealId, refunded);
    }

    /// @notice Only the designated creator may accept an Open deal, even after its due dates.
    function acceptDeal(uint256 dealId) external {
        Deal storage d = _deal(dealId);
        if (msg.sender != d.creator) revert NotCreator();
        if (d.status != DealStatus.Open) revert InvalidDealStatus();
        d.status = DealStatus.Active;
        emit DealAccepted(dealId, msg.sender);
    }

    /// @notice Only the creator may submit a Pending milestone of an Active deal at timestamp <= dueBy.
    /// @dev Proof must contain 1..280 bytes; a late submission reverts PastDue.
    function submitMilestone(uint256 dealId, uint256 index, string calldata proofURI) external {
        (Deal storage d, Milestone storage m) = _pair(dealId, index);
        if (msg.sender != d.creator) revert NotCreator();
        if (d.status != DealStatus.Active) revert InvalidDealStatus();
        _requireStatus(m, MilestoneStatus.Pending);
        if (block.timestamp > m.dueBy) revert PastDue();
        if (bytes(proofURI).length == 0 || bytes(proofURI).length > 280) revert InvalidParams();
        m.submittedAt = uint64(block.timestamp);
        m.proofURI = proofURI;
        m.status = MilestoneStatus.Submitted;
        emit MilestoneSubmitted(dealId, index, proofURI);
    }

    /// @notice Only the brand may approve a Submitted milestone at any time, including after review ends.
    function approveMilestone(uint256 dealId, uint256 index) external {
        (Deal storage d, Milestone storage m) = _pair(dealId, index);
        if (msg.sender != d.brand) revert NotBrand();
        _requireStatus(m, MilestoneStatus.Submitted);
        _release(dealId, index, d, m, ReleaseReason.Approved);
    }

    /// @notice Only the brand may request revision while Submitted and timestamp < submittedAt + reviewPeriod.
    /// @dev Requires an unused revision; note is 0..280 bytes. Extends dueBy to at least now + reviewPeriod.
    function requestRevision(uint256 dealId, uint256 index, string calldata note) external {
        (Deal storage d, Milestone storage m) = _pair(dealId, index);
        if (msg.sender != d.brand) revert NotBrand();
        _requireStatus(m, MilestoneStatus.Submitted);
        _requireReviewOpen(d, m);
        if (m.revisionsUsed >= d.maxRevisions) revert NoRevisionsLeft();
        if (bytes(note).length > 280) revert InvalidParams();
        ++m.revisionsUsed;
        m.status = MilestoneStatus.Pending;
        uint64 extendedDue = uint64(block.timestamp + d.reviewPeriod);
        if (extendedDue > m.dueBy) m.dueBy = extendedDue;
        emit RevisionRequested(dealId, index, note, m.dueBy);
    }

    /// @notice Only the brand may dispute while Submitted and timestamp < submittedAt + reviewPeriod.
    /// @dev An arbiter must exist; reason is limited to 0..280 bytes.
    function openDispute(uint256 dealId, uint256 index, string calldata reason) external {
        (Deal storage d, Milestone storage m) = _pair(dealId, index);
        if (msg.sender != d.brand) revert NotBrand();
        if (d.arbiter == address(0)) revert NoArbiter();
        _requireStatus(m, MilestoneStatus.Submitted);
        _requireReviewOpen(d, m);
        if (bytes(reason).length > 280) revert InvalidParams();
        m.disputedAt = uint64(block.timestamp);
        m.status = MilestoneStatus.Disputed;
        emit DisputeOpened(dealId, index, reason);
    }

    /// @notice Only the arbiter may resolve a Disputed milestone at any time, allocating 0..10000 bps to creator.
    function resolveDispute(uint256 dealId, uint256 index, uint16 creatorBps) external {
        (Deal storage d, Milestone storage m) = _pair(dealId, index);
        if (msg.sender != d.arbiter) revert NotArbiter();
        _requireStatus(m, MilestoneStatus.Disputed);
        if (creatorBps > BPS) revert InvalidParams();
        _split(dealId, index, d, m, creatorBps);
    }

    /// @notice Anyone may resolve a Disputed milestone 50/50 at timestamp >= disputedAt + DISPUTE_TIMEOUT.
    function resolveStaleDispute(uint256 dealId, uint256 index) external {
        (Deal storage d, Milestone storage m) = _pair(dealId, index);
        _requireStatus(m, MilestoneStatus.Disputed);
        if (block.timestamp < uint256(m.disputedAt) + DISPUTE_TIMEOUT) revert DisputeNotStale();
        _split(dealId, index, d, m, 5000);
    }

    /// @notice Anyone may release a Submitted milestone at timestamp >= submittedAt + reviewPeriod.
    function claimAfterTimeout(uint256 dealId, uint256 index) external {
        (Deal storage d, Milestone storage m) = _pair(dealId, index);
        _requireStatus(m, MilestoneStatus.Submitted);
        if (block.timestamp < uint256(m.submittedAt) + d.reviewPeriod) revert ReviewWindowOpen();
        _release(dealId, index, d, m, ReleaseReason.Timeout);
    }

    /// @notice Anyone may refund a Pending milestone of an Active deal strictly after dueBy; never at equality.
    function refundMilestone(uint256 dealId, uint256 index) external {
        (Deal storage d, Milestone storage m) = _pair(dealId, index);
        if (d.status != DealStatus.Active) revert InvalidDealStatus();
        _requireStatus(m, MilestoneStatus.Pending);
        if (block.timestamp <= m.dueBy) revert NotYetDue();
        m.status = MilestoneStatus.Refunded;
        _debit(d, m.amount);
        _credit(d.brand, m.amount);
        emit MilestoneRefunded(dealId, index, m.amount);
        _closeIfTerminal(dealId, d);
    }

    /// @notice Only the creator may exit an Active deal at any time if at least one milestone is Pending.
    /// @dev Refunds only Pending milestones; submitted/disputed work and later revisions follow normal rules.
    function creatorExit(uint256 dealId) external {
        Deal storage d = _deal(dealId);
        if (msg.sender != d.creator) revert NotCreator();
        if (d.status != DealStatus.Active) revert InvalidDealStatus();
        uint256 refunded;
        Milestone[] storage ms = _milestones[dealId];
        for (uint256 i; i < ms.length; ++i) {
            if (ms[i].status == MilestoneStatus.Pending) {
                ms[i].status = MilestoneStatus.Refunded;
                refunded += ms[i].amount;
            }
        }
        if (refunded == 0) revert InvalidMilestoneStatus();
        _debit(d, refunded);
        _credit(d.brand, refunded);
        emit CreatorExited(dealId, refunded);
        _closeIfTerminal(dealId, d);
    }

    /// @notice Anyone with a nonzero credit may withdraw their entire balance to themselves at any time.
    /// @dev Accounting is cleared before token transfer; a blocked USDC transfer reverts without losing credit.
    function withdraw() external nonReentrant {
        uint256 amount = withdrawable[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        withdrawable[msg.sender] = 0;
        totalWithdrawable -= amount;
        usdc.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Only the owner may set a fee <= 200 bps at any time; existing deals retain their locked fee.
    function setProtocolFee(uint16 bps) external onlyOwner {
        if (bps > MAX_FEE_BPS) revert FeeTooHigh();
        uint16 oldBps = protocolFeeBps;
        protocolFeeBps = bps;
        emit ProtocolFeeUpdated(oldBps, bps);
    }

    /// @notice Only the owner may set a nonzero recipient at any time, affecting future fee credits only.
    function setFeeRecipient(address recipient) external onlyOwner {
        _validAddress(recipient);
        address oldRecipient = feeRecipient;
        feeRecipient = recipient;
        emit FeeRecipientUpdated(oldRecipient, recipient);
    }

    /// @notice Disabled: always reverts so ownership can only be rotated through the two-step transfer.
    /// @dev Callable only by the owner, and never succeeds.
    function renounceOwnership() public view override onlyOwner {
        revert InvalidParams();
    }

    /// @notice Only the owner may pause new deal creation when unpaused; all other deal actions remain available.
    function pause() external onlyOwner { _pause(); }

    /// @notice Only the owner may resume new deal creation when paused.
    function unpause() external onlyOwner { _unpause(); }

    /// @notice Anyone may read an existing deal at any time; unknown identifiers revert InvalidParams.
    /// @return The complete deal, including its remaining escrow and locked fee.
    function getDeal(uint256 dealId) external view returns (Deal memory) { return _deal(dealId); }

    /// @notice Anyone may read all milestones of an existing deal at any time.
    /// @return The complete ordered milestone array.
    function getMilestones(uint256 dealId) external view returns (Milestone[] memory) {
        _deal(dealId);
        return _milestones[dealId];
    }

    /// @notice Anyone may read a brand's deal identifiers at any time, including an empty list.
    /// @return All deals created by account, in creation order.
    function dealsOfBrand(address account) external view returns (uint256[] memory) { return _dealsOfBrand[account]; }

    /// @notice Anyone may read a creator's deal identifiers at any time, including an empty list.
    /// @return All deals assigned to account, in creation order.
    function dealsOfCreator(address account) external view returns (uint256[] memory) { return _dealsOfCreator[account]; }

    /// @notice Anyone may read an arbiter's deal identifiers at any time, including an empty list.
    /// @return All deals naming account as arbiter, in creation order.
    function dealsOfArbiter(address account) external view returns (uint256[] memory) { return _dealsOfArbiter[account]; }

    /// @notice Anyone may read state-only action eligibility for an existing milestone at any time; roles are ignored.
    /// @dev Submit uses <= dueBy, refund > dueBy; review uses < reviewEndsAt, timeout >= reviewEndsAt.
    /// Approval has no deadline. reviewEndsAt is zero unless Submitted. Wallet roles must be checked separately.
    function milestoneActions(uint256 dealId, uint256 index) external view returns (
        bool canSubmit, bool canApprove, bool canRequestRevision, bool canDispute,
        bool canClaimTimeout, bool canRefund, bool canResolveStale, uint64 reviewEndsAt)
    {
        (Deal storage d, Milestone storage m) = _pair(dealId, index);
        bool pendingActive = d.status == DealStatus.Active && m.status == MilestoneStatus.Pending;
        canSubmit = pendingActive && block.timestamp <= m.dueBy;
        canRefund = pendingActive && block.timestamp > m.dueBy;
        canApprove = m.status == MilestoneStatus.Submitted;
        if (canApprove) {
            reviewEndsAt = uint64(uint256(m.submittedAt) + d.reviewPeriod);
            bool reviewing = block.timestamp < reviewEndsAt;
            canRequestRevision = reviewing && m.revisionsUsed < d.maxRevisions;
            canDispute = reviewing && d.arbiter != address(0);
            canClaimTimeout = !reviewing;
        }
        canResolveStale = m.status == MilestoneStatus.Disputed
            && block.timestamp >= uint256(m.disputedAt) + DISPUTE_TIMEOUT;
    }

    function _createDeal(Deal memory d, string[] memory labels, uint256[] memory amounts,
        uint64[] memory dueBys) internal returns (uint256 dealId)
    {
        uint256 n = labels.length;
        if (n == 0 || n > MAX_MILESTONES || amounts.length != n || dueBys.length != n) revert InvalidParams();
        if (d.creator == address(0) || d.creator == d.brand) revert InvalidParams();
        if (d.arbiter != address(0) && (d.arbiter == d.brand || d.arbiter == d.creator)) revert InvalidParams();
        if (bytes(d.title).length == 0 || bytes(d.title).length > 80 || bytes(d.briefURI).length > 256) revert InvalidParams();
        if (d.reviewPeriod < MIN_REVIEW_PERIOD || d.reviewPeriod > MAX_REVIEW_PERIOD || d.maxRevisions > MAX_REVISIONS) revert InvalidParams();
        for (uint256 i; i < n; ++i) {
            if (amounts[i] < MIN_MILESTONE || dueBys[i] <= block.timestamp
                || bytes(labels[i]).length == 0 || bytes(labels[i]).length > 64) revert InvalidParams();
            // Validate the sum explicitly so invalid overflowing amounts use InvalidParams.
            if (amounts[i] > type(uint256).max - d.totalAmount) revert InvalidParams();
            d.totalAmount += amounts[i];
        }
        d.escrowed = d.totalAmount;
        d.createdAt = uint64(block.timestamp);
        d.feeBps = protocolFeeBps;
        dealId = nextDealId++;
        _deals[dealId] = d;
        for (uint256 i; i < n; ++i) {
            _milestones[dealId].push(Milestone(labels[i], amounts[i], dueBys[i], 0, 0, 0, MilestoneStatus.Pending, ""));
        }
        _dealsOfBrand[d.brand].push(dealId);
        _dealsOfCreator[d.creator].push(dealId);
        if (d.arbiter != address(0)) _dealsOfArbiter[d.arbiter].push(dealId);
        totalEscrowed += d.totalAmount;
        uint256 beforeBalance = usdc.balanceOf(address(this));
        usdc.safeTransferFrom(d.brand, address(this), d.totalAmount);
        uint256 afterBalance = usdc.balanceOf(address(this));
        if (afterBalance < beforeBalance || afterBalance - beforeBalance != d.totalAmount) revert AmountMismatch();
        _emitCreated(dealId, d);
    }

    function _emitCreated(uint256 dealId, Deal memory d) internal {
        emit DealCreated(dealId, d.brand, d.creator, d.arbiter, d.totalAmount, d.feeBps, d.reviewPeriod, d.title, d.briefURI);
    }

    function _release(uint256 dealId, uint256 index, Deal storage d, Milestone storage m, ReleaseReason reason) internal {
        uint256 fee = m.amount * d.feeBps / BPS;
        uint256 creatorNet = m.amount - fee;
        m.status = MilestoneStatus.Released;
        _debit(d, m.amount);
        _credit(d.creator, creatorNet);
        _credit(feeRecipient, fee);
        emit MilestoneReleased(dealId, index, creatorNet, fee, reason);
        _closeIfTerminal(dealId, d);
    }

    function _split(uint256 dealId, uint256 index, Deal storage d, Milestone storage m, uint16 creatorBps) internal {
        uint256 creatorGross = m.amount * creatorBps / BPS;
        uint256 brandPart = m.amount - creatorGross;
        uint256 fee = creatorGross * d.feeBps / BPS;
        uint256 creatorNet = creatorGross - fee;
        m.status = creatorBps == BPS ? MilestoneStatus.Released
            : creatorBps == 0 ? MilestoneStatus.Refunded : MilestoneStatus.Split;
        _debit(d, m.amount);
        _credit(d.creator, creatorNet);
        _credit(feeRecipient, fee);
        _credit(d.brand, brandPart);
        emit DisputeResolved(dealId, index, creatorBps, creatorNet, brandPart, fee);
        _closeIfTerminal(dealId, d);
    }

    function _credit(address account, uint256 amount) internal {
        withdrawable[account] += amount;
        totalWithdrawable += amount;
    }

    function _debit(Deal storage d, uint256 amount) internal {
        d.escrowed -= amount;
        totalEscrowed -= amount;
    }

    function _closeIfTerminal(uint256 dealId, Deal storage d) internal {
        if (d.status != DealStatus.Active) return;
        Milestone[] storage ms = _milestones[dealId];
        for (uint256 i; i < ms.length; ++i) {
            if (uint8(ms[i].status) < uint8(MilestoneStatus.Released)) return;
        }
        d.status = DealStatus.Closed;
        emit DealClosed(dealId);
    }

    function _deal(uint256 dealId) internal view returns (Deal storage d) {
        if (dealId == 0 || dealId >= nextDealId) revert InvalidParams();
        return _deals[dealId];
    }

    function _pair(uint256 dealId, uint256 index) internal view returns (Deal storage d, Milestone storage m) {
        d = _deal(dealId);
        if (index >= _milestones[dealId].length) revert InvalidParams();
        m = _milestones[dealId][index];
    }

    function _requireStatus(Milestone storage m, MilestoneStatus status) internal view {
        if (m.status != status) revert InvalidMilestoneStatus();
    }

    function _requireReviewOpen(Deal storage d, Milestone storage m) internal view {
        if (block.timestamp >= uint256(m.submittedAt) + d.reviewPeriod) revert ReviewWindowClosed();
    }

    function _validAddress(address account) internal pure returns (address) {
        if (account == address(0)) revert InvalidParams();
        return account;
    }
}
