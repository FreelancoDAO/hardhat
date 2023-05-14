// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";

error TransactionFailed();
error SpendMoreMatic();

contract Whitelist is Ownable {
  address[] public _whitelisted;
  uint256 public immutable WHITELIST_FEES = 1274577610908013100;

  event Whitelist__Joined(address indexed);

  function joinWhitelist() public payable {
    if (msg.value <= WHITELIST_FEES) {
      revert SpendMoreMatic();
    }
    _whitelisted.push(msg.sender);

    emit Whitelist__Joined(msg.sender);
  }

  function withdraw() public onlyOwner {
    address receiver = msg.sender;
    (bool sent, ) = receiver.call{value: address(this).balance}("");
    if (sent != true) {
      revert TransactionFailed();
    }
  }

  function isWhitelisted(address _addr) public view returns (bool) {
    for (uint i = 0; i < _whitelisted.length; i++) {
      if (_whitelisted[i] == _addr) {
        return true;
      }
    }
    return false;
  }
}
