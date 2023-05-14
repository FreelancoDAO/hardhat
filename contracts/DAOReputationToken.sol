// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

error RepoToken__UnableToTransfer();
error RepoToken__UnableToApprove();
error RepoToken__Unqualified();

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DAOReputationToken is ERC20, ERC20Burnable, Ownable {
  uint32 private constant LEVEL_1_THRESHOLD = 1000;
  uint32 private constant LEVEL_2_THRESHOLD = 10000;

  enum Level {
    Soldier,
    Marine,
    Captain
  }

  mapping(address => Level) public ownerToRepo;
  address[] public nftHolders;

  constructor() ERC20("DAOReputationToken", "RT") {}

  function mint(address to, uint256 amount) public onlyOwner {
    nftHolders.push(to);
    _mint(to, amount);
  }

  function getHolders() public view returns (address[] memory) {
    return nftHolders;
  }

  function transfer(address, uint256) public pure override returns (bool) {
    revert RepoToken__UnableToTransfer();
  }

  function approve(address, uint256) public pure override returns (bool) {
    revert RepoToken__UnableToApprove();
  }

  function _afterTokenTransfer(address, address to, uint256) internal override {
    if (balanceOf(to) < LEVEL_1_THRESHOLD) {
      ownerToRepo[to] = Level.Soldier;
    }
    if (balanceOf(to) > LEVEL_1_THRESHOLD && balanceOf(to) < LEVEL_2_THRESHOLD) {
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
