// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {Functions, FunctionsClient} from "../dev/functions/FunctionsClient.sol";
// import "@chainlink/contracts/src/v0.8/dev/functions/FunctionsClient.sol"; // Once published
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

import "hardhat/console.sol";

library Decide {
    
    function whichOne(uint8 way, uint8 result, uint256 againstVotes, uint256 forVotes) public view returns (uint8) {
        if (result == 1) {
            //majority voted FOR
            if (way == 1) {
                return 1;
            } else {
                //recount
                if (
                    (againstVotes + calculateGPTVotingPower(againstVotes, forVotes)) >
                    forVotes
                ) {
                    return 0;
                } else {
                    return 1;
                }
                
            }
        } else {
            if(way == 1) {
                if (
                    (forVotes + calculateGPTVotingPower(againstVotes, forVotes)) >
                    againstVotes
                ) {
                    return 1;
                } else {
                    return 0;
                }
            } else {
                return 0;
            }
        }
    }

    function calculateGPTVotingPower(uint256 againstVotes, uint256 forVotes
    ) public view returns (uint256) {
        
        uint256 bps = 3000; // 30%
        uint256 _30percent = calculatePercentage(forVotes + againstVotes, bps);

        return _30percent;
    }

    function calculatePercentage(
        uint256 amount,
        uint256 bps
    ) public pure returns (uint256) {
        return (amount * bps) / 10_000;
    }
}


interface IDaoNFT {
    function balanceOf(address owner) external view virtual returns (uint256);
}


interface IFreelanco {
    function isProposalDisputed(
        uint256 _proposalID
    ) external view returns (bool);
}

error Governor__TransactionFailed();

contract GovernorContract is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl,
    FunctionsClient,
    ConfirmedOwner
{
    //Chainlink Functoins
    using Functions for Functions.Request;
    

    struct ProposalData {
        uint256 block_number;
        uint256 _id;
        bool shouldGPTVote;
        address[] targets;
        bytes[] calldatas;
    }

    struct GPTData {
        uint8 _voteWay;
        uint256 _id;
        bool hasVoted;
    }


    //Chainlink variables
    bytes32 public latestRequestId;
    bytes public latestResponse;
    bytes public latestError;

    //DAO contracts
    IDaoNFT public daoNFTContract;
    IFreelanco public freelancoContract;

    //State
    uint256 public counter = 0;
    uint256 public immutable amountToMintPerProposal = 10 ether;
    
    mapping(bytes32 => uint256) public requestIdToProposalId; //chainlink fulflill request id
    mapping(uint256 => GPTData) public proposalIdToGPTData;
    mapping(uint256 => ProposalData) public proposalIdToData; //stores the information about the proposal if GPT needs to execute

    //Events
    event OCRResponse(bytes32 indexed requestId, bytes result, bytes err);

    constructor(
        IVotes _token,
        TimelockController _timelock,
        uint256 _quorumPercentage,
        uint256 _votingPeriod,
        uint256 _votingDelay,
        IDaoNFT _nftContract,
        address oracle
    )
        Governor("GovernorContract")
        GovernorSettings(
            _votingDelay /* 1 block */, // voting delay
            _votingPeriod, // 45818, /* 1 week */ // voting period
            0 // proposal threshold
        )
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(_quorumPercentage)
        GovernorTimelockControl(_timelock)
        FunctionsClient(oracle)
        ConfirmedOwner(msg.sender)
    {
        daoNFTContract = IDaoNFT(_nftContract);
    }

    function updateOracleAddress(address oracle) public onlyOwner {
        setOracle(oracle);
    }

    function setFreelancoContract(address _freelancoContract) public onlyOwner {
        freelancoContract = IFreelanco(_freelancoContract);
    }

    function executeRequest(
        string calldata source,
        bytes calldata secrets,
        string[] calldata args,
        uint64 subscriptionId,
        uint32 gasLimit,
        uint256 proposalId
    ) public returns (bytes32) {
        
        ProposalData memory data = proposalIdToData[proposalId];

        if (!data.shouldGPTVote) {
            revert Governor__TransactionFailed();
        }

        if (
            data.block_number + votingDelay() + votingPeriod() + 1 <
            block.number
        ) {
            revert Governor__TransactionFailed();
        }
        Functions.Request memory req;
        
        req.initializeRequest(
            Functions.Location.Inline,
            Functions.CodeLanguage.JavaScript,
            source
        );
        if (secrets.length > 0) {
            req.addRemoteSecrets(secrets);
        }
        if (args.length > 0) req.addArgs(args);
    

        bytes32 assignedReqID = sendRequest(req, subscriptionId, gasLimit);

        latestRequestId = assignedReqID;

        requestIdToProposalId[latestRequestId] = proposalId;

        return assignedReqID;
    }

    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        latestResponse = response;
        latestError = err;
        uint256 _proposalId = requestIdToProposalId[latestRequestId];
        
        proposalIdToGPTData[_proposalId] = GPTData(abi.decode(response, (uint8)), _proposalId, true);

        (
            uint256 againstVotes,
            uint256 forVotes,
        ) = proposalVotes(_proposalId);

        uint8 result = forVotes >= againstVotes ? 1 : 0;
        uint8 gptVote = proposalIdToGPTData[_proposalId]._voteWay;

        // uint newresult = proposalIdToGPTData[_proposalId].whichOne(result);
        uint newresult = Decide.whichOne(gptVote, result, againstVotes, forVotes);
        // console.log("new result:", newresult);

        ProposalData memory data = proposalIdToData[_proposalId];
        address[] memory targets = new address[](1);
        targets[0] = data.targets[0];

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory datas = new bytes[](1);
        datas[0] = data.calldatas[newresult];

        super._execute(_proposalId, targets, values, datas, "reason");

        emit OCRResponse(requestId, response, err);
    }

    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal override returns (uint256) {
        if (daoNFTContract.balanceOf(account) <= 0) {
            revert Governor__TransactionFailed();
        }
        return super._castVote(proposalId, account, support, reason, params);
    }

    function votingDelay()
        public
        view
        override(IGovernor, GovernorSettings)
        returns (uint256)
    {
        return super.votingDelay();
    }

    function votingPeriod()
        public
        view
        override(IGovernor, GovernorSettings)
        returns (uint256)
    {
        return super.votingPeriod();
    }

    // The following functions are overrides required by Solidity.

    function quorum(
        uint256 blockNumber
    )
        public
        view
        override(IGovernor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }

    function getVotes(
        address account,
        uint256 blockNumber
    ) public view override(IGovernor, Governor) returns (uint256) {
        return super.getVotes(account, blockNumber);
    }

    function state(
        uint256 proposalId
    )
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override(Governor, IGovernor) returns (uint256) {
        
        uint256 proposalId = hashProposal(
            targets,
            values,
            calldatas,
            keccak256(bytes(description))
        );
        
        bool shouldGPTVote = freelancoContract.isProposalDisputed(proposalId);

        proposalIdToData[proposalId] = ProposalData(
            block.number,
            proposalId,
            shouldGPTVote,
            targets,
            calldatas
        );

        return super.propose(targets, values, calldatas, description);
    }

    function proposalThreshold()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.proposalThreshold();
    }

    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor()
        internal
        view
        override(Governor, GovernorTimelockControl)
        returns (address)
    {
        return super._executor();
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(Governor, GovernorTimelockControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
