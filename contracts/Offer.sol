// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

error OnlyFreelancerCanDoThisAction();
error TransactionFailed();
error CantUpdateSorry();

contract Offer is Ownable {
    enum ProposalStatus {
        Sent, //Escrowed By Client
        Approved, //Started (Freelancer likes the offer)
        Rejected, //Refund Client (Freelancer doesn't like the offer)
        Completed, //Done By Freelancer (Freelancer did his job)
        Successful, //Pay Freelancer (Client is Happy)
        Over_By_Freelancer, //Disputed (Freelancer is Unhappy)
        Over_By_Client, //Disputed (Client is Unhappy)
        Dispute_Over
    }

    struct Proposal {
        uint _gigId;
        uint _amountEscrowed;
        uint _daoFees;
        address _client;
        address _freelancerAddress;
        ProposalStatus _status;
        string _terms;
        uint _deadline;
    }

    Proposal private offer;

    constructor(
        uint256 _gigId,
        address _freelancer,
        address _client,
        uint _escrowedAmount,
        uint _daoFees,
        string memory _terms,
        uint _deadline
    ) {
        offer = Proposal(
            _gigId,
            _escrowedAmount,
            _daoFees,
            _client,
            _freelancer,
            ProposalStatus.Sent,
            _terms,
            _deadline
        );
    }

    function rejectOffer() public onlyOwner {
        Proposal storage proposal = offer;
        if (proposal._status == ProposalStatus.Sent) {
            proposal._status = ProposalStatus.Rejected;
        } else {
            revert CantUpdateSorry();
        }
    }

    function approveOffer() public onlyOwner {
        Proposal storage proposal = offer;
        if (proposal._status == ProposalStatus.Sent) {
            proposal._status = ProposalStatus.Approved;
        } else {
            revert CantUpdateSorry();
        }
    }

    function markComplete() public onlyOwner {
        Proposal storage proposal = offer;
        if (proposal._status == ProposalStatus.Approved) {
            proposal._status = ProposalStatus.Completed;
        } else {
            revert CantUpdateSorry();
        }
    }

    function markSuccessful() public onlyOwner {
        Proposal storage proposal = offer;
        if (proposal._status == ProposalStatus.Completed) {
            proposal._status = ProposalStatus.Successful;
        } else {
            revert CantUpdateSorry();
        }
    }

    function disputeByFreelancer() public onlyOwner {
        Proposal storage proposal = offer;
        proposal._status = ProposalStatus.Over_By_Freelancer;
    }

    function disputeByClient() public onlyOwner {
        Proposal storage proposal = offer;
        proposal._status = ProposalStatus.Over_By_Client;
    }

    function disputeResolved() public onlyOwner {
        Proposal storage proposal = offer;
        proposal._status = ProposalStatus.Dispute_Over;
    }

    function getDetails() public view returns (Proposal memory) {
        return offer;
    }
}
