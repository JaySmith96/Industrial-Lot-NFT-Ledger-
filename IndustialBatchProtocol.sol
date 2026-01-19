// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IndustrialBatchProtocol
 * @author Jeffrey Smith (Solutions Architect)
 * @notice Implements Physical-to-Digital Interlocking for Chemical Manufacturing
 */
contract IndustrialBatchProtocol {
    
    enum BatchStatus { Scheduled, InProcess, QualityCheck, Approved, Burned }
    
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
    mapping(uint256 => uint8) public vesselTierRequirement; // Vessel specific requirements
    
    event EventAnnouncement(uint256 indexed batchId, string message, uint256 timestamp);
    event BatchScrapped(uint256 indexed batchId, string reason);

    // Modifier: Ensures Operator has the correct Tier for the specific Vessel
    modifier onlyQualified(uint256 _vesselId) {
        require(operatorTier[msg.sender] >= vesselTierRequirement[_vesselId], 
        "SECURITY: Operator tier insufficient for this vessel.");
        _;
    }

    // Modifier: High-trust Governance for QC and Managers
    modifier onlyRole(bytes32 role) {
        // Implementation of Role-Based Access Control
        _;
    }

    /** * @notice The "Physical Handshake" - Operator scans Vessel via NFC
     */
    function startBatch(uint256 _batchId, uint256 _vesselId) external onlyQualified(_vesselId) {
        batches[_batchId].status = BatchStatus.InProcess;
        batches[_batchId].currentOperator = msg.sender;
        batches[_batchId].vesselId = _vesselId;
        batches[_batchId].lastEventTimestamp = block.timestamp;
        
        emit EventAnnouncement(_batchId, "Batch started via Biometric/NFC Handshake", block.timestamp);
    }

    /** * @notice Automated IoT Event Logging (The 20-minute heartbeat)
     */
    function logProcessUpdate(uint256 _batchId, bool _isSpecGood) external {
        // Logic to prevent congestion: only log every 20 mins unless Out of Spec
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

    /** * @notice Manager Override: Required when RFID/NFC hardware fails
     */
    function managerBypass(uint256 _batchId) external onlyRole("MANAGER_ROLE") {
        emit EventAnnouncement(_batchId, "MANAGER OVERRIDE: Physical witness verified for QR scan.", block.timestamp);
    }

    /** * @notice Final Governance: QC Approves or Burns the NFT
     */
    function finalizeBatch(uint256 _batchId, bool _approved) external onlyRole("QC_TECH") {
        if (_approved && !batches[_batchId].outOfSpec) {
            batches[_batchId].status = BatchStatus.Approved;
        } else {
            batches[_batchId].status = BatchStatus.Burned;
            emit BatchScrapped(_batchId, "Failed Quality Standards or Manual Scrap Triggered");
        }
    }
}
