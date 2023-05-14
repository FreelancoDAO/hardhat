// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";

import "../DAOReputationToken.sol";
import "../DAONFT.sol";
import "hardhat/console.sol";

error ChatGPTDidntVoteYet();
error ThresholdReached();
error isNotDaoMember();

contract GovernorContract is
  Governor,
  GovernorSettings,
  GovernorCountingSimple,
  GovernorVotes,
  GovernorVotesQuorumFraction,
  GovernorTimelockControl,
  AutomationCompatibleInterface
{
  struct VoterDetails {
    address account;
    uint256 support;
  }

  uint256 public counter = 0;
  DAOReputationToken public reputationContract;
  DaoNFT public daoNFTContract;
  mapping(uint256 => VoterDetails[]) public voters;
  mapping(uint256 => uint256) public _counterToProposalId;
  uint256 public immutable amountToMintPerProposal = 100 ether;

  constructor(
    IVotes _token,
    TimelockController _timelock,
    uint256 _quorumPercentage,
    uint256 _votingPeriod,
    uint256 _votingDelay,
    DAOReputationToken _reputationContract,
    DaoNFT _nftContract
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
  {
    reputationContract = DAOReputationToken(_reputationContract);
    daoNFTContract = DaoNFT(_nftContract);
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

    console.log("Casting vote in contract: ", proposalId, account, support);

    return super._castVote(proposalId, account, support, reason, params);
  }

  function votingDelay() public view override(IGovernor, GovernorSettings) returns (uint256) {
    return super.votingDelay();
  }

  function votingPeriod() public view override(IGovernor, GovernorSettings) returns (uint256) {
    return super.votingPeriod();
  }

  // The following functions are overrides required by Solidity.

  function quorum(
    uint256 blockNumber
  ) public view override(IGovernor, GovernorVotesQuorumFraction) returns (uint256) {
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
  ) public view override(Governor, GovernorTimelockControl) returns (ProposalState) {
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

  function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
    return super.proposalThreshold();
  }

  function checkUpkeep(
    bytes calldata /* checkData */
  ) external view override returns (bool upkeepNeeded, bytes memory /* performData */) {
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
      state(_proposalId) == ProposalState.Defeated || state(_proposalId) == ProposalState.Succeeded
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
    (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = proposalVotes(proposalId);

    console.log("For: ", forVotes, "against: ", againstVotes);

    super._execute(proposalId, targets, values, calldatas, descriptionHash);
  }

  function _mintReputationTokens(address[] memory _voters, uint256 proposalId) public {
    uint256 totalVotingPower = 0;

    // Calculate the total voting power of all voters
    for (uint256 i = 0; i < _voters.length; i++) {
      uint256 votingPower = getVotes(_voters[i], proposalSnapshot(proposalId)) / 1 ether;
      totalVotingPower += votingPower;
    }

    // Mint tokens proportionally based on each voter's voting power
    for (uint256 i = 0; i < _voters.length; i++) {
      uint256 votingPower = getVotes(_voters[i], proposalSnapshot(proposalId)) / 1 ether;
      uint256 tokensToMint = (votingPower * amountToMintPerProposal) / totalVotingPower;

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

  function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
    return super._executor();
  }

  function supportsInterface(
    bytes4 interfaceId
  ) public view override(Governor, GovernorTimelockControl) returns (bool) {
    return super.supportsInterface(interfaceId);
  }
}
