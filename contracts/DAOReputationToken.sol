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

contract DAOReputationToken is ERC20, ERC20Burnable, Ownable {
    uint32 private constant LEVEL_1_THRESHOLD = 1000;
    uint32 private constant LEVEL_2_THRESHOLD = 10000;
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

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

    function getRepo(address owner) public view returns (uint8) {
        return uint8(ownerToRepo[owner]);
    }
}
