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

interface IDaoRepo {
    function mint(address to, uint256 amount) external virtual;
    function _mintReputationTokens(
        address[] memory reputedVoters, uint256 proposalId
    ) external;
}


library Decide {
    
    function whichOne(uint8 way, uint8 result, uint256 againstVotes, uint256 forVotes) internal view returns (uint8) {
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

    struct VoterDetails {
        address account;
        uint256 support;
    }

    struct ProposalData {
        uint256 block_number;
        uint256 _id;
        bool shouldGPTVote;
        address[] targets;
        bytes[] calldatas;
        uint256 result;
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
    IDaoRepo public reputationContract;
    IDaoNFT public daoNFTContract;
    IFreelanco public freelancoContract;

    //State
    uint256 public counter = 0;
    address public gpt;
    mapping(uint256 => VoterDetails[]) public voters; //deatils of the voters mapped by proposal ID
    mapping(uint256 => uint256) public _counterToProposalId;
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
        IDaoRepo _reputationContract,
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
        reputationContract = IDaoRepo(_reputationContract);
        daoNFTContract = IDaoNFT(_nftContract);
        gpt = msg.sender;
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
        
        ProposalData storage data = proposalIdToData[proposalId];

        if(msg.sender != gpt) {
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

    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
        latestResponse = response;
        latestError = err;
        uint256 _proposalId = requestIdToProposalId[latestRequestId];
        proposalIdToGPTData[_proposalId] = GPTData(abi.decode(response, (uint8)), _proposalId, true);
        console.log("GPT VOTED: ", abi.decode(response, (uint8)));
        emit OCRResponse(requestId, response, err);
    }

    function executeProposal(uint256 _proposalId) public {
        if(proposalIdToGPTData[_proposalId].hasVoted == false) {
            revert Governor__TransactionFailed();
        }
        
        if (
            block.number < proposalIdToData[_proposalId].block_number + votingDelay() + votingPeriod() + 1 
        ) {
            revert Governor__TransactionFailed();
        }

        (
            uint256 againstVotes,
            uint256 forVotes,
        ) = proposalVotes(_proposalId);

        uint8 result = forVotes >= againstVotes ? 1 : 0;
        uint8 gptVote = proposalIdToGPTData[_proposalId]._voteWay;

        // uint newresult = proposalIdToGPTData[_proposalId].whichOne(result);
        uint newresult = Decide.whichOne(gptVote, result, againstVotes, forVotes);
        proposalIdToData[_proposalId].result = newresult;
        // console.log("new result:", newresult);

        ProposalData memory data = proposalIdToData[_proposalId];
        address[] memory targets = new address[](1);
        targets[0] = data.targets[0];

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory datas = new bytes[](1);
        datas[0] = data.calldatas[newresult];

        proposalIdToData[_proposalId].result = newresult;

        VoterDetails[] memory voters_ = voters[_proposalId];
        address[] memory reputedVoters = new address[](voters_.length);

        for (uint256 j = 0; j < voters_.length; j++) {
            VoterDetails memory voter = voters_[j];
            if (result == voter.support) {
                reputedVoters[j] = voter.account;
                
            }
        }

        reputationContract._mintReputationTokens(reputedVoters, _proposalId);

        super._execute(_proposalId, targets, values, datas, "reason");
    }


    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal override returns (uint256) {
        voters[proposalId].push(VoterDetails(account, support));
        if (daoNFTContract.balanceOf(account) <= 0) {
            revert Governor__TransactionFailed();
        }
        return super._castVote(proposalId, account, support, reason, params);
    }

    function getVoter(uint256 proposalId, uint256 _counter) public view returns(address, uint) {
        VoterDetails[] memory voters_ = voters[proposalId];
        console.log("voters len:", voters_.length, _counter);
        return (voters_[_counter].account, voters_[_counter].support);
    }

    function isReputedVoter(address _voter, uint256 support, uint256 proposalId) public view returns (bool){
        VoterDetails[] memory votesArray =  voters[proposalId];
        if(support == proposalIdToData[proposalId].result) {
            return true; 
        }
        return false;
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
        counter++;
        _counterToProposalId[counter] = proposalId;
        
        bool shouldGPTVote = freelancoContract.isProposalDisputed(proposalId);

        proposalIdToData[proposalId] = ProposalData(
            block.number,
            proposalId,
            shouldGPTVote,
            targets,
            calldatas,
            69
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
        if(proposalIdToData[proposalId].shouldGPTVote == true) {
            revert Governor__TransactionFailed();
        }
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
