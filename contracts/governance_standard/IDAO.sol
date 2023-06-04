// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IDaoNFT {
    function balanceOf(address owner) external view virtual returns (uint256);
}

interface IFreelanco {
    function isProposalDisputed(
        uint256 _proposalID
    ) external view returns (bool);
}