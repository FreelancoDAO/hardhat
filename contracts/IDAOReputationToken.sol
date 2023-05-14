// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface Reputation {
    function _mint(address account, uint256 amount) external;

    function getRepo(address owner) external view returns (uint8);

    function balanceOf(address account) external view returns (uint256);
}
