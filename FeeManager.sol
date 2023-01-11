pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FeeManager is Ownable {
    struct FeeRecipients {
        address receiver;
        uint256 feeBips;
    }

    struct User {
        uint256 profitTotal;
        uint256 claimed;
        uint256 balance;
    }

    mapping(address => User) public users;
    mapping(address => uint256) public referralFeeBips;
    mapping(address => mapping(uint256 => FeeRecipients[])) public creatorFeeInfo;
    mapping(address => mapping(uint256 => FeeRecipients[])) public appliedCreatorFeeInfo;
    mapping(address => mapping(uint256 => uint256)) public unverifiedProfit;
    mapping(address => bool) public operators;

    bool isInitialized;
    address payable public platformFeeAddress;
    uint256 constant public MAX_BIPS = 10000;
    uint256 public PLATFORM_FEE;
    uint256 public MAX_CREATOR_FEE;
    uint256 public BASIC_REFERRAL_FEE;
    uint256 public UNVERIFIED_CREATOR_FEE;

    event NftRegistrationApproved(address indexed tokenAddress, uint256 indexed tokenId, address indexed receiver, uint256 feeBips);
    event NftRegistrationApplied(address indexed tokenAddress, uint256 indexed tokenId);
    event SetCreatorFee(address indexed tokenAddress, uint256 indexed tokenId, address indexed receiver, uint256 feeBips);
    event FeeProfitClaimed(address indexed user, uint256 amount);
    event CreatorProfitMade(address indexed tokenAddress, uint256 indexed tokenId, address indexed user, uint256 amount);
    event PlatformProfitMade(address indexed tokenAddress, uint256 indexed tokenId, uint256 amount);
    event ReferralProfitMade(address indexed tokenAddress, uint256 indexed tokenId, address indexed user, uint256 amount);

    modifier onlyOperator() {
        require(operators[msg.sender] == true, "Operator account only");
        _;
    }

    receive() external payable {}
    fallback() external payable {}

    function init(
        address payable _platformFeeAddress
    ) external {
        require(!isInitialized, "Already initialized");
        platformFeeAddress = _platformFeeAddress;

        PLATFORM_FEE = 200;
        MAX_CREATOR_FEE = 1000;
        BASIC_REFERRAL_FEE = 0;
        UNVERIFIED_CREATOR_FEE = 500;

        _transferOwnership(msg.sender);
    }

    /** Called by users **/

    function withdrawBalance(address _user) external {
        User storage user = users[_user];
        require(user.balance > 0, "No balance to withdraw");
        user.claimed += user.balance;
        address payable receiver = payable(_user);
        uint256 amountToTransfer = user.balance;
        user.balance = 0;
        receiver.transfer(amountToTransfer);
        emit FeeProfitClaimed(_user, amountToTransfer);
    }

    function setCreatorFee(FeeRecipients[] memory _splitInfo, address _tokenAddress, uint256 _tokenId) public {
        if (creatorFeeInfo[_tokenAddress][_tokenId].length == 0 &&
            isCreator(msg.sender, _tokenAddress, _tokenId) == false && 
            operators[msg.sender] == false) {
            _applyNftRegistration(_splitInfo, _tokenAddress, _tokenId);
            return;
        }

        uint256 feeSum = 0;
        uint i;
        for (i = 0; i < _splitInfo.length; i++) {
            feeSum += _splitInfo[i].feeBips;
            if (i < creatorFeeInfo[_tokenAddress][_tokenId].length) {
                creatorFeeInfo[_tokenAddress][_tokenId][i].receiver = _splitInfo[i].receiver;
                creatorFeeInfo[_tokenAddress][_tokenId][i].feeBips = _splitInfo[i].feeBips;
            } else {
                creatorFeeInfo[_tokenAddress][_tokenId].push(_splitInfo[i]);
            }
            emit SetCreatorFee(_tokenAddress, _tokenId, _splitInfo[i].receiver, _splitInfo[i].feeBips);
        }
        for (; i < creatorFeeInfo[_tokenAddress][_tokenId].length;) {
            creatorFeeInfo[_tokenAddress][_tokenId].pop();
        }
        require(feeSum <= MAX_CREATOR_FEE, "The creator fee must be same to or smaller than 10%");
    }

    function setCreatorFees(FeeRecipients[] memory _splitInfo, address _tokenAddress, uint256[] memory _tokenIds) external {
        for (uint i = 0; i < _tokenIds.length; i++)
            setCreatorFee(_splitInfo, _tokenAddress, _tokenIds[i]);
    }

    /** Called by Marketplace **/
    
    function settleTradeFee(address _tokenAddress, uint256 _tokenId, address _referral) payable external {
        uint256 totalFeeBips = getTradeFeeBips(_tokenAddress, _tokenId);
        uint256 totalFee = msg.value;
        uint256 tradePrice = totalFee * MAX_BIPS / totalFeeBips;

        // settle referral
        uint256 referralFee = 0;
        if (_referral != address(0)) {
            if (referralFeeBips[_referral] > 0) {
                referralFee = totalFee * PLATFORM_FEE / totalFeeBips * referralFeeBips[_referral] / MAX_BIPS;
            } else {
                referralFee = totalFee * PLATFORM_FEE / totalFeeBips * BASIC_REFERRAL_FEE / MAX_BIPS;
            }
            users[_referral].profitTotal += referralFee;
            users[_referral].balance += referralFee;
            emit ReferralProfitMade(_tokenAddress, _tokenId, _referral, referralFee);
        }
        
        // settle platform
        uint256 platformFee = totalFee * PLATFORM_FEE / totalFeeBips - referralFee;
        users[platformFeeAddress].profitTotal += platformFee;
        users[platformFeeAddress].balance += platformFee;
        emit PlatformProfitMade(_tokenAddress, _tokenId, platformFee);

        // settle creators
        FeeRecipients[] memory recipients;
        if (creatorFeeInfo[_tokenAddress][_tokenId].length > 0) {
            recipients = creatorFeeInfo[_tokenAddress][_tokenId];
            for (uint i = 0; i < recipients.length; i++) {
                uint256 fee = tradePrice * recipients[i].feeBips / MAX_BIPS;
                users[recipients[i].receiver].profitTotal += fee;
                users[recipients[i].receiver].balance += fee;

                emit CreatorProfitMade(_tokenAddress, _tokenId, recipients[i].receiver, fee);
            }
        // } else if (appliedCreatorFeeInfo[_tokenAddress][_tokenId].length > 0) {
        //     recipients = appliedCreatorFeeInfo[_tokenAddress][_tokenId];
        //     uint256 feeBips;
        //     for (uint i = 0; i < recipients.length; i++) {
        //         feeBips += recipients[i].feeBips;
        //     }
        //     unverifiedProfit[_tokenAddress][_tokenId] += tradePrice * feeBips / MAX_BIPS;
        } else {
            unverifiedProfit[_tokenAddress][_tokenId] += tradePrice * UNVERIFIED_CREATOR_FEE / MAX_BIPS;
        }
    }
 
    /** Called by Admin **/
    function approveNftRegistration(address _tokenAddress, uint256 _tokenId) external onlyOperator {
        uint256 feeBipsSum;
        FeeRecipients[] memory feeInfo = appliedCreatorFeeInfo[_tokenAddress][_tokenId];
        for (uint i = feeInfo.length - 1; i >= 0; i--) {
            feeBipsSum += feeInfo[i].feeBips;
        }
        for (uint i = feeInfo.length - 1; i >= 0; i--) {
            creatorFeeInfo[_tokenAddress][_tokenId].push( feeInfo[i] );
            uint256 fee = unverifiedProfit[_tokenAddress][_tokenId] * feeInfo[i].feeBips / feeBipsSum;
            users[feeInfo[i].receiver].profitTotal += fee;
            users[feeInfo[i].receiver].balance += fee;
            appliedCreatorFeeInfo[_tokenAddress][_tokenId].pop();
            emit NftRegistrationApproved(_tokenAddress, _tokenId, feeInfo[i].receiver, feeInfo[i].feeBips);
        }

    }

    // Rate in Platform Fee
    function setReferralFeeBips(address _referral, uint256 _feeBips) external onlyOwner {
        require(_feeBips <= MAX_BIPS, "_feeBips cannot be bigger than 10000. 10000 means 100%");
        referralFeeBips[_referral] = _feeBips;
    }

    function setPlatformFeeBips(uint256 _feeBips) external onlyOwner {
        require(_feeBips <= MAX_BIPS, "_feeBips cannot be bigger than 10000. 10000 means 100%");
        PLATFORM_FEE = _feeBips;
    }

    function setMaxCreatorFeeBips(uint256 _feeBips) external onlyOwner {
        require(_feeBips <= MAX_BIPS, "_feeBips cannot be bigger than 10000. 10000 means 100%");
        MAX_CREATOR_FEE = _feeBips;
    }

    function setBasicReferralFeeBips(uint256 _feeBips) external onlyOwner {
        require(_feeBips <= MAX_BIPS, "_feeBips cannot be bigger than 10000. 10000 means 100%");
        BASIC_REFERRAL_FEE = _feeBips;
    }

    function setUnverifiedCreatorFeeBips(uint256 _feeBips) external onlyOwner {
        require(_feeBips <= MAX_BIPS, "_feeBips cannot be bigger than 10000. 10000 means 100%");
        UNVERIFIED_CREATOR_FEE = _feeBips;
    }

    function setPlatformFeeAddress(address payable _platformFeeAddress) external onlyOwner {
        platformFeeAddress = _platformFeeAddress;
    }

    function setOperator(address _address, bool _isOperator) external onlyOwner {
        operators[_address] = _isOperator;
    }

    /** Internals **/

    function _applyNftRegistration(FeeRecipients[] memory _splitInfo, address _tokenAddress, uint256 _tokenId) internal {
        for (uint i = 0; i < _splitInfo.length; i++) {
            appliedCreatorFeeInfo[_tokenAddress][_tokenId].push( _splitInfo[i] );
        }

        emit NftRegistrationApplied(_tokenAddress, _tokenId);
    }

    /** Views **/

    function getCreatorFee(address _tokenAddress, uint256 _tokenId) view public returns (FeeRecipients[] memory) {
        return creatorFeeInfo[_tokenAddress][_tokenId];
    }

    function isCreator(address _creator, address _tokenAddress, uint256 _tokenId) view public returns (bool) {
        if (Ownable(_tokenAddress).owner() == _creator)
            return true;
        FeeRecipients[] memory info = getCreatorFee(_tokenAddress, _tokenId);
        for (uint i = 0; i < info.length; i++) {
            if (info[i].receiver == _creator)
                return true;
        }
        return false;
    }
 
    function getTradeFeeBips(address _tokenAddress, uint256 _tokenId) view public returns (uint256) {
        FeeRecipients[] memory recipients;
        uint256 sum = PLATFORM_FEE;

        if (creatorFeeInfo[_tokenAddress][_tokenId].length > 0)
            recipients = creatorFeeInfo[_tokenAddress][_tokenId];
        // else if (appliedCreatorFeeInfo[_tokenAddress][_tokenId].length > 0)
        //     recipients = appliedCreatorFeeInfo[_tokenAddress][_tokenId];
        else
            sum += UNVERIFIED_CREATOR_FEE;

        for (uint i = 0; i < recipients.length; i++) {
            sum += recipients[i].feeBips;
        }
        return sum;
    }
}

