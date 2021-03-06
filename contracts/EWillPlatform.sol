pragma solidity ^0.4.24;

import 'zeppelin-solidity/contracts/ownership/Ownable.sol';
import './EWillFinanceIf.sol';
import './EWillAccountIf.sol';
import './EWillEscrowIf.sol';


contract EWillPlatform is Ownable {
    // Custom Types
    enum WillState { None, Created, Activated, Pending, Claimed, Rejected }

    struct Will {
        uint256     willId;
        uint256     storageId;
        uint256     annualFee;
        uint256     newFee;
        uint256     activationFee;
        uint256     beneficiaryHash;
        uint256     decryptionKey;
        address     owner;
        uint64      updatedAt;
        address     provider;
        uint64      validTill;
        WillState   state;
    }

    // Constants
    string constant public name = 'E-Will Platform';
    uint64 constant private oneYear = uint64(365 days);

    // State Variables
    mapping (uint256 => Will) public wills;
    //todo: remove both mappings and add events instead
    mapping (address => uint256[]) public userWills;
    mapping (uint256 => uint256[]) public beneficiaryWills;

    EWillFinanceIf public financeWallet;
    EWillEscrowIf public escrowWallet;

    // Events
    event WillCreated(address indexed owner, address indexed provider, uint256 willId);
    event WillStateUpdated(uint256 indexed willId, address indexed owner, WillState newState);
    event WillRefreshed(uint256 indexed willId, address indexed owner);
    event WillProlonged(uint256 indexed willId, address indexed owner, uint256 validTill);

    // Modifiers
    modifier onlyWillOwner(uint256 _willId) {
        Will storage will = wills[_willId];
        require(will.owner == msg.sender);
        _;
    }

    modifier onlyProvider(uint256 _willId) {
        Will storage will = wills[_willId];
        address provider = escrowWallet.providerAddress(msg.sender);
        require(will.provider == provider);
        _;
    }

    // Constructor
    constructor(address _finance, address _escrow) public {
        financeWallet = EWillFinanceIf(_finance);
        escrowWallet = EWillEscrowIf(_escrow);
    }

    // Finance calculations
    function annualPlatformFee() public view returns (uint256) {
        return financeWallet.platformFee();
    }

    function creatingFee(uint256 _annualFee) public pure returns (uint256) {
        return _annualFee * 12 / 10;
    }

    function prolongingFee(uint256 _annualFee) public pure returns (uint256) {
        return _annualFee;
    }

    function activatingReward(uint256 _annualFee) private pure returns (uint256) {
        return _annualFee / 10;
    }

    function refreshingReward(uint256 _annualFee) private pure returns (uint256) {
        return _annualFee / 12;
    }

    function claimingReward(uint256 _annualFee) private pure returns (uint256) {
        //todo: it's wrong. Need to return the 10% of the first year annual fee
        return _annualFee / 10;
    }

    function totalFee(address _provider, bool _referrer) public view returns (uint256 fee, uint256 refReward) {
        (fee, ) = escrowWallet.providerInfo(_provider);
        return financeWallet.totalFee(creatingFee(fee), _referrer);
    }

    function totalFeeEthers(address _provider, bool _referrer) public view returns (uint256 fee, uint256 refReward) {
        (fee, ) = escrowWallet.providerInfo(_provider);
        return financeWallet.totalFeeEthers(creatingFee(fee), _referrer);
    }

    function totalFeeTokens(address _provider, bool _referrer) public view returns (uint256 fee, uint256 refReward) {
        (fee, ) = escrowWallet.providerInfo(_provider);
        return financeWallet.totalFeeTokens(creatingFee(fee), _referrer);
    }

    // Public Will
    function numberOfUserWills(address _user) public view returns (uint256) {
        return userWills[_user].length;
    }

    function numberOfBeneficiaryWills(address _beneficiary) public view returns (uint256) {
        return beneficiaryWills[addressKeccak256(_beneficiary)].length;
    }

    function createWill(uint256 _willId, uint256 _storageId, uint256 _beneficiaryHash, address _provider, address _referrer) public payable {
        require(escrowWallet.isProviderValid(_provider));
        require(wills[_willId].state == WillState.None);
        require(address(_willId >> 96) == _provider);

        // charge the user and distribute the fee
        uint256 fee;
        (fee, ) = escrowWallet.providerInfo(_provider);
        financeWallet.charge.value(msg.value)(msg.sender, creatingFee(fee), _referrer, bytes32(_willId));

        // create the will
        wills[_willId] = Will({
            willId: _willId,
            storageId: _storageId,
            annualFee: financeWallet.centsToTokens(fee),
            newFee: 0,
            activationFee: financeWallet.centsToTokens(activatingReward(fee)),
            owner: msg.sender,
            state: WillState.Created,
            beneficiaryHash: _beneficiaryHash,
            decryptionKey: 0,
            updatedAt: currentTime(),
            validTill: 0,
            provider: _provider
        });
        userWills[msg.sender].push(_willId);

        // emit events
        emit WillCreated(msg.sender, _provider, _willId);
        emit WillStateUpdated(_willId, msg.sender, WillState.Created);
    }

    function activateWill(uint256 _willId) public onlyProvider(_willId) {
        Will storage will = wills[_willId];
        require(will.state == WillState.Created);

        will.state = WillState.Activated;
        will.updatedAt = currentTime();
        will.validTill = currentTime() + oneYear;

        financeWallet.reward(will.provider, activatingReward(will.annualFee), _willId);

        emit WillStateUpdated(_willId, will.owner, will.state);
    }

    function refreshWill(uint256 _willId) public onlyProvider(_willId) {
        Will storage will = wills[_willId];
        require(will.state == WillState.Activated);
        require(currentTime() - will.updatedAt > 30 days);

        if (will.newFee > 0) {
            // update annual fee and set last update to the start of the new year if it's a new year
            will.updatedAt = will.validTill - oneYear;
            will.annualFee = will.newFee;
            will.newFee = 0;
        }
        else {
            will.updatedAt = currentTime();
        }

        financeWallet.reward(will.provider, refreshingReward(will.annualFee), _willId);

        emit WillRefreshed(_willId, will.owner);
    }

    function prolongWillWithEther(uint256 _willId) public payable {
        Will storage will = wills[_willId];
        require(will.state == WillState.Activated);
        // allow to prolong the will in the last month of the previous subscription only
        require(will.validTill < currentTime() + 30 days);

        // charge the user and distribute the fee
        uint256 fee;
        (fee, ) = escrowWallet.providerInfo(will.provider);
        financeWallet.charge.value(msg.value)(msg.sender, prolongingFee(fee), 0x0, bytes32(_willId));

        // update the will
        will.newFee = financeWallet.centsToTokens(fee);
        will.validTill += oneYear;

        // emit an event
        emit WillProlonged(_willId, will.owner, will.validTill);
    }

    function applyWill(uint256 _willId, uint256 _decryptionKey) public onlyProvider(_willId) {
        Will storage will = wills[_willId];
        require(will.state == WillState.Activated);

        will.decryptionKey = _decryptionKey;
        will.state = WillState.Pending;
        will.updatedAt = currentTime();
        beneficiaryWills[will.beneficiaryHash].push(_willId);

        //todo: send a small amount of ethers to the beneficiary
        // it's impossible for the current paradigm due to unknown address of a beneficiary

        emit WillStateUpdated(_willId, will.owner, will.state);
    }

    function claimWill(uint256 _willId) public {
        Will storage will = wills[_willId];
        require(will.state == WillState.Pending);
        require(addressKeccak256(msg.sender) == will.beneficiaryHash);

        will.state = WillState.Claimed;
        financeWallet.reward(will.provider, claimingReward(will.annualFee), _willId);

        emit WillStateUpdated(_willId, will.owner, will.state);
    }

    function rejectWill(uint256 _willId) public onlyProvider(_willId) {
        Will storage will = wills[_willId];
        require(will.state == WillState.Activated);
        require(will.validTill < currentTime());

        will.state = WillState.Rejected;
        will.updatedAt = currentTime();

        emit WillStateUpdated(_willId, will.owner, will.state);
    }

    // Internal
    function addressKeccak256(address _address) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(_address)));
    }

    function currentTime() internal view returns (uint64) {
        return uint64(now);
    }
}
