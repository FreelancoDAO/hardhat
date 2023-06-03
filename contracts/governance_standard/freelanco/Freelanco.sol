// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../../Offer.sol";
import "../../GigNFT.sol";
import "../../DAOReputationToken.sol";
import "./Escrow.sol";
import "./Freelancer.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

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

error Freelanco__TransactionFailed();

contract Freelanco is Ownable, Escrow, DAOFreelancer {
    using SafeMath for uint256;

    //DAO Contracts
    IGovernorContract governor;
    Gig _nft_contract;
    DAOReputationToken _reputation_contract;
    
    uint256 public _counter;
    uint256 public _disputeCounter;
    uint256 private _daoChargesPercentage = 20;

    mapping(uint256 => Dispute) public _counterToDispute;
    mapping(uint256 => Dispute) public proposalIdToDispute;

    address public gpt;
    address immutable zero_address = address(0);

    event ContractDisputed(
        uint indexed _offerId,
        uint indexed _proposalId,
        string _reason
    );

    event GrantInitiated(uint indexed _proposalId, string _reason, bytes data);

    event SlashedFreelancerFunds(
        uint _offerId,
        address freelancer,
        uint amount
    );

    /**
    @dev Contract constructor.
    @param _governorContract The address of the governor contract.
    @param _nftContractAddress The address of the Gig contract.
    @param _reputationContractAddress The address of the DAOReputationToken contract.
    @notice Initializes the contract by setting the addresses of the governor contract, Gig contract, and DAOReputationToken contract.
    @notice Sets the gpt variable to the address of the contract deployer.
    */
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

    /**
    @dev Sends an offer for a specific gig.
    @param _gigTokenId The ID of the gig token.
    @param _freelancer The address of the freelancer to whom the offer is being sent.
    @param _terms The terms of the offer.
    @param _deadlineBlocks The number of blocks until the offer deadline.
    @notice This function creates and initializes a new Offer contract for the offer.
    @notice The offer amount is escrowed and the DAO fees are calculated and deducted from the offer amount.
    @notice Emits OfferSent event with the details of the sent offer.
    @notice Reverts with Freelanco__TransactionFailed if the gig is not approved for the freelancer.
    */
    function sendOffer(
        uint256 _gigTokenId,
        address _freelancer,
        string memory _terms,
        uint256 _deadlineBlocks
    ) public payable override {
        if(msg.value <= 0){
            revert Freelanco__TransactionFailed();
        }
        
        if(_nft_contract.isGigApproved(_gigTokenId, _freelancer) == false){
            revert Freelanco__TransactionFailed();
        }

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

    /**
    @dev Initiates a dispute for a specific offer contract.
    @param _offerId The ID of the offer.
    @param _reason The reason for the dispute.
    @notice This function allows either the client or the freelancer to initiate a dispute.
    @notice The function creates a proposal in the governor contract to handle the dispute.
    @notice Emits OfferStatusUpdated event with the updated status of the offer.
    @notice Emits ContractDisputed event with the offer ID, proposal ID, and reason for the dispute.
    */
    function disputeContract(uint256 _offerId, string memory _reason) public {
        Offer offerContract = Offer(offers[_offerId]);
        Offer.Proposal memory offerDetails = offerContract.getDetails();

        bytes[] memory datas = new bytes[](2);

        if (msg.sender == offerDetails._client) {
            offerContract.disputeByClient();

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
                Offer.ProposalStatus.Over_By_Client
            );
        } else if (msg.sender == offerDetails._freelancerAddress) {
            offerContract.disputeByFreelancer();

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
                Offer.ProposalStatus.Over_By_Freelancer
            );
        } else {
            revert Freelanco__TransactionFailed();
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
            zero_address
        );

        proposalIdToDispute[proposalId] = _counterToDispute[_disputeCounter];

        governor.propose(targets, values, datas, _reason);

        offerContract.setProposalId(proposalId);

        emit ContractDisputed(_offerId, proposalId, _reason);
    }

    /**
    @dev Initiates a grant proposal with a given reason.
    @param _reason The reason for the grant proposal.
    @notice This function initiates a grant proposal by creating a proposal in the governor contract.
    @notice The proposal calls the "withdraw()" function of the contract.
    @notice Emits GrantInitiated event with the proposal ID, reason, and encoded function signature.
    */
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
    }

    /**
    @dev Allows the DAO owner to withdraw the balance from the contract.
    @notice This function can only be called by the DAO owner.
    @notice Transfers the balance of the contract to the DAO owner.
    @notice Emits Freelanco__TransactionFailed if the transfer fails.
    */
    function withdraw() public onlyOwner {
        (bool sent, ) = gpt.call{value: address(this).balance}(
                ""
        );
        if (sent != true) {
            revert Freelanco__TransactionFailed();
        }
    }

    /**
    @dev Updates the DAO charges percentage.
    @param _newPercentage The new percentage to be set as the DAO charges percentage.
    @notice This function can only be called by the DAO owner.
    */
    function updateDAOPercentage(uint256 _newPercentage) public onlyOwner {
        _daoChargesPercentage = _newPercentage;
    }

    /**
    @dev Handles the resolution of a dispute for a specific offer.
    @param _offerId The ID of the offer.
    @param receiver The address of the receiver whose dispute is being resolved.
    @notice This function can only be called by the Timelock after a proposal has succeeded.
    @notice Calls the disputeResolved function of the offer contract to resolve the dispute.
    */
    function handleDispute(
        uint256 _offerId,
        address receiver
    ) public onlyOwner {
        Offer offerContract = Offer(offers[_offerId]);
        offerContract.disputeResolved(receiver);
    }

    /**
    @dev Retrieves disputed funds for a specific offer.
    @param _offerId The ID of the offer.
    @notice This function can only be called by the disputed receiver and if the dispute has been resolved.
    @notice If the disputed receiver is the client, the freelancer's funds may be slashed based on a percentage.
    @notice Emits SlashedFreelancerFunds event if the freelancer's funds are slashed.
    @notice Emits OfferStatusUpdated event with the updated status of the offer.
    */
    function getDisputedFunds(uint256 _offerId) public {
        Offer offerContract = Offer(offers[_offerId]);
        Offer.Proposal memory offerDetails = offerContract.getDetails();        
        
        if(offerContract.isDisputeResolved() == false){
            revert Freelanco__TransactionFailed();
        }

        if(msg.sender != offerContract.getDisputedReceiver())
        {
            revert Freelanco__TransactionFailed();
        }
        (bool sent, ) = msg.sender.call{value: offerDetails._amountEscrowed}(
                ""
        );
        if (sent != true) {
            revert Freelanco__TransactionFailed();
        }
        offerContract.fundsReleaased();
        
        //slash freelancers money if deposited for boosting
        if (offerDetails._client == offerContract.getDisputedReceiver()) {
            uint256 bps = 1000; // 10%
            uint256 _10percent = calculatePercentage(
                offerDetails._amountEscrowed,
                bps
            );

            if (
                _freelancers[offerDetails._freelancerAddress]
                    ._lockedAmount >= _10percent
            ) {
                _freelancers[offerDetails._freelancerAddress]
                    ._lockedAmount -= _10percent;
            } else if (
                _freelancers[offerDetails._freelancerAddress]
                    ._lockedAmount >=
                0 &&
                _freelancers[offerDetails._freelancerAddress]
                    ._lockedAmount <=
                _10percent
            ) {
                _freelancers[offerDetails._freelancerAddress]
                    ._lockedAmount = 0;
            }

            emit SlashedFreelancerFunds(
                _offerId,
                offerDetails._freelancerAddress,
                _10percent
            );
        }
        emit OfferStatusUpdated(_offerId, Offer.ProposalStatus.Dispute_Over);
    }

    //View functions
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
