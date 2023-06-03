// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;


import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../../Offer.sol";
import "hardhat/console.sol";

error Escrow__TransactionFailed();

abstract contract Escrow {
    using SafeMath for uint256;

    uint256 private _daoChargesPercentage = 20;
    
    mapping(uint256 => Offer) public offers;
    mapping(uint256 => uint256) public _counterToOffers;

    struct Dispute {
        uint256 proposalId;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        string description;
        uint256 offerID;
        address disputingParty;
        address againstParty;
        uint256 amountEscrowed;
        bool isDisputeOver;
        address disputeReceiver;
    }

    event OfferSent(
        uint256 _offerId,
        uint256 indexed _gigTokenId,
        address _freelancer,
        address _client,
        uint _amount,
        uint _daoFees,
        uint _deadline,
        string _terms
    );

    event OfferStatusUpdated(
        uint indexed _offerId,
        Offer.ProposalStatus _status
    );

    function sendOffer(
        uint256 _gigTokenId,
        address _freelancer,
        string memory _terms,
        uint256 _deadlineBlocks
    ) public payable virtual;

    /**
    @dev Handles the crossing of the deadline for an offer.
    @param _offerId The ID of the offer.
    @param extend A boolean flag indicating whether to extend the deadline or not.
    @param extendedBlocks The number of blocks to extend the deadline by.
    @notice Requires the current block number to be greater than the offer's deadline.
    @notice Requires the caller to be the client of the offer.
    @notice If extend is true, extends the deadline of the offer by extendedBlocks blocks.
    @notice If extend is false, transfers the escrowed amount back to the client.
    @notice Reverts with Escrow__TransactionFailed if the deadline has not crossed, or if the transfer of funds fails.
    */
    function handleDeadlineCrossed(
        uint _offerId,
        bool extend,
        uint extendedBlocks
    ) public {
        Offer offerContract = Offer(offers[_offerId]);
        Offer.Proposal memory offerDetails = offerContract.getDetails();

        if (block.number > offerDetails._deadline) {
            revert Escrow__TransactionFailed();
        }

        if (msg.sender != offerDetails._client) {
            revert Escrow__TransactionFailed();
        }

        if (extend) {
            offerDetails._deadline = extendedBlocks;
        } else {
            (bool sent, ) = offerDetails._client.call{
                value: offerDetails._amountEscrowed
            }("");
            if (sent != true) {
                revert Escrow__TransactionFailed();
            }
        }
    }

    /**
    @dev Rejects an offer.
    @param _offerId The ID of the offer.
    @notice Requires the caller to be the freelancer of the offer.
    @notice Rejects the offer.
    @notice Refunds the escrowed amount to the client.
    @notice Emits OfferStatusUpdated event with the updated status of the offer.
    @notice Reverts with Escrow__TransactionFailed if the caller is not the freelancer or if the refund fails.
    */
    function rejectOffer(uint _offerId) public {
        Offer offerContract = Offer(offers[_offerId]);
        Offer.Proposal memory offerDetails = offerContract.getDetails();

        if (msg.sender != offerDetails._freelancerAddress) {
            revert Escrow__TransactionFailed();
        }

        offerContract.rejectOffer();

        (bool sent, ) = offerDetails._client.call{
            value: offerDetails._amountEscrowed
        }("");
        if (sent != true) {
            revert Escrow__TransactionFailed();
        }

        emit OfferStatusUpdated(_offerId, Offer.ProposalStatus.Rejected);
    }

    /**
    @dev Approves an offer.
    @param _offerId The ID of the offer.
    @notice Requires the caller to be the freelancer of the offer.
    @notice Approves the offer.
    @notice Emits OfferStatusUpdated event with the updated status of the offer.
    @notice Reverts with Escrow__TransactionFailed if the caller is not the freelancer.
    */
    function approveOffer(uint _offerId) public {
        Offer offerContract = Offer(offers[_offerId]);
        Offer.Proposal memory offerDetails = offerContract.getDetails();
        if (msg.sender != offerDetails._freelancerAddress) {
            revert Escrow__TransactionFailed();
        }

        offerContract.approveOffer();

        emit OfferStatusUpdated(_offerId, Offer.ProposalStatus.Approved);
    }

    /**
    @dev Marks an offer as complete.
    @param _offerId The ID of the offer.
    @notice Requires the current block number to be less than or equal to the offer's deadline.
    @notice Requires the caller to be the freelancer of the offer.
    @notice Marks the offer as complete.
    @notice Emits OfferStatusUpdated event with the updated status of the offer.
    @notice Reverts with Escrow__TransactionFailed if the current block number is greater than the offer's deadline or if the caller is not the freelancer.
    */
    function markComplete(uint _offerId) public {
        Offer offerContract = Offer(offers[_offerId]);
        Offer.Proposal memory offerDetails = offerContract.getDetails();

        if (block.number > offerDetails._deadline) {
            revert Escrow__TransactionFailed();
        }

        if (msg.sender != offerDetails._freelancerAddress) {
            revert Escrow__TransactionFailed();
        }

        offerContract.markComplete();

        emit OfferStatusUpdated(_offerId, Offer.ProposalStatus.Completed);
    }

    /**
    @dev Marks an offer as successful.
    @param _offerId The ID of the offer.
    @notice Requires the caller to be the client of the offer.
    @notice Marks the offer as successful.
    @notice Transfers the escrowed amount to the freelancer.
    @notice Emits OfferStatusUpdated event with the updated status of the offer.
    @notice Reverts with Escrow__TransactionFailed if the caller is not the client or if the transfer of funds fails.
    */
    function markSuccessful(uint _offerId) public {
        Offer offerContract = Offer(offers[_offerId]);
        Offer.Proposal memory offerDetails = offerContract.getDetails();
        if (msg.sender != offerDetails._client) {
            revert Escrow__TransactionFailed();
        }

        offerContract.markSuccessful();

        (bool sent, ) = offerDetails._freelancerAddress.call{
            value: offerDetails._amountEscrowed
        }("");
        if (sent != true) {
            revert Escrow__TransactionFailed();
        }

        emit OfferStatusUpdated(_offerId, Offer.ProposalStatus.Successful);
    }

    /**
    @dev Calculates the percentage of an amount based on basis points (bps).
    @param amount The amount to calculate the percentage of.
    @param bps The basis points value representing the percentage.
    @return The calculated percentage of the amount.
    */
    function calculatePercentage(
        uint256 amount,
        uint256 bps
    ) public pure returns (uint256) {
        return (amount * bps) / 10_000;
    }
}