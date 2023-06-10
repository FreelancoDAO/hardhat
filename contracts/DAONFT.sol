// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./DAOReputationToken.sol";
import "./IWhitelist.sol";

error DaoNFT__AlreadyInitialized();
error DaoNFT__NeedMoreETHSent();
error DaoNFT__RangeOutOfBounds();
error DaoNFT__TransferFailed();
error DaoNFT__Unqualified();
error DaoNFT__TransactionFailed();

/**
 * @title DAO_NFt
 * @dev Contract responsible for minting DAO NFTs tokens for joining the DAO.
 */
contract DaoNFT is ERC721URIStorage, VRFConsumerBaseV2, Ownable {
    using SafeMath for uint256;

    // Types
    enum Level {
        Soldier,
        Marine,
        Captain
    }

    // Chainlink VRF Variables
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    uint64 private immutable i_subscriptionId;
    bytes32 private immutable i_gasLane;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    // NFT Variables
    uint256 private immutable i_mintFee;
    uint256 private s_tokenCounter;
    uint256 internal constant MAX_CHANCE_VALUE = 100;
    mapping(Level => string[]) s_dogTokenUris;
    bool private s_initialized;

    // VRF Helpers
    mapping(uint256 => address) public s_requestIdToSender;
    mapping(uint256 => Level) public s_requestIdToLevel;

    uint8 constant SOLDIER_SHARE = 30;
    uint8 constant MARINE_SHARE = 30;
    uint8 constant CAPTAIN_SHARE = 40;

    DAOReputationToken public repoContract;
    IWhitelist public whitelistContract;

    // Events
    event NftRequested(uint256 indexed requestId, address requester);
    event NftMinted(string uri, address minter);

    constructor(
        address vrfCoordinatorV2,
        uint64 subscriptionId,
        bytes32 gasLane, // keyHash
        uint32 callbackGasLimit,
        string[3] memory level_0_dogTokenUris,
        string[3] memory level_1_dogTokenUris,
        string[3] memory level_2_dogTokenUris,
        DAOReputationToken _reputationContract,
        IWhitelist _whitelistContract
    ) VRFConsumerBaseV2(vrfCoordinatorV2) ERC721("Freelanco DAO", "FDAO") {
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_mintFee = 0.1 ether;
        i_callbackGasLimit = callbackGasLimit;
        _initializeContract(
            level_0_dogTokenUris,
            level_1_dogTokenUris,
            level_2_dogTokenUris
        );
        s_tokenCounter = 0;
        repoContract = DAOReputationToken(_reputationContract);
        whitelistContract = IWhitelist(_whitelistContract);
    }

    function requestNft() public payable returns (uint256 requestId) {
        if(whitelistContract.isWhitelisted(msg.sender)){
            // do something
        }
        Level level;
        if (repoContract.getRepo(msg.sender) == 0) {
            if(whitelistContract.isWhitelisted(msg.sender) == false){
                if (msg.value < i_mintFee) {
                    revert DaoNFT__NeedMoreETHSent();
                }
            }
            level = Level.Soldier;
        } else if (repoContract.getRepo(msg.sender) == 1) {
            level = Level.Marine;
        } else if (repoContract.getRepo(msg.sender) == 2) {
            level = Level.Captain;
        } else {
            revert DaoNFT__Unqualified();
        }

        requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );

        s_requestIdToSender[requestId] = msg.sender;
        s_requestIdToLevel[requestId] = level;
        emit NftRequested(requestId, msg.sender);
    }

    function getRandomNumber(uint256[] memory randomWords) public view {
        uint256 moddedRng = randomWords[0] % MAX_CHANCE_VALUE;
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        address dogOwner = s_requestIdToSender[requestId];
        uint256 newItemId = s_tokenCounter;
        s_tokenCounter = s_tokenCounter + 1;
        uint256 moddedRng = randomWords[0] % MAX_CHANCE_VALUE;

        string memory _uri = getRandomNFT(
            moddedRng,
            s_requestIdToLevel[requestId]
        );
        _safeMint(dogOwner, newItemId);
        _setTokenURI(newItemId, _uri);
        emit NftMinted(_uri, dogOwner);
    }

    function getChanceArray() public pure returns (uint256[3] memory) {
        return [10, 40, MAX_CHANCE_VALUE];
    }

    function _initializeContract(
        string[3] memory level_0_dogTokenUris,
        string[3] memory level_1_dogTokenUris,
        string[3] memory level_2_dogTokenUris
    ) private {
        if (s_initialized) {
            revert DaoNFT__AlreadyInitialized();
        }
        s_dogTokenUris[Level.Soldier] = level_0_dogTokenUris;
        s_dogTokenUris[Level.Marine] = level_1_dogTokenUris;
        s_dogTokenUris[Level.Captain] = level_2_dogTokenUris;
        s_initialized = true;
    }

    function getRandomNFT(
        uint256 moddedRng,
        Level breed
    ) public view returns (string memory) {
        uint256 cumulativeSum = 0;
        uint256[3] memory chanceArray = getChanceArray();
        for (uint256 i = 0; i < chanceArray.length; i++) {
            if (moddedRng >= cumulativeSum && moddedRng < chanceArray[i]) {
                return s_dogTokenUris[breed][i];
            }
            cumulativeSum = chanceArray[i];
        }
        revert DaoNFT__RangeOutOfBounds();
    }

    function withdraw() public onlyOwner {
        // Get the current balance of the Freelanco contract
        uint256 balance = address(this).balance;
        require(balance > 0, "Freelanco: contract has no funds to distribute");

        (bool sent, ) = msg.sender.call{value: balance}("");
        if (sent != true) {
            revert DaoNFT__TransactionFailed();
        }
    }

    function getMintFee() public view returns (uint256) {
        return i_mintFee;
    }

    function getDogTokenUris(
        uint256 index,
        Level level
    ) public view returns (string memory) {
        return s_dogTokenUris[level][index];
    }

    function getInitialized() public view returns (bool) {
        return s_initialized;
    }

    function getTokenCounter() public view returns (uint256) {
        return s_tokenCounter;
    }
}
