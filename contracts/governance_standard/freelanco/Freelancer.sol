// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

error Freelancer__TransactionFailed();

abstract contract DAOFreelancer {

    struct Freelancer {
        address _owner;
        uint256 _lockedAmount;
        uint256 _deadlineBlocks;
    }

    mapping(address => Freelancer) public _freelancers;

    event FreelancerBoostedProfile(
        address indexed freelancerAddress,
        uint indexed _msgValue,
        uint _deadlineBlock
    );

    event FreelancerWithrewLockedFunds(
        address indexed freelancerAddress,
        uint _amount
    );

    /**
    @dev Boosts the profile of the freelancer by depositing funds.
    @param _deadlineBlocks The number of blocks until the boost deadline.
    @notice Requires a non-zero amount of funds to be deposited.
    @notice Updates the freelancer's profile with the deposited funds and the boost deadline.
    @notice Emits FreelancerBoostedProfile event with the details of the boosted profile.
    @notice Reverts with Freelancer__TransactionFailed if the amount deposited is zero.
    */
    function boostProfile(uint256 _deadlineBlocks) public payable {
        if (msg.value <= 0) {
            revert Freelancer__TransactionFailed();
        }

        _freelancers[msg.sender] = Freelancer(
            msg.sender,
            msg.value,
            _deadlineBlocks
        );

        emit FreelancerBoostedProfile(msg.sender, msg.value, _deadlineBlocks);
    }

    /**
    @dev Withdraws the locked funds of the freelancer.
    @notice Requires the freelancer to have locked funds and the lock deadline to have passed.
    @notice Transfers the locked funds to the freelancer's address.
    @notice Sets the freelancer's locked amount to zero after withdrawal.
    @notice Emits FreelancerWithdrewLockedFunds event with the details of the withdrawn funds.
    @notice Reverts with Freelancer__TransactionFailed if the freelancer has no locked funds or the lock deadline has not passed.
    */
    function withdrawLockedFreelancerAmount() public {
        if (_freelancers[msg.sender]._lockedAmount == 0) {
            revert Freelancer__TransactionFailed();
        }
        if (_freelancers[msg.sender]._deadlineBlocks > block.number) {
            revert Freelancer__TransactionFailed();
        }

        (bool sent, ) = msg.sender.call{
            value: _freelancers[msg.sender]._lockedAmount
        }("");

        if (sent != true) {
            revert Freelancer__TransactionFailed();
        }
        _freelancers[msg.sender]._lockedAmount = 0;

        emit FreelancerWithrewLockedFunds(
            msg.sender,
            _freelancers[msg.sender]._lockedAmount
        );
    }

    //View functions
    function getFreelancersLockedAmount(
        address _freelancer
    ) public view returns (Freelancer memory) {
        return _freelancers[_freelancer];
    }
}