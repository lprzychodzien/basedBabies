//SPDX-License-Identifier: MIT  
pragma solidity ^0.8.20;

import "erc721a/contracts/ERC721A.sol";
import "erc721a/contracts/IERC721A.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "base64-sol/base64.sol";
import "contracts/helpers/BabyData.sol";


///// Based OnChain Baby
contract OnChainBaby is ERC721A, Ownable, BabyData, ReentrancyGuard  {  

    address public deployer;
    bytes32 private lastBlockHash;
    uint256 private lastBlockNumber;

    /// Mint Settings
    uint     public maxSupply    = 5000;
    uint     public mintPrice    = 0.001 ether;
    uint     public maxFree      = 500;
    uint     public freeCount    = 0;
    bool     public mintEnabled  = false;

    /// Mint Rules
    uint     public maxMintPerTrans = 20;
    uint     public maxMintPerWallet = 500;

    /// Whitelist Settings
    mapping(address => uint) public mintAmount;
    mapping(address => bool) public whiteListed;

    /// Whitelist setup
    address public listController;

    modifier onlylistController() {
        require(msg.sender == listController, "Controller Only");
        _;
    }


    constructor() ERC721A("Based OnChain Babies", "BABY") Ownable(msg.sender){
        deployer = msg.sender;
        listController = msg.sender;
        lastBlockHash = blockhash(block.number - 1);
        lastBlockNumber = block.number;
    }

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    function mint(uint256 quantity) external payable {
        uint256 cost = mintPrice;
        require(mintEnabled, "Mint not ready yet");
        require(msg.value == quantity * cost, "Please send the exact ETH amount");
        require(quantity <= maxMintPerTrans, "Exceeds max mint per transaction");

        // Check if the mint quantity exceeds the per wallet limit
        uint256 totalMintedByWallet = mintAmount[msg.sender] + quantity;
        require(totalMintedByWallet <= maxMintPerWallet, "Exceeds max mint per wallet");
        mintAmount[msg.sender] = mintAmount[msg.sender] + totalMintedByWallet;

        // Start minting
        _internalMint(quantity);
    }

    function free_mint() external {
        require(whiteListed[msg.sender] == true, "Not on whitelist");
        require(mintEnabled, "Mint not ready yet");
        require(freeCount + 1 <= maxFree, "No more free Babies!");

        whiteListed[msg.sender] = false;
        freeCount = freeCount + 1;

        // Start minting
        _internalMint(1);

    }

    function _internalMint(uint256 quantity) internal  {

        require(_totalMinted() + quantity <= maxSupply, "Sold Out!");
        require(msg.sender == tx.origin, "The minter is another contract");

        // What token do we start minting with?
        uint startTokenID = _startTokenId() + _totalMinted();
        uint mintUntilTokenID =  quantity + startTokenID;

        for(uint256 tokenId = startTokenID; tokenId < mintUntilTokenID; tokenId++) {

            /// got get our random traits
            uint[6] memory randomSeeds = _randomSeed(lastBlockHash,tokenId);

            /// set this new Baby traits!
            _setBabyTraits(tokenId, randomSeeds);
        }
        lastBlockHash = blockhash(block.number - 1);
        lastBlockNumber = block.number;
        _safeMint(msg.sender, quantity);

    }

    function _randomSeed(bytes32 _lastBlockHash, uint256 _tokenId) internal pure returns (uint[6] memory _randomSeeds) {
        // Initial seed
        _randomSeeds[0] = uint256(keccak256(abi.encodePacked(_lastBlockHash, _tokenId))) % 101;

        // Generate subsequent seeds
        for (uint i = 1; i < 6; i++) {
            _randomSeeds[i] = uint256(keccak256(abi.encodePacked(_randomSeeds[i - 1], _tokenId))) % 101;
        }

        return _randomSeeds;
    }

    function _setBabyTraits(uint _tokenID, uint[6] memory _randomSeeds) internal {
        // Randomly select traits
        uint randFace   = _pickTraitByProbability(_randomSeeds[0], face_data, face_probability);
        uint randEyes  = _pickTraitByProbability(_randomSeeds[1], eyes_data, eye_probability);
        uint randHair  = _pickTraitByProbability(_randomSeeds[2], hair_data, hair_probability);
        uint randEarrings  = _pickTraitByProbability(_randomSeeds[3], earrings_data, earrings_probability);
        uint randMouth  = _pickTraitByProbability(_randomSeeds[4],  mouth_data, mouth_probability);
        uint randHat  = _pickTraitByProbability(_randomSeeds[5], hat_data, hat_probability);

        TraitStruct memory newTraits = TraitStruct({
            face: randFace,
            eyes: randEyes,
            hair: randHair,
            earrings: randEarrings,
            mouth: randMouth,
            hat: randHat
        });

        // Assign the generated traits to the token
        tokenTraits[_tokenID] = newTraits;

    }

    function _pickTraitByProbability(uint seed, bytes[] memory traitArray, uint[] memory traitProbability) internal pure returns (uint) {
        require(traitArray.length > 0, "Elements array is empty");
        require(traitArray.length == traitProbability.length, "Elements and weights length mismatch");
        
        for (uint i = 0; i < traitProbability.length; i++) {
            if(seed < traitProbability[i]) {
                return i;
            }
        }
        // Fallback, return first element as a safe default
        return 0;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        // Get image
        string memory image = buildSVG(tokenId);

        // Encode SVG data to base64
        string memory base64Image = Base64.encode(bytes(image));

        // Build JSON metadata
        // string memory json = string(
        //     abi.encodePacked(
        //         '{"name": "OnChain Baby # ', Strings.toString(tokenId), '",
        //         "description": "OnChain Babies are born on Base - 100% stored on the Blockchain",',
        //         "image_data": "', buildSVG(tokenId), '",',
        //         "attributes": [', _getBabyTraits(tokenId), ']}'
        //     )
        // );

        string memory json = string.concat(
        '{"name":"OnChain Baby #', Strings.toString(tokenId),'",
        "description":"OnChain Babies are born on Base - 100% stored on the Blockchain",
        "attributes": [', _getBabyTraits(tokenId), ']
        ',attributes,',',
        '"image":"data:image/svg+xml;base64,', base64Image,'"','}'
        );

        // Encode JSON data to base64
        string memory base64Json = Base64.encode(bytes(json));

        // Construct final URI
        return string(abi.encodePacked('data:application/json;base64,', base64Json));
    }

    function buildSVG(uint tokenid) public view returns (string memory) {

        require(_exists(tokenid), "Token does not exist");

        TraitStruct memory localTraits = tokenTraits[tokenid];

        string memory svg = string(abi.encodePacked(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" shape-rendering="crispEdges" width="512" height="512">',
        '<rect width="16" height="16" fill="#7db2b2"/>',
            _getSVGTraitData(face_data[localTraits.face]),
            _getSVGTraitData(eyes_data[localTraits.eyes]),
            _getSVGTraitData(hair_data[localTraits.hair]),
            _getSVGTraitData(earrings_data[localTraits.earrings]),
            _getSVGTraitData(mouth_data[localTraits.mouth]),
            _getSVGTraitData(hat_data[localTraits.hat]),
        '</svg>'
        ));
        return svg;

    }

    function _getSVGTraitData(bytes memory data) internal pure returns (string memory) {

        require(data.length % 5 == 0, "Invalid number of reacts");

        /// if empty this is a transparent react
        if (data.length == 0) {
             return "<rect x=\"0\" y=\"0\" width=\"0\" height=\"0\" fill=\"rgb(0,0,0)\"/>"; 
        }

        // Initialize arrays to store values
        uint reactCount = data.length / 5;


        /// react string to return
        string memory rects;

        uint[] memory x = new uint[](reactCount);
        uint[] memory y = new uint[](reactCount);
        uint[] memory r = new uint[](reactCount);
        uint[] memory g = new uint[](reactCount);
        uint[] memory b = new uint[](reactCount);

        // Iterate through each react and get the values we need
        for (uint i = 0; i < reactCount; i++) {

            // Convert and assign values to respective arrays
            x[i] = uint8(data[i * 5]);
            y[i] = uint8(data[i * 5 + 1]);
            r[i] = uint8(data[i * 5 + 2]);
            g[i] = uint8(data[i * 5 + 3]);
            b[i] = uint8(data[i * 5 + 4]);

            // Convert uint values to strings
            string memory xStr = Strings.toString(x[i]);
            string memory yStr = Strings.toString(y[i]);
            string memory rStr = Strings.toString(r[i]);
            string memory gStr = Strings.toString(g[i]);
            string memory bStr = Strings.toString(b[i]);

            rects = string(abi.encodePacked(rects, '<rect x="', xStr, '" y="', yStr, '" width="1" height="1" fill="rgb(', rStr, ',', gStr, ',', bStr, ')" />'));
        }

        return rects;
    }

    function _getBabyTraits(uint tokenid) internal view returns (string memory) {

        TraitStruct memory traits = tokenTraits[tokenid];

        string memory metadata = string(abi.encodePacked(
        '{"trait_type":"Face", "value":"', face_traits[traits.face], '"},',
        '{"trait_type":"Eyes", "value":"', eyes_traits[traits.eyes], '"}',
        '{"trait_type":"Hair", "value":"', hair_traits[traits.hair], '"}',
        '{"trait_type":"Earrings", "value":"', hair_traits[traits.earrings], '"}',
        '{"trait_type":"Mouth", "value":"', hair_traits[traits.mouth], '"}',
        '{"trait_type":"Hat", "value":"', hair_traits[traits.hat], '"}'
        ));

        return metadata;

    }


//// Admin methods
    function toggleMinting() external onlyOwner {
        mintEnabled = !mintEnabled;
    }

    function setMaxFree(uint _newMaxFree) external onlyOwner {
        maxFree = _newMaxFree;
    }

    function devMint(uint _quantity) external onlyOwner {
        _internalMint(_quantity);
    }

    function addToWhiteList(address[] calldata addresses) external onlylistController nonReentrant {
        for (uint i = 0; i < addresses.length; i++) {
            whiteListed[addresses[i]] = true;
        }
    }

    function changelistController(address _address) external onlyOwner {
        listController = _address;
    }

    function withdraw() external onlyOwner nonReentrant {
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "Transfer failed.");
    }

}