// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

library Decide {
    
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

    function calculateGPTVotingPower(uint256 againstVotes, uint256 forVotes
    ) public view returns (uint256) {
        
        uint256 bps = 3000; // 30%
        uint256 _30percent = calculatePercentage(forVotes + againstVotes, bps);

        return _30percent;
    }

    function calculatePercentage(
        uint256 amount,
        uint256 bps
    ) public pure returns (uint256) {
        return (amount * bps) / 10_000;
    }
}