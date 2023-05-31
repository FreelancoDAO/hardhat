// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./Offer.sol";
import "./GigNFT.sol";
import "./DAOReputationToken.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "hardhat/console.sol";

interface IGovernorContract {
    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external pure returns (uint256);

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256);
}

error Freelanco__OnlyFreelancerCanDoThisAction();
error Freelanco__ClientNeedsToEscrow();
error Freelanco__DeadlineNotReached();
error Freelanco__OnlyClientCanDoThisAction();

contract Freelanco is Ownable {
    using SafeMath for uint256;

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
        bool isDisputeOver;
        address disputeReceiver;
    }

    //DAO Contracts
    IGovernorContract governor;
    Gig _nft_contract;
    DAOReputationToken _reputation_contract;

    mapping(uint256 => Offer) public offers;
    mapping(uint256 => uint256) public _counterToOffers;

    uint256 public _counter;
    uint256 public _disputeCounter;
    uint256 private _daoChargesPercentage = 20;

    uint8 constant SOLDIER_SHARE = 30;
    uint8 constant MARINE_SHARE = 30;
    uint8 constant CAPTAIN_SHARE = 40;

    mapping(uint256 => Dispute) public _counterToDispute;
    mapping(address => Freelancer) public _freelancers;
    mapping(uint256 => Dispute) public proposalIdToDispute;

    address public gpt;

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

    event GrantInitiated(uint indexed _proposalId, string _reason, bytes data);

    event SlashedFreelancerFunds(
        uint _offerId,
        address freelancer,
        uint amount
    );

    constructor(
        IGovernorContract _governorContract,
        Gig _nftContractAddress,
        DAOReputationToken _reputationContractAddress
    ) {
        governor = IGovernorContract(_governorContract);
        _nft_contract = Gig(_nftContractAddress);
        _reputation_contract = DAOReputationToken(_reputationContractAddress);
        gpt = msg.sender;
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

        console.log("dao fees", _daoFees);
        console.log("escrowed:", _escrowedAmount);

        offers[_offerId] = new Offer(
            _gigTokenId,
            _freelancer,
            msg.sender,
            _escrowedAmount,
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
            revert Freelanco__OnlyClientCanDoThisAction();
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
            offerDetails._amountEscrowed,
            false,
            0x0000000000000000000000000000000000000000
        );

        proposalIdToDispute[proposalId] = _counterToDispute[_disputeCounter];

        governor.propose(targets, values, datas, _reason);

        offerContract.setProposalId(proposalId);

        emit ContractDisputed(_offerId, proposalId, _reason);
    }

    function initiateGrantProposal(string memory _reason) public {
        bytes[] memory datas = new bytes[](1);

        datas[0] = abi.encodeWithSignature("withdraw()");

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        address[] memory targets = new address[](1);
        targets[0] = address(this);

        governor.propose(targets, values, datas, _reason);

        uint256 proposalId = governor.hashProposal(
            targets,
            values,
            datas,
            keccak256(bytes(_reason))
        );

        emit GrantInitiated(
            proposalId,
            _reason,
            abi.encodeWithSignature("withdraw()")
        );

        console.log("grant made");
    }

    function withdraw() public onlyOwner {

        (bool sent, ) = gpt.call{value: address(this).balance}(
                ""
        );
        if (sent != true) {
            revert TransactionFailed();
        }

        // Get the current balance of the Freelanco contract

        // console.log("withdrawing..");

        // console.log("balance:", address(this).balance);

        // uint256 balance = address(this).balance;
        // if (balance < 0) {
        //     console.log("balance low");
        //     revert TransactionFailed();
        // }

        // // Calculate the total number of NFT holders in each level
        // uint256 totalSoldiers = 0;
        // uint256 totalMarines = 0;
        // uint256 totalCaptains = 0;

        // address[] memory holders = _reputation_contract.getHoldersArray();

        // console.log("getting holders", holders.length);

        // if (uint256(holders.length) <= 0) {
        //     console.log("reverting...");
        //     revert TransactionFailed();
        // }

        // for (uint256 i = 0; i < holders.length; i++) {
        //     address holder = holders[i];
        //     uint8 level = _reputation_contract.getRepo(holder);

        //     console.log("holder:", holder, level);

        //     console.log("counting");
        //     if (level == 0) {
        //         totalSoldiers++;
        //     } else if (level == 1) {
        //         totalMarines++;
        //     } else if (level == 2) {
        //         totalCaptains++;
        //     }
        // }

        // // Calculate the amount of funds to distribute to each level
        // console.log("counting 2", totalCaptains);
        // uint256 marinesShare;
        // uint256 captainsShare;
        // uint256 soldiersShare;
        // if (totalSoldiers > 0) {
        //     soldiersShare = balance.mul(SOLDIER_SHARE).div(100).div(
        //         totalSoldiers
        //     );
        // } else {
        //     soldiersShare = 0;
        // }
        // if (totalMarines > 0) {
        //     marinesShare = balance.mul(MARINE_SHARE).div(100).div(totalMarines);
        // } else {
        //     marinesShare = 0;
        // }
        // if (totalCaptains > 0) {
        //     captainsShare = balance.mul(CAPTAIN_SHARE).div(100).div(
        //         totalCaptains
        //     );
        // } else {
        //     captainsShare = 0;
        // }

        // console.log("distributing");

        // // Distribute funds to each NFT holder based on their level
        // for (uint256 i = 0; i < holders.length; i++) {
        //     address holder = holders[i];
        //     uint8 level = _reputation_contract.getRepo(holder);
        //     uint256 amount = 0;
        //     if (level == 0) {
        //         amount = soldiersShare;
        //     } else if (level == 1) {
        //         amount = marinesShare;
        //     } else if (level == 2) {
        //         amount = captainsShare;
        //     }

        //     if (amount > 0) {
        //         console.log("sending to", holder, amount);

        //         (bool sent, ) = holder.call{value: amount}("");
        //         if (sent != true) {
        //             revert TransactionFailed();
        //         }
        //     }
        // }
    }

    function handleDispute(
        uint256 _offerId,
        address receiver
    ) public onlyOwner {
        console.log("HANDLING OFFER ID", _offerId);
        Offer offerContract = Offer(offers[_offerId]);
        offerContract.disputeResolved(receiver);

        console.log("RECIEVER:", receiver);
    }

    function getDisputedFunds(uint256 _offerId) public {
        console.log("SENDER:", msg.sender);
        
        Offer offerContract = Offer(offers[_offerId]);
        Offer.Proposal memory offerDetails = offerContract.getDetails();        
        
        if(offerContract.isDisputeResolved() == false){
            revert TransactionFailed();
        }

        if(msg.sender != offerContract.getDisputedReceiver())
        {
            console.log("DISPUTE RECIEVER INVALID");
            revert TransactionFailed();
        }
        (bool sent, ) = msg.sender.call{value: offerDetails._amountEscrowed}(
                ""
        );
        if (sent != true) {
            revert TransactionFailed();
        }
        offerContract.fundsReleaased();
        console.log("GOT RESOLVED FULLY");
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
        if (_freelancers[msg.sender]._deadlineBlocks > block.number) {
            revert TransactionFailed();
        }

        (bool sent, ) = msg.sender.call{
            value: _freelancers[msg.sender]._lockedAmount
        }("");

        if (sent != true) {
            revert TransactionFailed();
        }
        _freelancers[msg.sender]._lockedAmount = 0;

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
