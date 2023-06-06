// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IWhitelist {
    function isWhitelisted(address _addr) external view returns (bool);
}