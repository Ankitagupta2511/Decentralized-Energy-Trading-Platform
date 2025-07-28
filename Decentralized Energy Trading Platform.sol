// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract Project {
    // Energy listing structure
    struct EnergyListing {
        uint256 id;
        address producer;
        uint256 energyAmount; // in kWh
        uint256 pricePerUnit; // in wei per kWh
        uint256 timestamp;
        bool isActive;
        string location;
        string energySource; // solar, wind, hydro, etc.
    }
    
    // Energy transaction structure
    struct EnergyTransaction {
        uint256 id;
        uint256 listingId;
        address producer;
        address consumer;
        uint256 energyAmount;
        uint256 totalPrice;
        uint256 timestamp;
        bool isCompleted;
    }
    
    // User profile structure
    struct User {
        address userAddress;
        string name;
        string location;
        uint256 totalEnergyProduced;
        uint256 totalEnergyConsumed;
        uint256 totalEarnings;
        uint256 totalSpent;
        bool isRegistered;
        bool isVerifiedProducer;
    }
    
    // State variables
    mapping(uint256 => EnergyListing) public energyListings;
    mapping(uint256 => EnergyTransaction) public energyTransactions;
    mapping(address => User) public users;
    mapping(address => uint256[]) public userListings; // producer => listing IDs
    mapping(address => uint256[]) public userPurchases; // consumer => transaction IDs
    
    uint256 public listingCounter;
    uint256 public transactionCounter;
    address public admin;
    uint256 public platformFeePercentage = 2; // 2% platform fee
    
    // Events
    event UserRegistered(address indexed user, string name, string location);
    event EnergyListed(uint256 indexed listingId, address indexed producer, uint256 amount, uint256 price);
    event EnergyPurchased(uint256 indexed transactionId, address indexed consumer, address indexed producer, uint256 amount);
    event ListingCancelled(uint256 indexed listingId, address indexed producer);
    event ProducerVerified(address indexed producer);
    
    // Modifiers
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can perform this action");
        _;
    }
    
    modifier onlyRegistered() {
        require(users[msg.sender].isRegistered, "User must be registered");
        _;
    }
    
    modifier onlyVerifiedProducer() {
        require(users[msg.sender].isVerifiedProducer, "Must be verified producer");
        _;
    }
    
    modifier listingExists(uint256 _listingId) {
        require(_listingId > 0 && _listingId <= listingCounter, "Listing does not exist");
        _;
    }
    
    modifier listingActive(uint256 _listingId) {
        require(energyListings[_listingId].isActive, "Listing is not active");
        _;
    }
    
    constructor() {
        admin = msg.sender;
        listingCounter = 0;
        transactionCounter = 0;
    }
    
    // Register user in the platform
    function registerUser(string memory _name, string memory _location) public {
        require(!users[msg.sender].isRegistered, "User already registered");
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(bytes(_location).length > 0, "Location cannot be empty");
        
        users[msg.sender] = User({
            userAddress: msg.sender,
            name: _name,
            location: _location,
            totalEnergyProduced: 0,
            totalEnergyConsumed: 0,
            totalEarnings: 0,
            totalSpent: 0,
            isRegistered: true,
            isVerifiedProducer: false
        });
        
        emit UserRegistered(msg.sender, _name, _location);
    }
    
    // Core Function 1: List energy for sale
    function listEnergy(
        uint256 _energyAmount,
        uint256 _pricePerUnit,
        string memory _location,
        string memory _energySource
    ) public onlyRegistered onlyVerifiedProducer returns (uint256) {
        require(_energyAmount > 0, "Energy amount must be greater than 0");
        require(_pricePerUnit > 0, "Price must be greater than 0");
        require(bytes(_location).length > 0, "Location cannot be empty");
        require(bytes(_energySource).length > 0, "Energy source cannot be empty");
        
        listingCounter++;
        
        energyListings[listingCounter] = EnergyListing({
            id: listingCounter,
            producer: msg.sender,
            energyAmount: _energyAmount,
            pricePerUnit: _pricePerUnit,
            timestamp: block.timestamp,
            isActive: true,
            location: _location,
            energySource: _energySource
        });
        
        userListings[msg.sender].push(listingCounter);
        
        emit EnergyListed(listingCounter, msg.sender, _energyAmount, _pricePerUnit);
        
        return listingCounter;
    }
    
    // Core Function 2: Purchase energy from a listing
    function purchaseEnergy(uint256 _listingId, uint256 _energyAmount) 
        public 
        payable 
        onlyRegistered 
        listingExists(_listingId) 
        listingActive(_listingId) 
    {
        EnergyListing storage listing = energyListings[_listingId];
        require(listing.producer != msg.sender, "Cannot purchase own energy");
        require(_energyAmount > 0, "Energy amount must be greater than 0");
        require(_energyAmount <= listing.energyAmount, "Not enough energy available");
        
        uint256 totalCost = _energyAmount * listing.pricePerUnit;
        require(msg.value >= totalCost, "Insufficient payment");
        
        // Calculate platform fee
        uint256 platformFee = (totalCost * platformFeePercentage) / 100;
        uint256 producerPayment = totalCost - platformFee;
        
        // Update listing
        listing.energyAmount -= _energyAmount;
        if (listing.energyAmount == 0) {
            listing.isActive = false;
        }
        
        // Create transaction record
        transactionCounter++;
        energyTransactions[transactionCounter] = EnergyTransaction({
            id: transactionCounter,
            listingId: _listingId,
            producer: listing.producer,
            consumer: msg.sender,
            energyAmount: _energyAmount,
            totalPrice: totalCost,
            timestamp: block.timestamp,
            isCompleted: true
        });
        
        // Update user statistics
        users[listing.producer].totalEnergyProduced += _energyAmount;
        users[listing.producer].totalEarnings += producerPayment;
        users[msg.sender].totalEnergyConsumed += _energyAmount;
        users[msg.sender].totalSpent += totalCost;
        
        userPurchases[msg.sender].push(transactionCounter);
        
        // Transfer payments
        payable(listing.producer).transfer(producerPayment);
        // Platform fee stays in contract (can be withdrawn by admin)
        
        // Refund excess payment
        if (msg.value > totalCost) {
            payable(msg.sender).transfer(msg.value - totalCost);
        }
        
        emit EnergyPurchased(transactionCounter, msg.sender, listing.producer, _energyAmount);
    }
    
    // Core Function 3: Get market data and user statistics
    function getMarketData() 
        public 
        view 
        returns (
            uint256 totalActiveListings,
            uint256 totalTransactions,
            uint256 totalEnergyTraded,
            uint256 averagePrice
        ) 
    {
        uint256 activeListings = 0;
        uint256 totalEnergyInMarket = 0;
        uint256 totalValue = 0;
        
        // Count active listings and calculate average price
        for (uint256 i = 1; i <= listingCounter; i++) {
            if (energyListings[i].isActive) {
                activeListings++;
                totalEnergyInMarket += energyListings[i].energyAmount;
                totalValue += energyListings[i].energyAmount * energyListings[i].pricePerUnit;
            }
        }
        
        // Calculate total energy traded
        uint256 energyTraded = 0;
        for (uint256 i = 1; i <= transactionCounter; i++) {
            if (energyTransactions[i].isCompleted) {
                energyTraded += energyTransactions[i].energyAmount;
            }
        }
        
        uint256 avgPrice = totalEnergyInMarket > 0 ? totalValue / totalEnergyInMarket : 0;
        
        return (activeListings, transactionCounter, energyTraded, avgPrice);
    }
    
    // Additional utility functions
    function verifyProducer(address _producer) public onlyAdmin {
        require(users[_producer].isRegistered, "User not registered");
        users[_producer].isVerifiedProducer = true;
        emit ProducerVerified(_producer);
    }
    
    function cancelListing(uint256 _listingId) public listingExists(_listingId) {
        require(energyListings[_listingId].producer == msg.sender, "Only producer can cancel");
        require(energyListings[_listingId].isActive, "Listing already inactive");
        
        energyListings[_listingId].isActive = false;
        emit ListingCancelled(_listingId, msg.sender);
    }
    
    function getUserListings(address _user) public view returns (uint256[] memory) {
        return userListings[_user];
    }
    
    function getUserPurchases(address _user) public view returns (uint256[] memory) {
        return userPurchases[_user];
    }
    
    function getListingDetails(uint256 _listingId) 
        public 
        view 
        listingExists(_listingId) 
        returns (
            address producer,
            uint256 energyAmount,
            uint256 pricePerUnit,
            bool isActive,
            string memory location,
            string memory energySource,
            uint256 timestamp
        ) 
    {
        EnergyListing storage listing = energyListings[_listingId];
        return (
            listing.producer,
            listing.energyAmount,
            listing.pricePerUnit,
            listing.isActive,
            listing.location,
            listing.energySource,
            listing.timestamp
        );
    }
    
    function withdrawPlatformFees() public onlyAdmin {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        payable(admin).transfer(balance);
    }
    
    function updatePlatformFee(uint256 _newFeePercentage) public onlyAdmin {
        require(_newFeePercentage <= 10, "Fee cannot exceed 10%");
        platformFeePercentage = _newFeePercentage;
    }
    
    // Emergency function to pause all trading
    bool public tradingPaused = false;
    
    function pauseTrading() public onlyAdmin {
        tradingPaused = true;
    }
    
    function resumeTrading() public onlyAdmin {
        tradingPaused = false;
    }
    
    modifier whenNotPaused() {
        require(!tradingPaused, "Trading is currently paused");
        _;
    }
}
