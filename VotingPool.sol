// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

pragma experimental ABIEncoderV2;

interface IFeeManager {
    struct FeeRecipients {
        address receiver;
        uint256 feeBips;
    }

    function getCreatorFee(address nftAddress, uint256 nftId) external view returns(FeeRecipients[] memory);
    function MAX_BIPS() external view returns(uint256);
}

interface IEarningReferral {
    struct User {
        address referrer;
        address[] referree;
        uint256 referralsCount;
        uint256 totalReferralCommissions;
        uint256 claimable;
        uint256 claimed;
        uint256 bonus;
    }
    function userInfo(address _user) external view returns (User memory);
    function claim() external;
    function recordReferral(address _user, address _referrer) external;
    function recordReferreeBonus(address _user, uint256 _bonus) external;
    function recordReferralCommission(address _user, uint256 _commission) external;
    function referee(address _user) external view returns (address[] memory);
}

interface IPriceProvider {
    function wethAddress() external view returns (address);
    function usdcAddress() external view returns (address);
    function convertToTargetValueFromPool(IUniswapV3Pool pool, uint256 sourceTokenAmount, address targetAddress) external view returns (uint256);
    function getTokenValueInEth(address token, uint256 amount, uint24 fee) external view returns (uint256);
    function getTokenValueInUsdc(address token, uint256 amount, uint24 fee) external view returns (uint256);
    function getEthValueInUsdc(uint256 amount, uint24 fee) external view returns (uint256);
}

contract ReferralOperator is Ownable {
    // referral
    IEarningReferral public earningReferral;
    uint public referralCommissionRate = 300;
    uint public referreeBonusRate = 1000;

    function setReferral(
        IEarningReferral _earningReferral,
        uint _referralCommissionRate,
        uint _referreeBonusRate
    ) external onlyOwner {
        earningReferral = _earningReferral;
        referralCommissionRate = _referralCommissionRate;
        referreeBonusRate = _referreeBonusRate;
    }

    function recordReferral(address _user, address _referrer) internal {
        if (address(earningReferral) != address(0) &&
            _referrer != address(0) &&
            _referrer != _user) {
            earningReferral.recordReferral(_user, _referrer);
        }
    }

    function payReferralProfit(address _user, uint256 _amount) internal {
        if (address(earningReferral) != address(0) && referralCommissionRate > 0) {
            uint256 commissionAmount = _amount * referralCommissionRate / 10000;
            uint256 bonus = _amount * referreeBonusRate / 10000;

            if (commissionAmount > 0) {
                earningReferral.recordReferralCommission(_user, commissionAmount);
                earningReferral.recordReferreeBonus(_user, bonus);
            }
        }
    }
}


