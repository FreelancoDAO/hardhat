// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./Decide.sol";
import "@openzeppelin/contracts/governance/Governor.sol";
import "./GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {Functions, FunctionsClient} from "../dev/functions/FunctionsClient.sol";
// import "@chainlink/contracts/src/v0.8/dev/functions/FunctionsClient.sol"; // Once published
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";
import "./IDAO.sol";

error Governor__TransactionFailed();

/**
 * @title GovernorContract
 * @dev The GovernorContract contract is responsible for managing proposals but TIMELOCK executes it.
 */
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
    IDaoNFT public daoNFTContract;
    IFreelanco public freelancoContract;

    //State
    address public gpt;
    uint8 FLAG=69;
    mapping(bytes32 => uint256) public requestIdToProposalId; //chainlink fulflill request id
    mapping(uint256 => GPTData) public proposalIdToGPTData;
    mapping(uint256 => ProposalData) public proposalIdToData; //stores the information about the proposal if GPT needs to execute tores the information about the proposal if GPT needs to execute

    //Events
    event OCRResponse(bytes32 indexed requestId, bytes result, bytes err);

    /**
    @notice Initializes the contract with initial state variables.
    @param _token The address of the Votes token contract.
    @param _timelock The address of the TimelockController contract.
    @param _quorumPercentage The percentage of votes required for a proposal to reach quorum.
    @param _votingPeriod The duration of the voting period in blocks.
    @param _votingDelay The delay between proposal creation and the start of voting in blocks.
    @param _nftContract The address of the DAO NFT contract.
    @param oracle The address of the FunctionsOracle contract.
    **/
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
        gpt = msg.sender;
    }

    /**
   * @notice Allows the Functions oracle address to be updated
   *
   * @param oracle New oracle address
   */
    function updateOracleAddress(address oracle) public onlyOwner {
        setOracle(oracle);
    }

    /**
    @dev Sets the addresses of the DAO contracts.
    @param _freelancoContractAddress The address of the Freelanco contract.
    @param _daoNFTAddress The address of the DAO NFT contract.
    **/
    function setDAOContracts(address _freelancoContractAddress, address _daoNFTAddress) public onlyOwner {
        freelancoContract = IFreelanco(_freelancoContractAddress);
        daoNFTContract = IDaoNFT(_daoNFTAddress);
    }
    
    /**
    @dev Modifier that allows only the GPT to execute a function.
    */
    modifier onlyGPT {
        if(msg.sender != gpt){
            revert Governor__TransactionFailed();
        }
        _;
    }

    /**
   * @notice Send a simple request
   *
   * @param source JavaScript source code
   * @param secrets Encrypted secrets payload
   * @param args List of arguments accessible from within the source code
   * @param subscriptionId Funtions billing subscription ID
   * @param gasLimit Maximum amount of gas used to call the client contract's `handleOracleFulfillment` function
   * @return Functions request ID
   */
    function executeRequest(
        string calldata source,
        bytes calldata secrets,
        string[] calldata args,
        uint64 subscriptionId,
        uint32 gasLimit,
        uint256 proposalId
    ) public onlyGPT returns (bytes32) {
        
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

    /**
    * @notice Callback that is invoked once the DON has resolved the request or hit an error
    *
    * @param requestId The request ID, returned by sendRequest()
    * @param response Aggregated response from the user code
    * @param err Aggregated error from the user code or from the execution pipeline
    * Either response or error parameter will be set, but never both
    */
    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
        latestResponse = response;
        latestError = err;
        uint256 _proposalId = requestIdToProposalId[latestRequestId];
        proposalIdToGPTData[_proposalId] = GPTData(abi.decode(response, (uint8)), _proposalId, true);
        emit OCRResponse(requestId, response, err);
    }

    /**
    @dev Executes a proposal by determining the outcome based on the GPT vote and executing the corresponding action.
    @param _proposalId The ID of the proposal to execute.
    Requirements:
        Only the GPT contract is allowed to call this function.
    */
    function executeProposal(uint256 _proposalId) public {
        (
            uint256 againstVotes,
            uint256 forVotes,
        ) = proposalVotes(_proposalId);

        uint8 result = forVotes > againstVotes ? 1 : 0;
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

        super._execute(_proposalId, targets, values, datas, "reason");
    }

    
    /**
       @notice Custom logic for successful of a proposal
     * @dev See {Governor-_voteSucceeded}. In Governor module, GPT must vote for a dispute proposal to be successful
     */
    function _voteSucceeded(uint256 proposalId) internal view virtual override returns (bool) {
        ProposalData storage data = proposalIdToData[proposalId];
        if(data.shouldGPTVote == true) {
            return proposalIdToGPTData[proposalId].hasVoted;
        } else {
            (
            uint256 againstVotes,
            uint256 forVotes,
        ) = proposalVotes(proposalId);
            return forVotes > againstVotes;
        }
    }

    /**
    @dev Casts a vote for a specific proposal.
    @param proposalId The ID of the proposal to vote on.
    @param account The address of the account casting the vote.
    @param support The vote value indicating support or opposition (0 for against, 1 for in favor).
    @param reason A string explaining the reason for the vote.
    @param params Additional parameters for the vote (in bytes format).
    @return The ID of the vote casted.
    Requirements:
        The account must have a positive balance of NFT tokens in the daoNFTContract.
    */
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

    /**
    @dev Creates a new proposal to be voted on.
    @param targets An array of target addresses for the proposed actions.
    @param values An array of values associated with the proposed actions.
    @param calldatas An array of data payloads to be executed by the target addresses.
    @param description A string describing the proposal.
    @return The ID of the newly created proposal.
    Requirements:
        The targets, values, and calldatas arrays must have the same length.
        The description must be a non-empty string.
        The shouldGPTVote flag must be determined based on the dispute status of the proposal.
    */
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
            calldatas,
            FLAG
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

    /**
    @dev Executes a proposal by calling the specified targets with the provided values and calldatas.
    @param proposalId The ID of the proposal to execute.
    @param targets An array of target addresses for the actions to be executed.
    @param values An array of values associated with the actions.
    @param calldatas An array of data payloads to be executed by the target addresses.
    @param descriptionHash The hash of the description associated with the proposal.
    Requirements:
        The shouldGPTVote flag of the proposal i.e dispute proposal can only be executed from Chainlink DON 
    */
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
