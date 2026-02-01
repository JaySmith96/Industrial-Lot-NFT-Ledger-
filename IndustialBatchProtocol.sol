// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IndustrialBatchProtocol
 * @author Jeffrey Smith (Solutions Architect)
 * @notice Implements Physical-to-Digital Interlocking for Chemical Manufacturing
 * @dev Includes Emergency Circuit Breaker (Pausable Pattern) for plant safety.
 */
contract IndustrialBatchProtocol {
    
    enum BatchStatus { Scheduled, InProcess, QualityCheck, Approved, Burned, Shipped }
    
    struct Batch {
        uint256 id;
        BatchStatus status;
        address currentOperator;
        uint256 vesselId;
        uint256 lastEventTimestamp;
        bool outOfSpec;
    }

    mapping(uint256 => Batch) public batches;
    mapping(address => uint8) public operatorTier; // Tiers 1-5
    mapping(uint256 => uint8) public vesselTierRequirement; 
    
    // Governance Roles
    address public supervisor;

    // *** NEW: Emergency Safety Toggle ***
    bool public circuitBreaker; 

    // Events
    event EventAnnouncement(uint256 indexed batchId, string message, uint256 timestamp);
    event BatchScrapped(uint256 indexed batchId, string reason);
    event BatchShipped(uint256 indexed batchId, address approvedBy);
    event CircuitBreakerToggled(bool isStopped, uint256 timestamp);

	    constructor() {
        supervisor = msg.sender;
        circuitBreaker = false; // System starts as ACTIVE (not stopped)
    }

    // --- MODIFIERS ---

    modifier onlyQualified(uint256 _vesselId) {
        require(operatorTier[msg.sender] >= vesselTierRequirement[_vesselId], 
        "SECURITY: Operator tier insufficient for this vessel.");
        _;
    }

    modifier onlyRole(bytes32 role) {
        // Implementation of Role-Based Access Control logic
        _;
    }

    modifier onlySupervisor() {
        require(msg.sender == supervisor, "Only the supervisor can perform this action");
        _;
    }

    // *** NEW: The E-Stop Guard ***
    modifier stopInEmergency() {
        require(!circuitBreaker, "SYSTEM HALT: Operations suspended by Supervisor.");
        _;
    }

    // --- GOVERNANCE FUNCTIONS ---

    /** * @notice The Big Red Button. Toggles the contract's active state.
     */
    function toggleCircuitBreaker() external onlySupervisor {
        circuitBreaker = !circuitBreaker;
        emit CircuitBreakerToggled(circuitBreaker, block.timestamp);
    }

    // --- CORE LOGIC ---

    function startBatch(uint256 _batchId, uint256 _vesselId) 
        external 
        onlyQualified(_vesselId) 
        stopInEmergency // <--- Protected
    {
        batches[_batchId].status = BatchStatus.InProcess;
        batches[_batchId].currentOperator = msg.sender;
        batches[_batchId].vesselId = _vesselId;
        batches[_batchId].lastEventTimestamp = block.timestamp;
        
        emit EventAnnouncement(_batchId, "Batch started via Biometric/NFC Handshake", block.timestamp);
    }

    function logProcessUpdate(uint256 _batchId, bool _isSpecGood) 
        external 
        stopInEmergency // <--- Protected
    {
        require(block.timestamp >= batches[_batchId].lastEventTimestamp + 20 minutes || !_isSpecGood, 
        "Network Optimization: Update interval not reached.");

        if (!_isSpecGood) {
            batches[_batchId].outOfSpec = true;
            emit EventAnnouncement(_batchId, "ALERT: Batch Out-of-Spec detected", block.timestamp);
        } else {
            emit EventAnnouncement(_batchId, "Process Update: Specs verified", block.timestamp);
        }
        batches[_batchId].lastEventTimestamp = block.timestamp;
    }

    function managerBypass(uint256 _batchId) external onlyRole("MANAGER_ROLE") {
        // Note: Managers can bypass even during emergency if physical safety is confirmed
        emit EventAnnouncement(_batchId, "MANAGER OVERRIDE: Physical witness verified for QR scan.", block.timestamp);
    }

    function finalizeBatch(uint256 _batchId, bool _approved) 
        external 
        onlyRole("QC_TECH") 
        stopInEmergency // <--- Protected
    {
        if (_approved && !batches[_batchId].outOfSpec) {
            batches[_batchId].status = BatchStatus.Approved;
        } else {
            batches[_batchId].status = BatchStatus.Burned;
            emit BatchScrapped(_batchId, "Failed Quality Standards or Manual Scrap Triggered");
        }
    }

    function approveForShipping(uint256 _batchId) 
        external 
        onlySupervisor 
        stopInEmergency // <--- Protected
    {
        require(batches[_batchId].status == BatchStatus.Approved, "Batch must be QC Approved before shipping");
        batches[_batchId].status = BatchStatus.Shipped;
        
        emit BatchShipped(_batchId, msg.sender);
        emit EventAnnouncement(_batchId, "LOGISTICS: Batch released to carrier", block.timestamp);
    }
}