contract ArtVotingPool is Ownable, ReentrancyGuard, ReferralOperator {
    using SafeMath for uint256;

    struct UserInfo {
        uint256 amount; // How many tokens the user has voted
        uint256 boostedAmount;  // How many boosted
        uint256 rewardDebt; // Reward debt
        uint256 reward;
        uint256 rewardClaimed;
        uint256 votingRewardClaimed;
        uint256 holdingReward;
        uint256 holdingRewardClaimed;
        uint256 reward5520Index;
        uint256 reward5520;
        uint256 reward5520Debt;
        uint256 reward5520Claimed;
        Vote[] votes;
        Nft[] holdingNfts;
    }

    struct LockInfo {
        uint256 nextWithdrawalUntil; // When can the user withdraw again.
        uint256 lockPeriod;
    }

    struct ArtInfo {
        uint256 votingAmount;
        uint256 votingRewardDebt;
        uint256 votingRewardClaimed;
        uint256 votingReward;
        uint256 value;
        uint256 holdingRewardDebt;
        uint256 holdingRewardReceived;
        uint256 lastTradeTimestamp;
        address holder;
    }

    struct Nft {
        address nftAddress;
        uint256 nftId;
    }

    struct Vote {
        address nftAddress;
        uint256 nftId;
        uint256 amount;
    }

    struct ArtistRewardInfo {
        uint256 artistReward;
        uint256 artistRewardClaimed;
    }

    bool public isInitialized;
    uint256 public accTokenPerShare;
    uint256 constant PRECISION_FACTOR = 1e18;
    uint256 public startTimestamp;
    uint256 public endTimestamp;
    uint256 public lastRewardTimestamp;
    uint256 public initialRewardPerSecond; // 93353 * 10 ** 18 / (60 * 60 * 24);
    uint256 public rewardReduceRateByDay; // 99967422

    IERC20 public VoteToken;
    uint256 public totalStakedTokenAmount = 0;
    uint256 public totalBoostedAmount = 0;
    uint256 public totalHoldingAmount = 0;
    uint256 public total5520Amount = 0;

    // lock
    uint256 public lockIncentiveReduceRate; // 9964
    uint256 public maxLockIncentiveMultiplier; // 10000 = 100%
    
    // fee
    address public feeAddr;
    uint256 public claimFee = 0;

    // vote
    uint256 constant public votingRewardBP = 1000;
    uint256 constant MAX_BIPS = 10000;
    
    IFeeManager public feeManager;
    address public artMarket;
    IPriceProvider public priceProvider;

    uint256 constant SECONDS_IN_DAY = 86400;

    mapping(address => UserInfo) public userInfo;
    mapping(address => LockInfo) public lockInfo;
    mapping(address => mapping(uint256 => ArtInfo)) public artInfo;
    mapping(address => mapping(address => mapping(uint256 => ArtistRewardInfo))) public artistRewardInfo;

    // user event
    event NewStartAndEndBlocks(uint256 startTimestamp, uint256 endBlock);
    event Deposit(address indexed user, uint256 amount);
    event Voted(address indexed user, uint256 amount, address indexed nftAddress, uint256 indexed nftId);
    event Unvoted(address indexed user, uint256 amount, address indexed nftAddress, uint256 indexed nftId);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event HoldingRewardReceived(address indexed user, uint256 amount, address indexed nftAddress, uint256 indexed nftId);
    event RewardClaimed(address indexed user, uint256 amount);
    event VotingRewardClaimed(address indexed user, uint256 amount);
    event HoldingRewardClaimed(address indexed user, uint256 amount);
    event Reward5520Claimed(address indexed user, uint256 amount);
    
    // admin event
    event RewardValueUpdated(uint256 initialRewardPerSecond, uint256 rewardReduceRateByDay);
    event RewardsStop(uint256 timestamp);
    event NewLockConfiguration(uint256 maxLockPeriod, uint256 maxLockIncentiveMultiplier);
    event SetFeeAddress(address user, address newAddress);
    event SetWithdrawalPenalty(uint256 withdrawalPenalty);
    event SetClaimFee(uint256 claimFee);
    event SetArtMarket(address artMarket);
    event SetPriceProvider(address priceProvider);
    event SetFeeManager(address feeManager);
    event AdminTokenRecovery(address tokenRecovered, uint256 amount);
    
    constructor() public {
    }

    function initialize(
        IERC20 _VoteToken,
        uint256 _startTimestamp,
        uint256 _endTimestamp,
        uint256 _claimFee,
        address _feeAddr,
        address _feeManager,
        address _artMarket,
        address _priceProvider
    ) external {
        require(!isInitialized, "Already initialized");

        // Make this contract initialized
        isInitialized = true;

        VoteToken = _VoteToken;
        startTimestamp = _startTimestamp;
        endTimestamp = _endTimestamp;
        claimFee = _claimFee;

        // Set the lastRewardTimestamp as the startTimestamp
        lastRewardTimestamp = startTimestamp;

        feeAddr = _feeAddr;
        feeManager = IFeeManager(_feeManager);

        artMarket = _artMarket;
        priceProvider = IPriceProvider(_priceProvider);

        initialRewardPerSecond = 1080474530000000000; // 93353 * 10 ** 18 / (60 * 60 * 24);
        rewardReduceRateByDay = 99967422;
        lockIncentiveReduceRate = 9964;
        maxLockIncentiveMultiplier = 10000;

        _transferOwnership(msg.sender);
    }

    function voteArts(Vote[] memory _votes, uint256 _additionalLockPeriodInDays) external {
        _voteArts(_votes, _additionalLockPeriodInDays, address(0));
    }

    function voteArts(Vote[] memory _votes, uint256 _additionalLockPeriodInDays, address _referrer) external {
        _voteArts(_votes, _additionalLockPeriodInDays, _referrer);
    }

    function _voteArts(Vote[] memory _votes, uint256 _additionalLockPeriodInDays, address _referrer) internal nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        LockInfo storage lock = lockInfo[msg.sender];

        _updatePool();

        // settle reward
        user.reward = user.reward.add(pendingReward(msg.sender));
        _settle5520(msg.sender);

        // update voting amount
        for (uint i = 0; i < user.votes.length; i++) {
            _unvoteArt(user.votes[i].amount, user.votes[i].nftAddress, user.votes[i].nftId);
        }
        uint256 newAmount;
        for (uint i = 0; i < _votes.length; i++) {
            newAmount = newAmount.add(_votes[i].amount);
            _voteArt(_votes[i].amount, _votes[i].nftAddress, _votes[i].nftId);
        }
        
        uint256 oldBoostedAmount = user.boostedAmount;
        if (newAmount < user.amount) {
            // Withdraw
            require(block.timestamp >= lock.nextWithdrawalUntil, "The voting amount cannot be reduced until unlocked");
            VoteToken.transfer(address(msg.sender), user.amount.sub(newAmount));

            emit Withdraw(msg.sender, user.amount.sub(newAmount));
        } else if (newAmount > user.amount) {
            // Deposit
            uint256 amountToAdd = newAmount.sub(user.amount);
            uint256 wantBalBefore = IERC20(VoteToken).balanceOf(address(this));
            VoteToken.transferFrom(address(msg.sender), address(this), amountToAdd);
            uint256 wantBalAfter = IERC20(VoteToken).balanceOf(address(this));
            require(wantBalAfter.sub(wantBalBefore) == amountToAdd, "Amount to add is not same to added");

            emit Deposit(msg.sender, amountToAdd);
        }

        // lock update
        uint256 lockPeriod;
        if (lock.nextWithdrawalUntil > block.timestamp)
            lockPeriod = lock.nextWithdrawalUntil.sub(block.timestamp).add(_additionalLockPeriodInDays.mul(SECONDS_IN_DAY));
        else
            lockPeriod = _additionalLockPeriodInDays.mul(SECONDS_IN_DAY);
        lock.nextWithdrawalUntil = block.timestamp.add(lockPeriod);
        lock.lockPeriod = lockPeriod;

        totalStakedTokenAmount = totalStakedTokenAmount.add(newAmount).sub(user.amount);
        user.amount = user.amount.add(newAmount).sub(user.amount);
        uint256 newBoostedAmount = getLockBoostedAmount(user.amount, lockPeriod);
        totalBoostedAmount = totalBoostedAmount.add(newBoostedAmount).sub(oldBoostedAmount);
        user.boostedAmount = newBoostedAmount;
        user.rewardDebt = user.boostedAmount.mul(accTokenPerShare).div(PRECISION_FACTOR);

        // update user.votes[]
        uint length = user.votes.length;
        for (uint i = 0; i < length; i++) {
            user.votes.pop();
        }
        for (uint i = 0; i < _votes.length; i++) {
            if (_votes[i].amount > 0)
                user.votes.push(_votes[i]);
        }

        // update 5520 index
        _update5520index(msg.sender);

        recordReferral(msg.sender, _referrer);
    }

    function onTradeEvent(address _nftAddress, uint256 _nftId, uint256 _priceInEth, address _seller, address _buyer) external {
        require(msg.sender == address(artMarket), "Only art market contract can invoke");

        UserInfo storage seller = userInfo[_seller];
        UserInfo storage buyer = userInfo[_buyer];
        ArtInfo storage art = artInfo[_nftAddress][_nftId];
        _updatePool();

        // settle rewards
        _settle5520(_buyer);
        _settle5520(_seller);
        if (art.value > 0) {
            uint256 holdingReward = pendingHoldingReward(_nftAddress, _nftId);
            seller.holdingReward = seller.holdingReward.add(holdingReward);
            art.holdingRewardReceived = art.holdingRewardReceived.add(holdingReward);
            emit HoldingRewardReceived(_seller, holdingReward, _nftAddress, _nftId);

            if (art.holder != address(0)) {
                UserInfo storage holder = userInfo[art.holder];
                for (uint i = 0; i < holder.holdingNfts.length; i++) {
                    if (_nftAddress == holder.holdingNfts[i].nftAddress &&
                        _nftId == holder.holdingNfts[i].nftId) {
                        _settle5520(art.holder);
                        holder.holdingNfts[i] = holder.holdingNfts[holder.holdingNfts.length - 1];
                        holder.holdingNfts.pop();
                        _update5520index(art.holder);
                        break;
                    }
                }
            }
        }

        // update amounts
        uint256 votePriceInEth;
        uint256 valueInVote;
        try priceProvider.getTokenValueInEth(address(VoteToken), 100000000, 3000) returns (uint256 priceInEth)
        {
            votePriceInEth = priceInEth;
        }
        catch {
            votePriceInEth = 8333;
        }
        valueInVote = _priceInEth.mul(100000000).div(votePriceInEth);
        totalHoldingAmount = totalHoldingAmount.sub(art.value).add(valueInVote);
        art.value = valueInVote;
        art.holdingRewardDebt = valueInVote.mul(accTokenPerShare).div(PRECISION_FACTOR);
        art.lastTradeTimestamp = block.timestamp;
        art.holder = _buyer;

        buyer.holdingNfts.push( Nft({
            nftAddress: _nftAddress,
            nftId: _nftId
        }));
        _update5520index(_buyer);
        _update5520index(_seller);
    }

    function claimReward() external nonReentrant {
        _updatePool();
        
        UserInfo storage user = userInfo[msg.sender];
        uint256 reward = user.reward.add( pendingReward(msg.sender) );
        if (reward > 0) {
            require(reward > claimFee, "Reward must be larger than claim fee");
            user.rewardClaimed = user.rewardClaimed.add(reward); 
            user.reward = 0;
            VoteToken.transfer(address(msg.sender), reward.sub(claimFee));
            VoteToken.transfer(feeAddr, claimFee);
            payReferralProfit(msg.sender, reward.sub(claimFee));

            user.rewardDebt = user.boostedAmount.mul(accTokenPerShare).div(PRECISION_FACTOR);
            emit RewardClaimed(msg.sender, reward);
        }
    }

    function claimVotingReward(address _nftAddress, uint256 _nftId) external nonReentrant {
        _updatePool();
        ArtInfo storage art = artInfo[_nftAddress][_nftId];
        uint256 reward = art.votingReward.add( pendingVotingReward(_nftAddress, _nftId) );
        if (reward > 0) {
            IFeeManager.FeeRecipients[] memory creators = feeManager.getCreatorFee(_nftAddress, _nftId);
            uint256 creatorFeeBipsSum;
            for (uint i = 0; i < creators.length; i++) {
                creatorFeeBipsSum = creatorFeeBipsSum.add(creators[i].feeBips);
            }
            require(creators.length > 0, "Creator info is not registered");
            bool isCreator;
            for (uint i = 0; i < creators.length; i++) {
                uint256 dividedReward;
                if (creatorFeeBipsSum > 0)
                    dividedReward = reward.mul(creators[i].feeBips).div(creatorFeeBipsSum);
                else
                    dividedReward = reward.div(creators.length);
                artistRewardInfo[creators[i].receiver][_nftAddress][_nftId].artistReward += dividedReward;

                if (creators[i].receiver == msg.sender)
                    isCreator = true;
            }
            require(isCreator == true, "Only artist can request to claim voting reward");

            // Withdraw
            ArtistRewardInfo storage rewardInfo = artistRewardInfo[msg.sender][_nftAddress][_nftId];
            require(rewardInfo.artistReward > claimFee, "Voting reward must be larger than claim fee");
            uint256 amountToClaim = rewardInfo.artistReward.sub(claimFee);
            VoteToken.transfer(msg.sender, amountToClaim);
            VoteToken.transfer(feeAddr, claimFee);
            payReferralProfit(msg.sender, amountToClaim);
            emit VotingRewardClaimed(msg.sender, reward);

            UserInfo storage user = userInfo[msg.sender];
            user.votingRewardClaimed = user.votingRewardClaimed.add(rewardInfo.artistReward);
            rewardInfo.artistRewardClaimed += rewardInfo.artistReward;
            rewardInfo.artistReward = 0;
            art.votingRewardClaimed = art.votingRewardClaimed.add(reward);
            art.votingReward = 0;
            art.votingRewardDebt = art.votingAmount.mul(accTokenPerShare).div(PRECISION_FACTOR);
        }
    }

    function claimHoldingReward() external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        
        if (user.holdingReward > 0) {
            require(user.holdingReward > claimFee, "Holding reward must be larger than claim fee");
            
            VoteToken.transfer(address(msg.sender), user.holdingReward.sub(claimFee));
            VoteToken.transfer(feeAddr, claimFee);
            payReferralProfit(msg.sender, user.holdingReward.sub(claimFee));
            user.holdingRewardClaimed = user.holdingRewardClaimed.add(user.holdingReward);
            emit HoldingRewardClaimed(msg.sender, user.holdingReward);
            user.holdingReward = 0;
        }
    }

    function claim5520Reward() external nonReentrant {
        _updatePool();
        _settle5520(msg.sender);

        UserInfo storage user = userInfo[msg.sender];
        
        if (user.reward5520 > 0) {
            require(user.reward5520 > claimFee, "5520 reward must be larger than claim fee");
            
            VoteToken.transfer(address(msg.sender), user.reward5520.sub(claimFee));
            VoteToken.transfer(feeAddr, claimFee);
            payReferralProfit(msg.sender, user.reward5520.sub(claimFee));
            user.reward5520Claimed = user.reward5520Claimed.add(user.reward5520);
            emit Reward5520Claimed(msg.sender, user.reward5520);
            user.reward5520 = 0;
        }

        _update5520index(msg.sender);
    }

    /*---------------- ADMIN ----------------*/

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _tokenAddress: the address of the token to withdraw
     * @param _tokenAmount: the number of tokens to withdraw
     * @dev This function is only callable by admin.
     */
    function recoverWrongTokens(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        require(_tokenAddress != address(VoteToken), "Cannot be VOTE token");
        IERC20(_tokenAddress).transfer(address(msg.sender), _tokenAmount);
        emit AdminTokenRecovery(_tokenAddress, _tokenAmount);
    }

    function stopReward() external onlyOwner {
        endTimestamp = block.timestamp;
    }

    function updateRewardInflation(uint256 _initialRewardPerSecond, uint256 _rewardReduceRateByDay) external onlyOwner {
        initialRewardPerSecond = _initialRewardPerSecond;
        rewardReduceRateByDay = _rewardReduceRateByDay;
        emit RewardValueUpdated(_initialRewardPerSecond, _rewardReduceRateByDay);
    }

    function updateStartAndEndBlocks(uint256 _startTimestamp, uint256 _endTimestamp) external onlyOwner {
        require(block.timestamp < startTimestamp, "Pool has started");
        require(_startTimestamp < _endTimestamp, "New startTimestamp must be lower than new endBlock");
        require(block.timestamp < _startTimestamp, "New startTimestamp must be higher than current timestamp");

        startTimestamp = _startTimestamp;
        endTimestamp = _endTimestamp;

        // Set the lastRewardTimestamp as the startTimestamp
        lastRewardTimestamp = startTimestamp;

        emit NewStartAndEndBlocks(_startTimestamp, _endTimestamp);
    }

    function updateMaxLockPeriodAndIncentive(uint256 _lockIncentiveReduceRate, uint256 _multiplier) external onlyOwner {
        lockIncentiveReduceRate = _lockIncentiveReduceRate;
        maxLockIncentiveMultiplier = _multiplier;
        emit NewLockConfiguration(_lockIncentiveReduceRate, _multiplier);
    }

    function setFeeAddress(address _feeAddress) public onlyOwner {
        feeAddr = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    function setClaimFee(uint256 _claimFee) external onlyOwner {
        claimFee = _claimFee;
        emit SetClaimFee(_claimFee);
    }

    function setArtMarket(address _artMarket) external onlyOwner {
        artMarket = _artMarket;
        emit SetArtMarket(_artMarket);
    }
    
    function setPriceProvider(address _priceProvider) external onlyOwner {
        priceProvider = IPriceProvider(_priceProvider);
        emit SetPriceProvider(_priceProvider);
    }

    function setFeeManager(address _feeManager) external onlyOwner {
        feeManager = IFeeManager(_feeManager);
        emit SetFeeManager(_feeManager);
    }
    

    /*---------------- VIEW ----------------*/

    function rewardPerSecond() public view returns (uint256) {
        if (block.timestamp < startTimestamp)
            return 0;

        uint256 elapsedDays = (block.timestamp - startTimestamp) / (60 * 60 * 24);
        uint256 reward = initialRewardPerSecond;
        for (uint i = 0; i < elapsedDays; i++) {
            reward = reward.mul(rewardReduceRateByDay).div(MAX_BIPS).div(MAX_BIPS);
        }
        return reward;
    }

    function pendingReward(address _user) public view returns (uint256) {
        UserInfo memory user = userInfo[_user];
        if (block.timestamp > lastRewardTimestamp && getTotalRewardIndex() != 0) {
            uint256 multiplier = _getMultiplier(lastRewardTimestamp, block.timestamp);
            uint256 distrubutingReward = multiplier.mul(rewardPerSecond());
            uint256 adjustedTokenPerShare =
            accTokenPerShare.add(distrubutingReward.mul(PRECISION_FACTOR).div(getTotalRewardIndex()));
            return user.boostedAmount.mul(adjustedTokenPerShare).div(PRECISION_FACTOR).sub(user.rewardDebt);
        } else {
            return user.boostedAmount.mul(accTokenPerShare).div(PRECISION_FACTOR).sub(user.rewardDebt);
        }
    }

    function pendingVotingReward(address _nftAddress, uint256 _nftId) public view returns (uint256) {
        ArtInfo memory art = artInfo[_nftAddress][_nftId];
        if (block.timestamp > lastRewardTimestamp && getTotalRewardIndex() != 0) {
            uint256 multiplier = _getMultiplier(lastRewardTimestamp, block.timestamp);
            uint256 distrubutingReward = multiplier.mul(rewardPerSecond());
            uint256 adjustedTokenPerShare =
            accTokenPerShare.add(distrubutingReward.mul(PRECISION_FACTOR).div(getTotalRewardIndex()));
            return art.votingAmount.mul(adjustedTokenPerShare).div(PRECISION_FACTOR).sub(art.votingRewardDebt).mul(votingRewardBP).div(MAX_BIPS);
        } else {
            return art.votingAmount.mul(accTokenPerShare).div(PRECISION_FACTOR).sub(art.votingRewardDebt).mul(votingRewardBP).div(MAX_BIPS);
        }
    }

    function pendingHoldingReward(address _nftAddress, uint256 _nftId) public view returns (uint256) {
        ArtInfo memory art = artInfo[_nftAddress][_nftId];
        if (block.timestamp > lastRewardTimestamp && getTotalRewardIndex() != 0) {
            uint256 multiplier = _getMultiplier(lastRewardTimestamp, block.timestamp);
            uint256 distrubutingReward = multiplier.mul(rewardPerSecond());
            uint256 adjustedTokenPerShare =
            accTokenPerShare.add(distrubutingReward.mul(PRECISION_FACTOR).div(getTotalRewardIndex()));
            return art.value.mul(adjustedTokenPerShare).div(PRECISION_FACTOR).sub(art.holdingRewardDebt);
        } else {
            return art.value.mul(accTokenPerShare).div(PRECISION_FACTOR).sub(art.holdingRewardDebt);
        }
    }

    function pendingReward5520(address _user) public view returns (uint256) {
        UserInfo memory user = userInfo[_user];
        if (block.timestamp > lastRewardTimestamp && getTotalRewardIndex() != 0) {
            uint256 multiplier = _getMultiplier(lastRewardTimestamp, block.timestamp);
            uint256 distrubutingReward = multiplier.mul(rewardPerSecond());
            uint256 adjustedTokenPerShare =
            accTokenPerShare.add(distrubutingReward.mul(PRECISION_FACTOR).div(getTotalRewardIndex()));
            return get5520Index(_user).mul(adjustedTokenPerShare).div(PRECISION_FACTOR).sub(user.reward5520Debt);
        } else {
            return get5520Index(_user).mul(accTokenPerShare).div(PRECISION_FACTOR).sub(user.reward5520Debt);
        }
    }

    function getClaimableArtistReward(address _artist, address _nftAddress, uint256 _nftId) public view returns (uint256) {
        ArtInfo memory art = artInfo[_nftAddress][_nftId];
        ArtistRewardInfo memory artistReward = artistRewardInfo[_artist][_nftAddress][_nftId];
        uint256 reward = art.votingReward.add( pendingVotingReward(_nftAddress, _nftId) );
        
        IFeeManager.FeeRecipients[] memory creators = feeManager.getCreatorFee(_nftAddress, _nftId);
        uint256 creatorFeeBipsSum;
        for (uint i = 0; i < creators.length; i++) {
            creatorFeeBipsSum = creatorFeeBipsSum.add(creators[i].feeBips);
        }
        if (creators.length == 0) return 0;
        
        uint256 dividedReward = 0;
        for (uint i = 0; i < creators.length; i++) {
            if (_artist == creators[i].receiver) {
                if (creatorFeeBipsSum > 0)
                    dividedReward = reward.mul(creators[i].feeBips).div(creatorFeeBipsSum);
                else
                    dividedReward = reward.div(creators.length);
                break;
            }
        }
        return dividedReward.add( artistReward.artistReward );
    }

    function get5520Index(address _user) public view returns (uint256) {
        UserInfo memory user = userInfo[_user];

        uint256 holdingAmount = getHoldingAmount(_user);
        if (user.amount <= holdingAmount)
            return user.amount.mul(2);
        else
            return holdingAmount.mul(2);
    }

    function getHoldingAmount(address _user) public view returns (uint256 holdingAmount) {
        UserInfo memory user = userInfo[_user];
        ArtInfo memory art;
        for (uint i = 0; i < user.holdingNfts.length; i++) {
            art = artInfo[user.holdingNfts[i].nftAddress][user.holdingNfts[i].nftId];
            holdingAmount = holdingAmount.add(art.value);
        }
    }
 
    function getHoldingNfts(address _user) public view returns (
        Nft[] memory nftInfo,
        ArtInfo[] memory holdingsInfo,
        uint256[] memory pendings
    ) {
        UserInfo memory user = userInfo[_user];
        nftInfo = user.holdingNfts;
        holdingsInfo = new ArtInfo[](nftInfo.length);
        pendings = new uint256[](nftInfo.length);
        for (uint i = 0; i < nftInfo.length;) {
            ArtInfo memory art = artInfo[nftInfo[i].nftAddress][nftInfo[i].nftId];
            holdingsInfo[i].votingAmount = art.votingAmount;
            holdingsInfo[i].votingRewardDebt = art.votingRewardDebt;
            holdingsInfo[i].votingRewardClaimed = art.votingRewardClaimed;
            holdingsInfo[i].votingReward = art.votingReward;
            holdingsInfo[i].value = art.value;
            holdingsInfo[i].holdingRewardDebt = art.holdingRewardDebt;
            holdingsInfo[i].holdingRewardReceived = art.holdingRewardReceived;
            holdingsInfo[i].lastTradeTimestamp = art.lastTradeTimestamp;
            pendings[i] = pendingHoldingReward(nftInfo[i].nftAddress, nftInfo[i].nftId);
            i++;
        }
    }

    function getLockBoostedAmount(uint256 _amount, uint256 _lockPeriodInSec) public view returns (uint256) {
        uint256 subtraction = maxLockIncentiveMultiplier;
        uint256 lockPeriodInDay = _lockPeriodInSec / SECONDS_IN_DAY;
        for (uint256 i = 0; i < lockPeriodInDay; i++) {
            subtraction = subtraction.mul(lockIncentiveReduceRate).div(MAX_BIPS);
        }
        return _amount.mul(MAX_BIPS.add(maxLockIncentiveMultiplier).sub(subtraction)).div(MAX_BIPS);
    }
    
    function getTotalRewardIndex() public view returns (uint256) {
        return totalBoostedAmount
            .add(totalStakedTokenAmount.mul(votingRewardBP).div(MAX_BIPS))
            .add(totalHoldingAmount)
            .add(total5520Amount);
    }
    
    function getUserInfo(address _user) external view returns (
        uint256, uint256,
        Vote[] memory, Nft[] memory, ArtInfo[] memory, uint256[] memory
    ) {
        UserInfo memory user = userInfo[_user];
        (Nft[] memory nftInfo, ArtInfo[] memory holdingsInfo, uint256[] memory pendingsHoldingReward) = getHoldingNfts(_user);
        return (
            user.votes.length,
            nftInfo.length,
            user.votes,
            nftInfo,
            holdingsInfo,
            pendingsHoldingReward
        );
    }

    function _updatePool() internal {
        if (block.timestamp <= lastRewardTimestamp) {
            return;
        }
        if (getTotalRewardIndex() == 0) {
            lastRewardTimestamp = block.timestamp;
            return;
        }

        uint256 multiplier = _getMultiplier(lastRewardTimestamp, block.timestamp);
        uint256 distrubutingReward = multiplier.mul(rewardPerSecond());
        accTokenPerShare = accTokenPerShare.add(distrubutingReward.mul(PRECISION_FACTOR).div(getTotalRewardIndex()));
        lastRewardTimestamp = block.timestamp;
    }

    function _getMultiplier(uint256 _from, uint256 _to) internal view returns (uint256) {
        if (_to <= endTimestamp) {
            return _to.sub(_from);
        } else if (_from >= endTimestamp) {
            return 0;
        } else {
            return endTimestamp.sub(_from);
        }
    }

    function _voteArt(uint256 _amount, address _nftAddress, uint256 _nftId) internal {
        ArtInfo storage art = artInfo[_nftAddress][_nftId];
        if (_amount == 0) return;

        art.votingReward = art.votingReward.add(pendingVotingReward(_nftAddress, _nftId));
        art.votingAmount = art.votingAmount.add(_amount);
        art.votingRewardDebt = art.votingAmount.mul(accTokenPerShare).div(PRECISION_FACTOR);
        
        emit Voted(msg.sender, _amount, _nftAddress, _nftId);
    }

    function _unvoteArt(uint256 _amount, address _nftAddress, uint256 _nftId) internal {
        ArtInfo storage art = artInfo[_nftAddress][_nftId];
        require(art.votingAmount >= _amount, "The amount to unvote is bigger than voted amount");
        require(_amount >= 0, "The amount to unvote must be larger than 0");

        art.votingReward = art.votingReward.add(pendingVotingReward(_nftAddress, _nftId));
        art.votingAmount = art.votingAmount.sub(_amount);
        art.votingRewardDebt = art.votingAmount.mul(accTokenPerShare).div(PRECISION_FACTOR);
        
        emit Unvoted(msg.sender, _amount, _nftAddress, _nftId);
    }

    function _update5520index(address _user) internal {
        UserInfo storage user = userInfo[_user];
        uint256 reward5520Index = get5520Index(_user);
        total5520Amount = total5520Amount.add(reward5520Index).sub(user.reward5520Index);
        user.reward5520Index = reward5520Index;
        user.reward5520Debt = get5520Index(_user).mul(accTokenPerShare).div(PRECISION_FACTOR);
    }

    function _settle5520(address _user) internal {
        UserInfo storage user = userInfo[_user];
        uint256 reward5520 = pendingReward5520(_user);
        if (reward5520 > 0) {
            user.reward5520 = user.reward5520.add(reward5520);
        }
    }
}

