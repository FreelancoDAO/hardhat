// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "hardhat/console.sol";

error RepoToken__UnableToTransfer();
error RepoToken__UnableToApprove();
error RepoToken__Unqualified();

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

import "./governance_standard/GovernorContract.sol";

contract DAOReputationToken is ERC20, ERC20Burnable, Ownable {
    uint256 public immutable amountToMintPerProposal = 10 ether;

    uint32 private constant LEVEL_1_THRESHOLD = 1000;
    uint32 private constant LEVEL_2_THRESHOLD = 10000;
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    GovernorContract governor;

    enum Level {
        Soldier,
        Marine,
        Captain
    }

    mapping(address => Level) public ownerToRepo;
    uint256 _counter = 0;
    struct Holder {
        address _owner;
        uint256 _tokens;
        Level level;
    }
    mapping(uint256 => Holder) _holders;

    address[] public _holdersArray;

    constructor() ERC20("DAOReputationToken", "RT") {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
        console.log("minting reputation token", to, amount);

        console.log("pushed counter");
        _tokenIds.increment();
        console.log("pushed counter 2");
        uint256 newItemId = _tokenIds.current();
        console.log("pushed counter 3");

        _holdersArray.push(to);

        _holders[newItemId] = Holder(to, amount, ownerToRepo[to]);

        console.log("minting");
    }

    function getHolders(uint256 counter) public view returns (Holder memory) {
        console.log("getting", _holders[counter]._owner);
        return _holders[counter];
    }

    function getHoldersArray() public view returns (address[] memory) {
        return _holdersArray;
    }

    function transfer(address, uint256) public pure override returns (bool) {
        revert RepoToken__UnableToTransfer();
    }

    function approve(address, uint256) public pure override returns (bool) {
        revert RepoToken__UnableToApprove();
    }

    function _afterTokenTransfer(
        address,
        address to,
        uint256
    ) internal override {
        console.log("after token called");
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

    function setGovernorContract(address payable _governor) public onlyOwner {
        governor = GovernorContract(_governor);
    }

    // function _mintReputationTokens(
    //     uint256 proposalId,
    //     uint256 counter,
    //     uint256 len
    // ) public {

    //     address[] memory reputedVoters = new address[](len);

    //     for (uint256 i = 1; i <= counter; i++) {
    //         (address voter, uint support) = governor.getVoter(proposalId, counter);
            

    //         for (uint256 j = 0; j < len; j++) {
    //             bool isReputed = governor.isReputedVoter(voter, support, proposalId);
    //             if (isReputed) {
    //                 reputedVoters[j] = voter;
    //             }
    //         }
        
    //     }

    //     uint256 totalVotingPower = 0;

    //     // Calculate the total voting power of all voters
    //     for (uint256 i = 0; i < reputedVoters.length; i++) {
    //         uint256 votingPower = governor.getVotes(
    //             reputedVoters[i],
    //             governor.proposalSnapshot(proposalId)
    //         ) / 1 ether;
    //         totalVotingPower += votingPower;
    //     }

    //     // Mint tokens proportionally based on each voter's voting power
    //     for (uint256 i = 0; i < reputedVoters.length; i++) {
    //         uint256 votingPower = governor.getVotes(
    //             reputedVoters[i],
    //             governor.proposalSnapshot(proposalId)
    //         ) / 1 ether;
    //         uint256 tokensToMint = (votingPower * amountToMintPerProposal) /
    //             totalVotingPower;

    //         mint(reputedVoters[i], tokensToMint);
    //     }
    // }

    function getRepo(address owner) public view returns (uint8) {
        return uint8(ownerToRepo[owner]);
    }
}
