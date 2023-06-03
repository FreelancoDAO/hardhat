// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./governance_standard/GovernorContract.sol";

error RepoToken__UnableToTransfer();
error RepoToken__UnableToApprove();
error RepoToken__Unqualified();

contract DAOReputationToken is ERC20, ERC20Burnable, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    //Constants
    uint256 public immutable amountToMintPerProposal = 10 ether;
    uint32 private constant LEVEL_1_THRESHOLD = 1000;
    uint32 private constant LEVEL_2_THRESHOLD = 10000;
    
    //Governor Contract
    GovernorContract governor;

    //State
    enum Level {
        Soldier,
        Marine,
        Captain
    }
    
    struct Holder {
        address _owner;
        uint256 _tokens;
        Level level;
    }

    mapping(uint256 => Holder) public _holders;
    mapping(address => Level) public ownerToRepo;
    address[] public _holdersArray;

    constructor() ERC20("DAOReputationToken", "RT") {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();
        _holdersArray.push(to);
        _holders[newItemId] = Holder(to, amount, ownerToRepo[to]);
    }

    /**
    @dev Hook function that is called after a token transfer.
    @param to The address receiving the tokens.
    **/
    function _afterTokenTransfer(
        address,
        address to,
        uint256
    ) internal override {
        if (balanceOf(to) < LEVEL_1_THRESHOLD) {
            ownerToRepo[to] = Level.Soldier;
        }
        if (
            balanceOf(to) > LEVEL_1_THRESHOLD &&
            balanceOf(to) < LEVEL_2_THRESHOLD
        ) {
            ownerToRepo[to] = Level.Marine;
        } else if (balanceOf(to) > LEVEL_2_THRESHOLD) {
            ownerToRepo[to] = Level.Captain;
        } else {
            revert RepoToken__UnableToTransfer();
        }
    }

    /**
    @notice Sets the Governor contract address.
    @param _governor The address of the Governor contract.
    Requirements:
        Only the DAO can call this function through a proposal.
    */
    function setGovernorContract(address payable _governor) public onlyOwner {
        governor = GovernorContract(_governor);
    }

    /**
    @notice Mints reputation tokens to reputed voters based on their voting power for a specific proposal.
    @param reputedVoters An array of addresses representing reputed voters.
    @param proposalId The ID of the proposal.
    */
    function _mintReputationTokens(
        address[] memory reputedVoters, uint256 proposalId
    ) public {
        uint256 totalVotingPower = 0;

        // Calculate the total voting power of all voters
        for (uint256 i = 0; i < reputedVoters.length; i++) {
            uint256 votingPower = governor.getVotes(
                reputedVoters[i],
                governor.proposalSnapshot(proposalId)
            ) / 1 ether;
            totalVotingPower += votingPower;
        }

        // Mint tokens proportionally based on each voter's voting power
        for (uint256 i = 0; i < reputedVoters.length; i++) {
            uint256 votingPower = governor.getVotes(
                reputedVoters[i],
                governor.proposalSnapshot(proposalId)
            ) / 1 ether;
            uint256 tokensToMint = (votingPower * amountToMintPerProposal) /
                totalVotingPower;

            mint(reputedVoters[i], tokensToMint);
        }
    }

    /**
    @notice Retrieves the reputation value of an owner.
    @param owner The address of the owner.
    @return The reputation value of the owner.
    */
    function getRepo(address owner) public view returns (uint8) {
        return uint8(ownerToRepo[owner]);
    }

    //View Functions
    function getHolders(uint256 counter) public view returns (Holder memory) {
        return _holders[counter];
    }

    function getHoldersArray() public view returns (address[] memory) {
        return _holdersArray;
    }

    //Overrides
    function transfer(address, uint256) public pure override returns (bool) {
        revert RepoToken__UnableToTransfer();
    }

    function approve(address, uint256) public pure override returns (bool) {
        revert RepoToken__UnableToApprove();
    }
}
