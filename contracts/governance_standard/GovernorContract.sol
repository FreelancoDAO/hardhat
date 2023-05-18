// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";
import {Functions, FunctionsClient} from "../dev/functions/FunctionsClient.sol";
// import "@chainlink/contracts/src/v0.8/dev/functions/FunctionsClient.sol"; // Once published
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

import "../DAOReputationToken.sol";
import "../DAONFT.sol";
import "hardhat/console.sol";

error ChatGPTDidntVoteYet();
error ThresholdReached();
error isNotDaoMember();
error ProposalNeedsToBeQueued();

contract GovernorContract is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl,
    AutomationCompatibleInterface,
    FunctionsClient,
    ConfirmedOwner
{
    //Chainlink Functoins
    using Functions for Functions.Request;

    bytes32 public latestRequestId;
    bytes public latestResponse;
    bytes public latestError;

    event OCRResponse(bytes32 indexed requestId, bytes result, bytes err);

    struct VoterDetails {
        address account;
        uint256 support;
    }

    uint256 public counter = 0;
    DAOReputationToken public reputationContract;
    DaoNFT public daoNFTContract;
    mapping(uint256 => VoterDetails[]) public voters;
    mapping(uint256 => uint256) public _counterToProposalId;
    mapping(bytes32 => uint256) public requestIdToProposalId;
    mapping(uint256 => uint8) public proposalIdToChatGPT;
    mapping(uint256 => bool) public proposalIdToChatGPTVoted;
    mapping(uint256 => bool) public proposalIdToShouldTransfer;
    mapping(uint256 => Parties) public proposalIdToShouldTransferTo;
    uint256 public immutable amountToMintPerProposal = 100 ether;

    enum Parties {
        DisputingParty,
        AgainstParty
    }

    constructor(
        IVotes _token,
        TimelockController _timelock,
        uint256 _quorumPercentage,
        uint256 _votingPeriod,
        uint256 _votingDelay,
        DAOReputationToken _reputationContract,
        DaoNFT _nftContract,
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
        reputationContract = DAOReputationToken(_reputationContract);
        daoNFTContract = DaoNFT(_nftContract);
    }

    function updateOracleAddress(address oracle) public onlyOwner {
        setOracle(oracle);
    }

    function executeRequest(
        string calldata source,
        bytes calldata secrets,
        string[] calldata args,
        uint64 subscriptionId,
        uint32 gasLimit,
        uint256 proposalId
    ) public returns (bytes32) {
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
        proposalIdToChatGPT[_proposalId] = abi.decode(response, (uint8));

        address gpt_address = address(this);
        bytes memory params;

        proposalIdToChatGPTVoted[_proposalId] = true;

        (
            uint256 againstVotes,
            uint256 forVotes,
            uint256 abstainVotes
        ) = proposalVotes(_proposalId);

        uint result = forVotes > againstVotes ? 1 : 0;

        if (result == 1) {
            //majority voted FOR
            if (proposalIdToChatGPT[_proposalId] == 1) {
                proposalIdToShouldTransfer[_proposalId] = false;

                //gpt voted FOR
            } else {
                //gpt voted AGAINST
                if (
                    (againstVotes + calculateGPTVotingPower(_proposalId)) >
                    forVotes
                ) {
                    //majority chooses for
                    //send money to against party
                    proposalIdToShouldTransfer[_proposalId] = true;
                    proposalIdToShouldTransferTo[_proposalId] = Parties
                        .AgainstParty;
                }
            }
        } else {
            //majority voted AGAINST
            if (proposalIdToChatGPT[_proposalId] == 1) {
                //gpt voted FOR
                if (
                    (forVotes + calculateGPTVotingPower(_proposalId)) >
                    againstVotes
                ) {
                    //majority chooses for
                    //send money to for party
                    proposalIdToShouldTransfer[_proposalId] = true;
                    proposalIdToShouldTransferTo[_proposalId] = Parties
                        .DisputingParty;
                }
            } else {
                //gpt voted AGAINST
                if (
                    (againstVotes + calculateGPTVotingPower(_proposalId)) >
                    forVotes
                ) {
                    proposalIdToShouldTransfer[_proposalId] = true;
                    proposalIdToShouldTransferTo[_proposalId] = Parties
                        .AgainstParty;
                }
            }
        }

        console.log("GPT VOTED", proposalIdToChatGPT[_proposalId]);

        emit OCRResponse(requestId, response, err);
    }

    function getGPTIsVoted(uint256 _proposalId) public view returns (bool) {
        return proposalIdToChatGPTVoted[_proposalId];
    }

    function getShouldTransfer(uint256 _proposalId) public view returns (bool) {
        return proposalIdToShouldTransfer[_proposalId];
    }

    function getShouldTransferTo(
        uint256 _proposalId
    ) public view returns (Parties) {
        return proposalIdToShouldTransferTo[_proposalId];
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
            revert isNotDaoMember();
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
        counter++;
        _counterToProposalId[counter] = hashProposal(
            targets,
            values,
            calldatas,
            keccak256(bytes(description))
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

    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        for (uint256 i = 0; i < counter; i++) {
            uint256 proposalId = _counterToProposalId[i];
            if (isProposalReputed(proposalId)) {
                upkeepNeeded = true;
            }
        }
        upkeepNeeded = false;
    }

    function performUpkeep(bytes calldata /* performData */) external override {
        for (uint256 i = 0; i < counter; i++) {
            uint256 proposalId = _counterToProposalId[i];
            if (isProposalReputed(proposalId)) {
                VoterDetails[] memory voters_ = voters[proposalId];
                uint256 result = _voteSucceeded(proposalId) ? 1 : 0;
                address[] memory reputedVoters = new address[](voters_.length);

                for (uint256 j = 0; j < voters_.length; j++) {
                    VoterDetails memory voter = voters_[j];
                    if (result == voter.support) {
                        reputedVoters[j] = voter.account;
                    }
                }

                _mintReputationTokens(reputedVoters, proposalId);
            }
        }
    }

    function isProposalReputed(uint256 _proposalId) public view returns (bool) {
        if (
            state(_proposalId) == ProposalState.Defeated ||
            state(_proposalId) == ProposalState.Succeeded
        ) {
            return true;
        }
        return false;
    }

    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        if (proposalIdToChatGPT[proposalId] == 1) {
            // if chat gpt vote's for, as the DAO members also voted for, we execute
            super._execute(
                proposalId,
                targets,
                values,
                calldatas,
                descriptionHash
            );
        } else {
            //if chat gpt doesn't vote for, then we need to re count

            (
                uint256 againstVotes,
                uint256 forVotes,
                uint256 abstainVotes
            ) = proposalVotes(proposalId);

            bool shouldExecute = forVotes >
                againstVotes + calculateGPTVotingPower(proposalId);

            if (shouldExecute) {
                super._execute(
                    proposalId,
                    targets,
                    values,
                    calldatas,
                    descriptionHash
                );
            } else {
                proposalIdToShouldTransfer[proposalId] = true;
            }
        }
    }

    function calculateGPTVotingPower(
        uint256 _proposalId
    ) public returns (uint256) {
        (
            uint256 againstVotes,
            uint256 forVotes,
            uint256 abstainVotes
        ) = proposalVotes(_proposalId);

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

    function _mintReputationTokens(
        address[] memory _voters,
        uint256 proposalId
    ) public {
        uint256 totalVotingPower = 0;

        // Calculate the total voting power of all voters
        for (uint256 i = 0; i < _voters.length; i++) {
            uint256 votingPower = getVotes(
                _voters[i],
                proposalSnapshot(proposalId)
            ) / 1 ether;
            totalVotingPower += votingPower;
        }

        // Mint tokens proportionally based on each voter's voting power
        for (uint256 i = 0; i < _voters.length; i++) {
            uint256 votingPower = getVotes(
                _voters[i],
                proposalSnapshot(proposalId)
            ) / 1 ether;
            uint256 tokensToMint = (votingPower * amountToMintPerProposal) /
                totalVotingPower;

            reputationContract.mint(_voters[i], tokensToMint);
        }
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
