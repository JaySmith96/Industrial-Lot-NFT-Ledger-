// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IndustrialBatchProtocol
 * @author Jeffrey Smith (Solutions Architect)
 * @notice Implements Physical-to-Digital Interlocking for Chemical Manufacturing
 */
contract IndustrialBatchProtocol {
    
    // 1. UPDATE: Added 'Shipped' to the status list so we can track the final step
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
    
    // 2. NEW: Supervisor State Variable
    address public supervisor;

    event EventAnnouncement(uint256 indexed batchId, string message, uint256 timestamp);
    event BatchScrapped(uint256 indexed batchId, string reason);
    // 3. NEW: Specific Event for Shipping
    event BatchShipped(uint256 indexed batchId, address approvedBy);

    // 4. NEW: Constructor to set the Supervisor when deployed
    constructor() {
        supervisor = msg.sender;
    }

    // Modifier: Ensures Operator has the correct Tier
    modifier onlyQualified(uint256 _vesselId) {
        require(operatorTier[msg.sender] >= vesselTierRequirement[_vesselId], 
        "SECURITY: Operator tier insufficient for this vessel.");
        _;
    }

    // Modifier: High-trust Governance
    modifier onlyRole(bytes32 role) {
        // Implementation of Role-Based Access Control logic would go here
        _;
    }

    // 5. NEW: The Supervisor Modifier
    modifier onlySupervisor() {
        require(msg.sender == supervisor, "Only the supervisor can perform this action");
        _;
    }

    function startBatch(uint256 _batchId, uint256 _vesselId) external onlyQualified(_vesselId) {
        batches[_batchId].status = BatchStatus.InProcess;
        batches[_batchId].currentOperator = msg.sender;
        batches[_batchId].vesselId = _vesselId;
        batches[_batchId].lastEventTimestamp = block.timestamp;
        
        emit EventAnnouncement(_batchId, "Batch started via Biometric/NFC Handshake", block.timestamp);
    }

    function logProcessUpdate(uint256 _batchId, bool _isSpecGood) external {
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
        emit EventAnnouncement(_batchId, "MANAGER OVERRIDE: Physical witness verified for QR scan.", block.timestamp);
    }

    function finalizeBatch(uint256 _batchId, bool _approved) external onlyRole("QC_TECH") {
        if (_approved && !batches[_batchId].outOfSpec) {
            batches[_batchId].status = BatchStatus.Approved;
        } else {
            batches[_batchId].status = BatchStatus.Burned;
            emit BatchScrapped(_batchId, "Failed Quality Standards or Manual Scrap Triggered");
        }
    }

    // 6. NEW: The Shipping Logic
    // This connects the "Approved" status to the "Logistics" world
    function approveForShipping(uint256 _batchId) external onlySupervisor {
        // Logic Check: Can't ship something that hasn't been approved by QC yet
        require(batches[_batchId].status == BatchStatus.Approved, "Batch must be QC Approved before shipping");
        
        batches[_batchId].status = BatchStatus.Shipped;
        
        emit BatchShipped(_batchId, msg.sender);
        emit EventAnnouncement(_batchId, "LOGISTICS: Batch released to carrier", block.timestamp);
    }
}
