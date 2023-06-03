// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";

error TransactionFailed();
error SpendMoreMatic();

/**
 * @title Whitelist
 * @dev A contract that manages a whitelist of addresses.
 */
contract Whitelist is Ownable {
  // Future Scope:
  // 1. Use price feeds to determine the amount of fees required for joining the whitelist.
  // 2. Allow users to view real-time price data through a function in the contract.

  address[] public _whitelisted;
  uint256 public immutable WHITELIST_FEES = 1274577610908013100; // about 1.3 ETH

  event Whitelist__Joined(address indexed);

  /**
   * @dev Allows an address to join the whitelist by paying the required fees.
   * Emits a Whitelist__Joined event upon successful registration.
   */
  function joinWhitelist() public payable {
    if (msg.value <= WHITELIST_FEES) {
      revert SpendMoreMatic();
    }
    _whitelisted.push(msg.sender);

    emit Whitelist__Joined(msg.sender);
  }

  /**
   * @dev Allows the owner to withdraw the contract's balance.
   * Emits a TransactionFailed error if the withdrawal fails.
   */
  function withdraw() public onlyOwner {
    address receiver = msg.sender;
    (bool sent, ) = receiver.call{value: address(this).balance}("");
    if (sent != true) {
      revert TransactionFailed();
    }
  }

  /**
   * @dev Checks if an address is whitelisted.
   * @param _addr The address to check.
   * @return A boolean value indicating whether the address is whitelisted.
   */
  function isWhitelisted(address _addr) public view returns (bool) {
    for (uint i = 0; i < _whitelisted.length; i++) {
      if (_whitelisted[i] == _addr) {
        return true;
      }
    }
    return false;
  }
}
