// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Address.sol";

interface IFeeManager {
    struct FeeRecipients {
        address receiver;
        uint256 feeBips;
    }
    function setCreatorFee(FeeRecipients[] memory _splitInfo, address _tokenAddress, uint256 _tokenId) external;
    function getCreatorFee(address _tokenAddress, uint256 _tokenId) view external returns (FeeRecipients[] memory);
    function getTradeFeeBips(address _tokenAddress, uint256 _tokenId) view external returns (uint256 sum);
    function settleTradeFee(address _tokenAddress, uint256 _tokenId, address _referral) payable external;
    function withdrawBalance() external;
    function transferWithdrawFee() payable external;
}
 
interface ITradeEventReceiver {
    function onTradeEvent(address _nftAddress, uint256 _nftId, uint256 _priceInEth, address _seller, address _buyer) external;
}

contract ArtMarket is Ownable {
    struct Asset {
        address tokenAddress;
        uint256 tokenId;
    }

    struct Listing {
        address payTo;
        uint256 price;
    }

    struct Auction {
        Asset asset;
        address payTo;
        uint256 startPrice;
        uint256 minIncremental;
        uint256 startTimestamp;
        uint256 finishTimestamp;
    }

    struct User {
        uint256 profitTotal;
        uint256 claimed;
        uint256 balance;
    }

    struct Order {
        address maker;
        uint256 price;
        uint256 expirationTime;
        address referral;
    }

    struct AuctionBid {
        address maker;
        uint256 price;
        address referral;
    }

    struct TradeHistory {
        address buyer;
        uint256 price;
        uint256 tradeAt;
        Asset asset;
    }

    mapping(address => mapping(uint256 => Listing)) public listings;
    mapping(address => mapping(uint256 => Order[])) public orders;
    mapping(address => mapping(uint256 => Auction)) public auctions;
    mapping(address => mapping(uint256 => AuctionBid[])) public auctionBids;
    mapping(address => User) public users;
    mapping(address => bool) public blockWithdraw;

    bool isInitialized;
    uint256 public maxPrice;
    uint256 constant MAX_BIPS = 10000;
    address constant NULL_ADDR = 0x0000000000000000000000000000000000000000;

    IFeeManager public feeManager;
    ITradeEventReceiver public tradeEventReceiver;

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _reentrancyStatus;

    modifier nonReentrant() {
        require(_reentrancyStatus != _ENTERED, "ReentrancyGuard: reentrant call");
        _reentrancyStatus = _ENTERED;
        _;
        _reentrancyStatus = _NOT_ENTERED;
    }

    event AssetListed(address indexed tokenAddress, uint256 indexed tokenId, address indexed seller, uint256 price);
    event AssetListingCanceled(address indexed tokenAddress, uint256 indexed tokenId, address indexed seller);
    event AssetPriceChanged(address indexed tokenAddress, uint256 indexed tokenId, address indexed seller, uint256 price);
    event AuctionCreated(address indexed tokenAddress, uint256 indexed tokenId, address indexed seller, uint256 startPrice, uint256 startTimestamp, uint256 finishTimestamp, uint256 minIncremental);
    event AuctionBidded(address indexed tokenAddress, uint256 indexed tokenId, address indexed buyer, uint256 price, address referral);
    event AuctionFinished(address indexed tokenAddress, uint256 indexed tokenId, address indexed buyer, uint256 finalPrice);
    event BiddingAsset(address indexed tokenAddress, uint256 indexed tokenId, uint256 price, uint256 expirationTime, address indexed buyer);
    event BiddingAccepted(address indexed tokenAddress, uint256 indexed tokenId, uint256 bidPrice, uint256 actualTradePrice, uint256 expirationTime, address seller, address indexed buyer);
    event BiddingEdited(address indexed tokenAddress, uint256 indexed tokenId, uint256 bidPrice, uint256 actualTradePrice, uint256 expirationTime, address seller, address indexed buyer);
    event BiddingCanceled(address indexed tokenAddress, uint256 indexed tokenId, uint256 price, uint256 expirationTime, address indexed buyer);
    event ExpiredBiddingRemoved(address indexed tokenAddress, uint256 indexed tokenId, uint256 price, uint256 expirationTime, address indexed buyer);
    event BuyNow(address indexed tokenAddress, uint256 indexed tokenId, uint256 price, address seller, address indexed buyer);
    event SaleProfitMade(address indexed user, uint256 amount, address indexed tokenAddress, uint256 indexed tokenId);
    event SaleProfitClaimed(address indexed user, uint256 amount);
    event ProfitWithdrawBlocked(address indexed user, bool isBlock);

    function initialize(
        address payable _feeManager,
        address _tradeEventReceiver
    ) public {
        require(!isInitialized, "Already initialized");
        isInitialized = true;

        maxPrice = 1000 * 1e18;
        feeManager = IFeeManager(_feeManager);
        tradeEventReceiver = ITradeEventReceiver(_tradeEventReceiver);

        _transferOwnership(msg.sender);
    }

    function listingAsset(address _payTo, address _tokenAddress, uint256 _tokenId, uint256 _price) public nonReentrant {
        require(_price > 0, "The price must be larger than 0");
        require(_price <= maxPrice, "The price is too high");

        IERC721(_tokenAddress).transferFrom(msg.sender, address(this), _tokenId);

        listings[_tokenAddress][_tokenId] = Listing({
            payTo: _payTo,
            price: _price
        });

        emit AssetListed(_tokenAddress, _tokenId, _payTo, _price);

        _settleTradeAfterListing(_tokenAddress, _tokenId);
    }

    function batchListingAssets(Listing[] calldata _listings, Asset[] calldata _assets) external {
        require(_listings.length > 0, "Listing data is empty");
        for (uint i = 0; i < _listings.length; i++) {
            listingAsset(
                _listings[i].payTo,
                _assets[i].tokenAddress,
                _assets[i].tokenId,
                _listings[i].price
            );
        }
    }

    function cancelListing(address _tokenAddress, uint256 _tokenId) public nonReentrant {
        Listing memory listing = listings[_tokenAddress][_tokenId];
        require(listing.payTo != address(0), "The asset is not listed now");
        require(listing.payTo == address(msg.sender), "Only seller can cancel listing");

        emit AssetListingCanceled(_tokenAddress, _tokenId, listing.payTo);

        _transferAsset(listing.payTo, _tokenAddress, _tokenId);
        delete listings[_tokenAddress][_tokenId];
    }

    function batchCancelListing(Asset[] calldata _assets) external {
        for (uint i = 0; i < _assets.length; i++) {
            cancelListing(
                _assets[i].tokenAddress,
                _assets[i].tokenId
            );
        }
    }

    function setListingPrice(address _tokenAddress, uint256 _tokenId, uint256 _price) external nonReentrant {
        require(listings[_tokenAddress][_tokenId].payTo != address(0), "The asset is not listed now");
        require(listings[_tokenAddress][_tokenId].payTo == msg.sender, "Only owner can set the price");
        require(listings[_tokenAddress][_tokenId].price != _price, "The new price is same to current price");
        require(_price <= maxPrice, "The price is too high");
        require(_price > 0, "The price must be larger than 0");

        listings[_tokenAddress][_tokenId].price = _price;

        emit AssetPriceChanged(_tokenAddress, _tokenId, msg.sender, _price);

        _settleTradeAfterListing(_tokenAddress, _tokenId);
        _removeExpiredBid(_tokenAddress, _tokenId);
    }

    function acceptBid(address _tokenAddress, uint256 _tokenId, address _maker, uint256 _price) external nonReentrant {
        Listing storage listing = listings[_tokenAddress][_tokenId];
        Order[] storage orderList = orders[_tokenAddress][_tokenId];

        for (uint i = 0; i < orderList.length; i++) {
            Order memory order = orderList[i];
            if (order.price == _price &&
                order.maker == _maker &&
                (order.expirationTime >= block.timestamp || order.expirationTime == 0)) {

                if (listing.payTo != address(0)) {
                    require(listing.payTo == msg.sender, "Only owner can accept bid");
                    _transferAsset(order.maker, _tokenAddress, _tokenId);
                    delete listings[_tokenAddress][_tokenId];
                } else {
                    require(IERC721(_tokenAddress).ownerOf(_tokenId) == address(msg.sender), "Only owner can accept bid");
                    IERC721(_tokenAddress).transferFrom(msg.sender, order.maker, _tokenId);
                }

                // settle fee and profit
                uint256 fee = order.price * feeManager.getTradeFeeBips(_tokenAddress, _tokenId) / MAX_BIPS;
                feeManager.settleTradeFee{value: fee}(_tokenAddress, _tokenId, order.referral);

                uint256 payAmount = order.price - fee;
                users[msg.sender].profitTotal += payAmount;
                users[msg.sender].balance += payAmount;

                tradeEventReceiver.onTradeEvent(_tokenAddress, _tokenId, order.price, msg.sender, order.maker);
                emit BiddingAccepted(_tokenAddress, _tokenId, order.price, order.price, order.expirationTime, msg.sender, order.maker);
                emit SaleProfitMade(msg.sender, payAmount, _tokenAddress, _tokenId);

                // initialize
                orderList[i] = orderList[orderList.length - 1];
                orderList.pop();
                break;
            }
        }

        _removeExpiredBid(_tokenAddress, _tokenId);
    }

    function buyNow(address _tokenAddress, uint256 _tokenId, address _referral) payable public {
        _buyNow(_tokenAddress, _tokenId, _referral, msg.value);
    }

    function buyBatchNow(Asset[] calldata _tokens, address _referral) payable external {
        uint256 value = msg.value;
        for (uint i = 0; i < _tokens.length; i++) {
            Listing memory listing = listings[_tokens[i].tokenAddress][_tokens[i].tokenId];
            require(value >= listing.price, "The value is not enough to buy the assets");
            value -= listing.price;
            _buyNow(_tokens[i].tokenAddress, _tokens[i].tokenId, _referral, listing.price);
        }
        require(value == 0, "The value must be same to sum of asset prices");
    }

    function biddingAsset(address _tokenAddress, uint256 _tokenId, uint256 _expirationTime, address _referral) payable external nonReentrant {
        require(msg.value > 0, "Cannot bidding with 0 value");
        require(_expirationTime > block.timestamp, "The expiration time has already been past");
        Order memory order = Order({
            maker: msg.sender,
            price: msg.value,
            expirationTime: _expirationTime,
            referral: _referral
        });
        orders[_tokenAddress][_tokenId].push(order);

        emit BiddingAsset(_tokenAddress, _tokenId, msg.value, _expirationTime, msg.sender);

        _settleTradeAfterBidding(_tokenAddress, _tokenId, _referral);
        _removeExpiredBid(_tokenAddress, _tokenId);
    }

    function cancelBidding(address _tokenAddress, uint256 _tokenId, uint256 _price, uint256 _expirationTime) external nonReentrant {
        Order[] storage orderList = orders[_tokenAddress][_tokenId];
        bool isCanceled;
        for (uint i = 0; i < orderList.length; i++) {
            if (orderList[i].maker == msg.sender && 
                orderList[i].price == _price &&
                orderList[i].expirationTime == _expirationTime) {

                // return bidding
                address payable returnTo = payable(msg.sender);
                returnTo.transfer(_price);

                orderList[i] = orderList[orderList.length - 1];
                orderList.pop();

                emit BiddingCanceled(_tokenAddress, _tokenId, _price, _expirationTime, msg.sender);
                isCanceled = true;

                break;
            }
        }
        require(isCanceled, "No bidding matched to cancel");

        // remove expired bid
        _removeExpiredBid(_tokenAddress, _tokenId);
    }

    function createAuction(
        address _tokenAddress,
        uint256 _tokenId,
        uint256 _startPrice,
        uint256 _startTimestamp,
        uint256 _finishTimestamp,
        uint256 _minIncremental
    ) external nonReentrant {
        IERC721(_tokenAddress).transferFrom(address(msg.sender), address(this), _tokenId);
        Auction storage auction = auctions[_tokenAddress][_tokenId];
        require(auction.startTimestamp == 0 &&
                auction.finishTimestamp == 0 &&
                auction.startPrice == 0 &&
                auction.minIncremental == 0, "Auction is on");
        
        // cancel listing
        Listing storage listing = listings[_tokenAddress][_tokenId];
        if (listing.price > 0) {
            delete listings[_tokenAddress][_tokenId];
            _removeExpiredBid(_tokenAddress, _tokenId);
        }
        
        auction.startPrice = _startPrice;
        auction.startTimestamp = _startTimestamp;
        auction.finishTimestamp = _finishTimestamp;
        auction.minIncremental = _minIncremental;
        emit AuctionCreated(_tokenAddress, _tokenId, msg.sender, _startPrice, _startTimestamp, _finishTimestamp, _minIncremental);
    }

    function biddingAuction(address _tokenAddress, uint256 _tokenId, uint256 _price, address _referral) payable external nonReentrant {
        Auction memory auction = auctions[_tokenAddress][_tokenId];
        require(block.timestamp >= auction.startTimestamp &&
                block.timestamp <= auction.finishTimestamp, "No auction time");
        AuctionBid[] storage bidList = auctionBids[_tokenAddress][_tokenId];
        if (bidList.length > 0) {
            AuctionBid memory lastBid = bidList[bidList.length - 1];
            require(_price >= lastBid.price + auction.minIncremental,
                "Bid price must be larger than current bid price");
            // return bidding
            address payable returnTo = payable(lastBid.maker);
            returnTo.transfer(lastBid.price);
        }

        bidList.push(AuctionBid({
            maker: msg.sender,
            price: _price,
            referral: _referral
        }));
        emit AuctionBidded(_tokenAddress, _tokenId, msg.sender, _price, _referral);
    }

    function finalizeAuction(address _tokenAddress, uint256 _tokenId) external nonReentrant {
        Auction memory auction = auctions[_tokenAddress][_tokenId];
        require(auction.finishTimestamp > 0, "No auction for the nft");
        require(auction.finishTimestamp <= block.timestamp, "Auction is not finished yet");
        AuctionBid[] storage bidList = auctionBids[_tokenAddress][_tokenId];
        AuctionBid memory lastBid = bidList[bidList.length - 1];
        _transferAsset(lastBid.maker, _tokenAddress, _tokenId);

        // settle fee and profit
        uint256 fee = lastBid.price * feeManager.getTradeFeeBips(_tokenAddress, _tokenId) / MAX_BIPS;
        feeManager.settleTradeFee{value: fee}(_tokenAddress, _tokenId, lastBid.referral);

        uint256 payAmount = lastBid.price - fee;
        users[auction.payTo].profitTotal += payAmount;
        users[auction.payTo].balance += payAmount;

        emit AuctionFinished(_tokenAddress, _tokenId, lastBid.maker, lastBid.price);
        emit SaleProfitMade(auction.payTo, payAmount, _tokenAddress, _tokenId);

        // remove auction data
        delete auctions[_tokenAddress][_tokenId];
        for (; bidList.length > 0;) {
            delete bidList[bidList.length - 1];
            bidList.pop();
        }
    }

    function withdrawBalance() external nonReentrant {
        User storage user = users[msg.sender];
        require(user.balance > 0, "No balance to withdraw");
        require(!blockWithdraw[msg.sender], "Withdraw is blocked");
        user.claimed += user.balance;
        address payable to = payable(msg.sender);
        uint256 amount = user.balance;
        to.transfer(amount);
        user.balance = 0;

        emit SaleProfitClaimed(msg.sender, amount);
    }

    function setMaxPrice(uint256 _maxPrice) external onlyOwner {
        maxPrice = _maxPrice;
    }

    function setTradeEventReceiver(address _tradeEventReceiver) external onlyOwner {
        tradeEventReceiver = ITradeEventReceiver(_tradeEventReceiver);
    }

    function setFeeManager(address _feeManager) external onlyOwner {
        feeManager = IFeeManager(_feeManager);
    }

    function setBlockWithdraw(address user, bool isBlock) external onlyOwner {
        blockWithdraw[user] = isBlock;
        emit ProfitWithdrawBlocked(user, isBlock);
    }
    

    function _settleTradeAfterListing(address _tokenAddress, uint256 _tokenId) internal {
        Listing storage listing = listings[_tokenAddress][_tokenId];
        Order[] storage orderList = orders[_tokenAddress][_tokenId];
        if (orderList.length == 0) return;

        uint idxMax = 99999999;
        uint max = 0;
        for (uint i = 0; i < orderList.length; i++) {
            Order memory order = orderList[i];

            // find the highest bid price which is acceptable to listing price
            if (listing.price <= order.price &&
                (order.expirationTime >= block.timestamp || order.expirationTime == 0) &&
                order.price > max
            ) {
                max = order.price;
                idxMax = i;
            }
        }

        if (idxMax != 99999999) {
            Order memory order = orderList[idxMax];

            _transferAsset(order.maker, _tokenAddress, _tokenId);

            // settle fee and profit
            uint256 fee = order.price * feeManager.getTradeFeeBips(_tokenAddress, _tokenId) / MAX_BIPS;
            feeManager.settleTradeFee{value: fee}(_tokenAddress, _tokenId, order.referral);

            uint256 payAmount = order.price - fee;
            users[listing.payTo].profitTotal += payAmount;
            users[listing.payTo].balance += payAmount;

            tradeEventReceiver.onTradeEvent(_tokenAddress, _tokenId, order.price, listing.payTo, order.maker);
            emit BiddingAccepted(_tokenAddress, _tokenId, order.price, order.price, order.expirationTime, listing.payTo, order.maker);
            emit SaleProfitMade(listing.payTo, payAmount, _tokenAddress, _tokenId);

            // initialize
            delete listings[_tokenAddress][_tokenId];
            orderList[idxMax] = orderList[orderList.length - 1];
            orderList.pop();
        }
    }

    function _settleTradeAfterBidding(address _tokenAddress, uint256 _tokenId, address _referral) internal {
        Listing storage listing = listings[_tokenAddress][_tokenId];
        if (listing.payTo == address(0)) return;
        Order[] storage orderList = orders[_tokenAddress][_tokenId];
        Order memory order = orderList[orderList.length - 1];

        if (listing.price <= order.price &&
            (order.expirationTime >= block.timestamp || order.expirationTime == 0)) {
            if (listing.price < order.price) {
                uint256 returnValue = order.price - listing.price;
                address payable returnTo = payable(order.maker);
                returnTo.transfer(returnValue);
            }

            _transferAsset(order.maker, _tokenAddress, _tokenId);

            // settle fee and profit
            uint256 fee = listing.price * feeManager.getTradeFeeBips(_tokenAddress, _tokenId) / MAX_BIPS;
            feeManager.settleTradeFee{value: fee}(_tokenAddress, _tokenId, _referral);

            uint256 payAmount = listing.price - fee;
            users[listing.payTo].profitTotal += payAmount;
            users[listing.payTo].balance += payAmount;

            tradeEventReceiver.onTradeEvent(_tokenAddress, _tokenId, listing.price, listing.payTo, order.maker);
            emit BiddingAccepted(_tokenAddress, _tokenId, order.price, listing.price, order.expirationTime, listing.payTo, order.maker);
            emit SaleProfitMade(listing.payTo, payAmount, _tokenAddress, _tokenId);

            // initialize listing and bidding
            delete listings[_tokenAddress][_tokenId];
            orderList.pop();
        }
    }

    function _removeExpiredBid(address _tokenAddress, uint256 _tokenId) internal {
        Order[] storage orderList = orders[_tokenAddress][_tokenId];
        for (uint i = 0; i < orderList.length; ) {
            if (orderList[i].expirationTime != 0 &&
                orderList[i].expirationTime < block.timestamp) {
                address payable to = payable( orderList[i].maker );
                to.transfer(orderList[i].price);

                emit ExpiredBiddingRemoved(_tokenAddress, _tokenId, orderList[i].price, orderList[i].expirationTime, orderList[i].maker);

                orderList[i] = orderList[orderList.length - 1];
                orderList.pop();
            } else
                i++;
        }
    }

    function _transferAsset(address _to, address _tokenAddress, uint256 _tokenId) internal {
        IERC721(_tokenAddress).transferFrom(address(this), _to, _tokenId);
    }

    function _buyNow(address _tokenAddress, uint256 _tokenId, address _referral, uint256 value) internal nonReentrant {
        Listing storage listing = listings[_tokenAddress][_tokenId];
        require(listing.payTo != address(0), "The asset is not listed");
        require(listing.price == value, "The value is not equal to the price");

        _transferAsset(msg.sender, _tokenAddress, _tokenId);

        // settle fee and profit
        uint256 fee = listing.price * feeManager.getTradeFeeBips(_tokenAddress, _tokenId) / MAX_BIPS;
        feeManager.settleTradeFee{value: fee}(_tokenAddress, _tokenId, _referral);

        uint256 payAmount = listing.price - fee;
        users[listing.payTo].profitTotal += payAmount;
        users[listing.payTo].balance += payAmount;

        // remove expired bid
        _removeExpiredBid(_tokenAddress, _tokenId);

        // onTradeEvent
        tradeEventReceiver.onTradeEvent(_tokenAddress, _tokenId, listing.price, listing.payTo, msg.sender);
        emit BuyNow(_tokenAddress, _tokenId, listing.price, listing.payTo, msg.sender);
        emit SaleProfitMade(listing.payTo, payAmount, _tokenAddress, _tokenId);

        // initialize listing
        delete listings[_tokenAddress][_tokenId];
    }
}

