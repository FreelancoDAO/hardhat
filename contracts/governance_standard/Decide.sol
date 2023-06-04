// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

/**
 * @title Decide Library
 * @dev This library re-counts the votes accounting for GPT's voting power
 */
library Decide {

    /**
    * @dev Determines the final outcome of a voting based on the given parameters.
    * @param way The voting direction: 1 for FOR, 0 for AGAINST.
    * @param result The result of the voting: 1 for majority voted FOR, 0 for majority voted AGAINST.
    * @param againstVotes The total votes against the proposal.
    * @param forVotes The total votes for the proposal.
    * @return The final outcome: 1 for approved, 0 for rejected.
    */ 
    function whichOne(uint8 way, uint8 result, uint256 againstVotes, uint256 forVotes) internal view returns (uint8) {
        if (result == 1) {
            //majority voted FOR
            if (way == 1) {
                return 1;
            } else {
                //recount
                if (
                    (againstVotes + calculateGPTVotingPower(againstVotes, forVotes)) >
                    forVotes
                ) {
                    return 0;
                } else {
                    return 1;
                }
                
            }
        } else {
            if(way == 1) {
                if (
                    (forVotes + calculateGPTVotingPower(againstVotes, forVotes)) >
                    againstVotes
                ) {
                    return 1;
                } else {
                    return 0;
                }
            } else {
                return 0;
            }
        }
    }

    /**
    * @dev Calculates the GPT voting power based on the total votes.
    * @param againstVotes The total votes against the proposal.
    * @param forVotes The total votes for the proposal.
    * @return The GPT voting power as a percentage.
    */
    function calculateGPTVotingPower(uint256 againstVotes, uint256 forVotes
    ) public view returns (uint256) {
        
        uint256 bps = 3000; // 30%
        uint256 _30percent = calculatePercentage(forVotes + againstVotes, bps);

        return _30percent;
    }

    /**
    * @dev Calculates the percentage value of an amount based on basis points (bps).
    * @param amount The value to calculate the percentage of.
    * @param bps The basis points value.
    * @return The calculated percentage.
    */
    function calculatePercentage(
        uint256 amount,
        uint256 bps
    ) public pure returns (uint256) {
        return (amount * bps) / 10_000;
    }
}