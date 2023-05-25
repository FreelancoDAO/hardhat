// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./Offer.sol";
import "./GigNFT.sol";
import "./DAOReputationToken.sol";
import "./governance_standard/GovernorContract.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "hardhat/console.sol";

error Freelanco__OnlyFreelancerCanDoThisAction();
error Freelanco__ClientNeedsToEscrow();
error Freelanco__DeadlineNotReached();
error Freelanco__OnlyClientCanDoThisAction();

contract Freelanco is Ownable {
    using SafeMath for uint256;

    mapping(uint256 => Offer) public offers;
    mapping(uint256 => uint256) public _counterToOffers;

    uint256 public _counter;
    uint256 public _disputeCounter;
    GovernorContract governor;
    Gig _nft_contract;
    DAOReputationToken _reputation_contract;
    uint256 private _daoChargesPercentage = 20;
    uint8 constant SOLDIER_SHARE = 30;
    uint8 constant MARINE_SHARE = 30;
    uint8 constant CAPTAIN_SHARE = 40;

    struct Freelancer {
        address _owner;
        uint256 _lockedAmount;
        uint256 _deadlineBlocks;
    }

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
    }

    mapping(uint256 => Dispute) public _counterToDispute;
    mapping(address => Freelancer) public _freelancers;
    mapping(uint256 => Dispute) public proposalIdToDispute;

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

    event ContractDisputed(
        uint indexed _offerId,
        uint indexed _proposalId,
        string _reason
    );

    event FreelancerBoostedProfile(
        address indexed freelancerAddress,
        uint indexed _msgValue,
        uint _deadlineBlock
    );

    event FreelancerWithrewLockedFunds(
        address indexed freelancerAddress,
        uint _amount
    );

    constructor(
        GovernorContract _governorContract,
        Gig _nftContractAddress,
        DAOReputationToken _reputationContractAddress
    ) {
        governor = GovernorContract(_governorContract);
        _nft_contract = Gig(_nftContractAddress);
        _reputation_contract = DAOReputationToken(_reputationContractAddress);
    }

    function sendOffer(
        uint256 _gigTokenId,
        address _freelancer,
        string memory _terms,
        uint256 _deadlineBlocks
    ) public payable {
        _counter++;

        uint256 _offerId = uint256(
            keccak256(
                abi.encode(_gigTokenId, _freelancer, _terms, _deadlineBlocks)
            )
        );

        _counterToOffers[_counter] = _offerId;

        uint256 _deadline = block.number + _deadlineBlocks;

        uint256 bps = 9000; // 30%
        uint256 _90percent = calculatePercentage(msg.value, bps);

        uint256 _escrowedAmount = _90percent;

        uint256 _daoFees = msg.value - _escrowedAmount;

        offers[_offerId] = new Offer(
            _gigTokenId,
            _freelancer,
            msg.sender,
            msg.value,
            _daoFees,
            _terms,
            _deadline
        );

        emit OfferSent(
            _offerId,
            _gigTokenId,
            _freelancer,
            msg.sender,
            _escrowedAmount,
            _daoFees,
            _deadline,
            _terms
        );
    }

    function calculatePercentage(
        uint256 amount,
        uint256 bps
    ) public pure returns (uint256) {
        return (amount * bps) / 10_000;
    }

    function rejectOffer(uint _offerId) public {
        Offer offerContract = Offer(offers[_offerId]);
        Offer.Proposal memory offerDetails = offerContract.getDetails();

        if (msg.sender != offerDetails._freelancerAddress) {
            revert Freelanco__OnlyFreelancerCanDoThisAction();
        }

        offerContract.rejectOffer();

        (bool sent, ) = offerDetails._client.call{
            value: offerDetails._amountEscrowed
        }("");
        if (sent != true) {
            revert TransactionFailed();
        }

        emit OfferStatusUpdated(_offerId, Offer.ProposalStatus.Rejected);
    }

    function approveOffer(uint _offerId) public {
        Offer offerContract = Offer(offers[_offerId]);
        Offer.Proposal memory offerDetails = offerContract.getDetails();
        if (msg.sender != offerDetails._freelancerAddress) {
            revert Freelanco__OnlyFreelancerCanDoThisAction();
        }

        offerContract.approveOffer();

        emit OfferStatusUpdated(_offerId, Offer.ProposalStatus.Approved);
    }

    function markComplete(uint _offerId) public {
        Offer offerContract = Offer(offers[_offerId]);
        Offer.Proposal memory offerDetails = offerContract.getDetails();

        if (block.number > offerDetails._deadline) {
            revert Freelanco__DeadlineNotReached();
        }

        if (msg.sender != offerDetails._freelancerAddress) {
            revert Freelanco__OnlyFreelancerCanDoThisAction();
        }

        offerContract.markComplete();

        emit OfferStatusUpdated(_offerId, Offer.ProposalStatus.Completed);
    }

    function handleDeadlineCrossed(
        uint _offerId,
        bool extend,
        uint extendedBlocks
    ) public {
        Offer offerContract = Offer(offers[_offerId]);
        Offer.Proposal memory offerDetails = offerContract.getDetails();

        if (block.number > offerDetails._deadline) {
            revert Freelanco__DeadlineNotReached();
        }

        if (msg.sender != offerDetails._client) {
            revert Freelanco__OnlyFreelancerCanDoThisAction();
        }

        if (extend) {
            offerDetails._deadline = extendedBlocks;
        } else {
            (bool sent, ) = offerDetails._client.call{
                value: offerDetails._amountEscrowed
            }("");
            if (sent != true) {
                revert TransactionFailed();
            }
            console.log(
                "Sent ",
                offerDetails._amountEscrowed,
                "To ",
                offerDetails._client
            );
        }
    }

    function markSuccessful(uint _offerId) public {
        Offer offerContract = Offer(offers[_offerId]);
        Offer.Proposal memory offerDetails = offerContract.getDetails();
        if (msg.sender != offerDetails._client) {
            revert Freelanco__OnlyClientCanDoThisAction();
        }

        offerContract.markSuccessful();

        (bool sent, ) = offerDetails._freelancerAddress.call{
            value: offerDetails._amountEscrowed
        }("");
        if (sent != true) {
            revert TransactionFailed();
        }

        emit OfferStatusUpdated(_offerId, Offer.ProposalStatus.Successful);
    }

    function disputeContract(uint256 _offerId, string memory _reason) public {
        Offer offerContract = Offer(offers[_offerId]);
        Offer.Proposal memory offerDetails = offerContract.getDetails();

        bytes[] memory datas = new bytes[](2);

        if (msg.sender == offerDetails._client) {
            offerContract.disputeByClient();

            datas[0] = abi.encodeWithSignature(
                "handleDispute(uint256,address)",
                _offerId,
                offerDetails._client
            );

            datas[1] = abi.encodeWithSignature(
                "handleDispute(uint256,address)",
                _offerId,
                offerDetails._freelancerAddress
            );

            emit OfferStatusUpdated(
                _offerId,
                Offer.ProposalStatus.Over_By_Client
            );
        } else if (msg.sender == offerDetails._freelancerAddress) {
            offerContract.disputeByFreelancer();

            datas[0] = abi.encodeWithSignature(
                "handleDispute(uint256,address)",
                _offerId,
                offerDetails._freelancerAddress
            );

            datas[1] = abi.encodeWithSignature(
                "handleDispute(uint256,address)",
                _offerId,
                offerDetails._client
            );

            emit OfferStatusUpdated(
                _offerId,
                Offer.ProposalStatus.Over_By_Freelancer
            );
        } else {
            revert Freelanco__ClientNeedsToEscrow();
        }

        uint256[] memory values = new uint256[](2);
        values[0] = 0;

        address[] memory targets = new address[](2);
        targets[0] = address(this);

        uint256 proposalId = governor.hashProposal(
            targets,
            values,
            datas,
            keccak256(bytes(_reason))
        );

        _disputeCounter++;

        _counterToDispute[_disputeCounter] = Dispute(
            proposalId,
            targets,
            values,
            datas,
            _reason,
            _offerId,
            msg.sender,
            offerDetails._freelancerAddress,
            offerDetails._amountEscrowed
        );

        proposalIdToDispute[proposalId] = _counterToDispute[_disputeCounter];

        governor.propose(targets, values, datas, _reason);

        emit ContractDisputed(_offerId, proposalId, _reason);
    }

    function withdraw() public onlyOwner {
        // Get the current balance of the Freelanco contract
        uint256 balance = address(this).balance;
        require(balance > 0, "Freelanco: contract has no funds to distribute");

        // Calculate the total number of NFT holders in each level
        uint256 totalSoldiers = 0;
        uint256 totalMarines = 0;
        uint256 totalCaptains = 0;
        address[] memory holders = _reputation_contract.getHolders();
        for (uint256 i = 0; i < holders.length; i++) {
            address holder = holders[i];
            uint8 level = _reputation_contract.getRepo(holder);
            if (level == 1) {
                totalSoldiers++;
            } else if (level == 2) {
                totalMarines++;
            } else if (level == 3) {
                totalCaptains++;
            }
        }

        // Calculate the amount of funds to distribute to each level
        uint256 soldiersShare = balance.mul(SOLDIER_SHARE).div(100).div(
            totalSoldiers
        );
        uint256 marinesShare = balance.mul(MARINE_SHARE).div(100).div(
            totalMarines
        );
        uint256 captainsShare = balance.mul(CAPTAIN_SHARE).div(100).div(
            totalCaptains
        );

        // Distribute funds to each NFT holder based on their level
        for (uint256 i = 0; i < holders.length; i++) {
            address holder = holders[i];
            uint8 level = _reputation_contract.getRepo(holder);
            uint256 amount = 0;
            if (level == 1) {
                amount = soldiersShare;
            } else if (level == 2) {
                amount = marinesShare;
            } else if (level == 3) {
                amount = captainsShare;
            }
            if (amount > 0) {
                payable(holder).transfer(amount); //change this
            }
        }
    }

    function handleDispute(
        uint256 _offerId,
        address receiver
    ) public onlyOwner {
        console.log("handle dispute called");

        Offer offerContract = Offer(offers[_offerId]);
        Offer.Proposal memory offerDetails = offerContract.getDetails();

        if (
            offerDetails._freelancerAddress == receiver ||
            offerDetails._client == receiver
        ) {
            (bool sent, ) = receiver.call{value: offerDetails._amountEscrowed}(
                ""
            );
            if (sent != true) {
                revert TransactionFailed();
            }
        } else {
            revert TransactionFailed();
        }

        offerContract.disputeResolved();

        emit OfferStatusUpdated(_offerId, Offer.ProposalStatus.Dispute_Over);
    }

    function boostProfile(uint256 _deadlineBlocks) public payable {
        if (msg.value <= 0) {
            revert TransactionFailed();
        }

        _freelancers[msg.sender] = Freelancer(
            msg.sender,
            msg.value,
            _deadlineBlocks
        );

        emit FreelancerBoostedProfile(msg.sender, msg.value, _deadlineBlocks);
    }

    function withdrawLockedFreelancerAmount() public {
        if (_freelancers[msg.sender]._lockedAmount == 0) {
            revert TransactionFailed();
        }
        if (_freelancers[msg.sender]._deadlineBlocks < block.number) {
            revert TransactionFailed();
        }
        (bool sent, ) = msg.sender.call{
            value: _freelancers[msg.sender]._lockedAmount
        }("");
        if (sent != true) {
            revert TransactionFailed();
        }

        emit FreelancerWithrewLockedFunds(
            msg.sender,
            _freelancers[msg.sender]._lockedAmount
        );
    }

    function updateDAOPercentage(uint256 _newPercentage) public onlyOwner {
        _daoChargesPercentage = _newPercentage;
    }

    function getFreelancersLockedAmount(
        address _freelancer
    ) public returns (Freelancer memory) {
        return _freelancers[_freelancer];
    }

    //VIEW
    function getOfferContract(uint256 _offerId) public view returns (address) {
        return address(offers[_offerId]);
    }

    function getDisputeStruct(
        uint256 _proposalID
    ) public view returns (Dispute memory) {
        Dispute memory dispute = proposalIdToDispute[_proposalID];
        return dispute;
    }

    function isProposalDisputed(
        uint256 _proposalID
    ) public view returns (bool) {
        Dispute memory dispute = proposalIdToDispute[_proposalID];

        console.log("arg", _proposalID);
        console.log("pro:", dispute.proposalId);
        if (dispute.proposalId != 0) {
            return true;
        } else {
            return false;
        }
    }

    function getOfferId(uint256 _counterIdx) public view returns (uint256) {
        return _counterToOffers[_counterIdx];
    }

    function getDispute(
        uint256 _counterIdx
    ) public view returns (Dispute memory) {
        return _counterToDispute[_counterIdx];
    }
}
