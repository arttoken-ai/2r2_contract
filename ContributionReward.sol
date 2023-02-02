/**
 *Submitted for verification at Etherscan.io on 2021-09-25
*/

// File: @openzeppelin/contracts/utils/Context.sol

pragma solidity >=0.6.0 <0.8.0;

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with GSN meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

// File: @openzeppelin/contracts/utils/Pausable.sol

pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract Pausable is Context {
    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    bool private _paused;

    /**
     * @dev Initializes the contract in unpaused state.
     */
    constructor () internal {
        _paused = false;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        require(!paused(), "Pausable: paused");
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        require(paused(), "Pausable: not paused");
        _;
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}




// File contracts/libraries/SafeMath.sol

pragma solidity ^0.7.5;


library SafeMath {

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }

    function sqrrt(uint256 a) internal pure returns (uint c) {
        if (a > 3) {
            c = a;
            uint b = add( div( a, 2), 1 );
            while (b < c) {
                c = b;
                b = div( add( div( a, b ), b), 2 );
            }
        } else if (a != 0) {
            c = 1;
        }
    }
}


// File contracts/libraries/Address.sol

pragma solidity ^0.7.5;


library Address {

    function isContract(address account) internal view returns (bool) {

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
        return size > 0;
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
      return functionCall(target, data, "Address: low-level call failed");
    }

    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        return _functionCallWithValue(target, data, 0, errorMessage);
    }

    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: value }(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _functionCallWithValue(address target, bytes memory data, uint256 weiValue, string memory errorMessage) private returns (bytes memory) {
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: weiValue }(data);
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }

    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    function functionStaticCall(address target, bytes memory data, string memory errorMessage) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    function functionDelegateCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) private pure returns(bytes memory) {
        if (success) {
            return returndata;
        } else {
            if (returndata.length > 0) {

                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }

    function addressToString(address _address) internal pure returns(string memory) {
        bytes32 _bytes = bytes32(uint256(_address));
        bytes memory HEX = "0123456789abcdef";
        bytes memory _addr = new bytes(42);

        _addr[0] = '0';
        _addr[1] = 'x';

        for(uint256 i = 0; i < 20; i++) {
            _addr[2+i*2] = HEX[uint8(_bytes[i + 12] >> 4)];
            _addr[3+i*2] = HEX[uint8(_bytes[i + 12] & 0x0f)];
        }

        return string(_addr);

    }
}


// File contracts/interfaces/IERC20.sol

pragma solidity ^0.7.5;

interface IERC20 {
    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed owner, address indexed spender, uint256 value);
}


// File contracts/libraries/SafeERC20.sol

pragma solidity ^0.7.5;


library SafeERC20 {
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    function safeApprove(IERC20 token, address spender, uint256 value) internal {

        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(value);
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(value, "SafeERC20: decreased allowance below zero");
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function _callOptionalReturn(IERC20 token, bytes memory data) private {

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

interface IERC721 {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function balanceOf(address owner) external view returns (uint256 balance);
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;
    function approve(address to, uint256 tokenId) external;
    function setApprovalForAll(address operator, bool _approved) external;
    function getApproved(uint256 tokenId) external view returns (address operator);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}


// File contracts/libraries/FullMath.sol

pragma solidity ^0.7.5;

library FullMath {
    function fullMul(uint256 x, uint256 y) private pure returns (uint256 l, uint256 h) {
        uint256 mm = mulmod(x, y, uint256(-1));
        l = x * y;
        h = mm - l;
        if (mm < l) h -= 1;
    }

    function fullDiv(
        uint256 l,
        uint256 h,
        uint256 d
    ) private pure returns (uint256) {
        uint256 pow2 = d & -d;
        d /= pow2;
        l /= pow2;
        l += h * ((-pow2) / pow2 + 1);
        uint256 r = 1;
        r *= 2 - d * r;
        r *= 2 - d * r;
        r *= 2 - d * r;
        r *= 2 - d * r;
        r *= 2 - d * r;
        r *= 2 - d * r;
        r *= 2 - d * r;
        r *= 2 - d * r;
        return l * r;
    }

    function mulDiv(
        uint256 x,
        uint256 y,
        uint256 d
    ) internal pure returns (uint256) {
        (uint256 l, uint256 h) = fullMul(x, y);
        uint256 mm = mulmod(x, y, d);
        if (mm > l) h -= 1;
        l -= mm;
        require(h < d, 'FullMath::mulDiv: overflow');
        return fullDiv(l, h, d);
    }
}


// File contracts/libraries/FixedPoint.sol

pragma solidity ^0.7.5;

library Babylonian {

    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;

        uint256 xx = x;
        uint256 r = 1;
        if (xx >= 0x100000000000000000000000000000000) {
            xx >>= 128;
            r <<= 64;
        }
        if (xx >= 0x10000000000000000) {
            xx >>= 64;
            r <<= 32;
        }
        if (xx >= 0x100000000) {
            xx >>= 32;
            r <<= 16;
        }
        if (xx >= 0x10000) {
            xx >>= 16;
            r <<= 8;
        }
        if (xx >= 0x100) {
            xx >>= 8;
            r <<= 4;
        }
        if (xx >= 0x10) {
            xx >>= 4;
            r <<= 2;
        }
        if (xx >= 0x8) {
            r <<= 1;
        }
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1; // Seven iterations should be enough
        uint256 r1 = x / r;
        return (r < r1 ? r : r1);
    }
}

library BitMath {

    function mostSignificantBit(uint256 x) internal pure returns (uint8 r) {
        require(x > 0, 'BitMath::mostSignificantBit: zero');

        if (x >= 0x100000000000000000000000000000000) {
            x >>= 128;
            r += 128;
        }
        if (x >= 0x10000000000000000) {
            x >>= 64;
            r += 64;
        }
        if (x >= 0x100000000) {
            x >>= 32;
            r += 32;
        }
        if (x >= 0x10000) {
            x >>= 16;
            r += 16;
        }
        if (x >= 0x100) {
            x >>= 8;
            r += 8;
        }
        if (x >= 0x10) {
            x >>= 4;
            r += 4;
        }
        if (x >= 0x4) {
            x >>= 2;
            r += 2;
        }
        if (x >= 0x2) r += 1;
    }
}


library FixedPoint {

    struct uq112x112 {
        uint224 _x;
    }

    struct uq144x112 {
        uint256 _x;
    }

    uint8 private constant RESOLUTION = 112;
    uint256 private constant Q112 = 0x10000000000000000000000000000;
    uint256 private constant Q224 = 0x100000000000000000000000000000000000000000000000000000000;
    uint256 private constant LOWER_MASK = 0xffffffffffffffffffffffffffff; // decimal of UQ*x112 (lower 112 bits)

    function decode(uq112x112 memory self) internal pure returns (uint112) {
        return uint112(self._x >> RESOLUTION);
    }

    function decode112with18(uq112x112 memory self) internal pure returns (uint) {

        return uint(self._x) / 5192296858534827;
    }

    function fraction(uint256 numerator, uint256 denominator) internal pure returns (uq112x112 memory) {
        require(denominator > 0, 'FixedPoint::fraction: division by zero');
        if (numerator == 0) return FixedPoint.uq112x112(0);

        if (numerator <= uint144(-1)) {
            uint256 result = (numerator << RESOLUTION) / denominator;
            require(result <= uint224(-1), 'FixedPoint::fraction: overflow');
            return uq112x112(uint224(result));
        } else {
            uint256 result = FullMath.mulDiv(numerator, Q112, denominator);
            require(result <= uint224(-1), 'FixedPoint::fraction: overflow');
            return uq112x112(uint224(result));
        }
    }
    
    // square root of a UQ112x112
    // lossy between 0/1 and 40 bits
    function sqrt(uq112x112 memory self) internal pure returns (uq112x112 memory) {
        if (self._x <= uint144(-1)) {
            return uq112x112(uint224(Babylonian.sqrt(uint256(self._x) << 112)));
        }

        uint8 safeShiftBits = 255 - BitMath.mostSignificantBit(self._x);
        safeShiftBits -= safeShiftBits % 2;
        return uq112x112(uint224(Babylonian.sqrt(uint256(self._x) << safeShiftBits) << ((112 - safeShiftBits) / 2)));
    }
}


// File contracts/types/Ownable.sol

pragma solidity ^0.7.5;

contract Ownable {

    address payable public policy;

    constructor () {
        policy = msg.sender;
    }

    modifier onlyPolicy() {
        require( policy == msg.sender, "Ownable: caller is not the policy" );
        _;
    }
    
    function transferManagment(address payable _newPolicy) external onlyPolicy() {
        require( _newPolicy != address(0) );
        policy = _newPolicy;
    }
}

interface IToolBox {
    function wethAddress() external view returns (address);
    function usdcAddress() external view returns (address);
    //function convertToTargetValueFromPool(IUniswapV3Pool pool, uint256 sourceTokenAmount, address targetAddress) external view returns (uint256);
    function getTokenValueInEth(address token, uint256 amount, uint24 fee) external view returns (uint256);
    function getTokenValueInUsdc(address token, uint256 amount, uint24 fee) external view returns (uint256);
    function getEthValueInUsdc(uint256 amount, uint24 fee) external view returns (uint256);
}

interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint wad) external;
    function approve(address guy, uint wad) external returns (bool);
    function transfer(address dst, uint wad) external returns (bool);
    function transferFrom(address src, address dst, uint wad) external returns (bool);
}

pragma solidity >=0.7.5;
pragma abicoder v2;
interface INonfungiblePositionManager
{
    event IncreaseLiquidity(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    event DecreaseLiquidity(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    event Collect(uint256 indexed tokenId, address recipient, uint256 amount0, uint256 amount1);

    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );

    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }
    function mint(MintParams calldata params)
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }
    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);
    function burn(uint256 tokenId) external payable;
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

contract ReferralOperator is Ownable {
    IEarningReferral public earningReferral;
    uint public referralCommissionRate = 300;
    uint public referreeBonusRate = 1000;

    function setReferral(
        IEarningReferral _earningReferral,
        uint _referralCommissionRate,
        uint _referreeBonusRate
    ) external onlyPolicy {
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

pragma solidity ^0.7.5;

contract ContributionReward is Ownable, Pausable, ReferralOperator {
    using FixedPoint for *;
    using SafeERC20 for IERC20;
    using SafeMath for uint;

    event NewContribution( address user, uint contributionAmount, uint rewardAmount, uint expireTimestamp );
    event RewardClaimed( address user, uint amount, uint pendingAmount );
        
    IERC20 public rewardToken;
    IWETH9 constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IToolBox public toolbox;
    INonfungiblePositionManager position;
    uint256 positionTokenId;

    uint public totalContribution;
    uint public totalRewardGiven;
    Terms public terms;
    uint public pendingReward;
    mapping( address => Contribution ) public contributionInfo;

    uint256 public feeBips;
    uint256 constant public MAX_BIPS = 10000;

    // whitelists
    mapping(address => bool) public whiteList;
    bool public isWhitelist = false;
    
    /* ======== STRUCTS ======== */

    struct Terms {
        uint vestingTerm; // in seconds
        uint cliffTerm; // in seconds
        uint minDiscountRate; // reward value for contribution in %. i.e. 500 = 5%
        uint maxDiscountRate; // reward value for contribution in %. i.e. 500 = 5%
        uint maxReward; // in amount
        uint startTimestamp; // Reward start timestamp
        uint endTimestamp; //  Reward end timestamp
        uint feeBips; // Fee Bips in 10000 (3000 = 30%)
    }

    // Info for contributor
    struct Contribution {
        uint totalContributed;
        uint totalReward;
        uint claimed;   // claimed in this vesting. Total claimed is totalReward - vestingAmount + claimed
        uint vestingAmount;
        uint vestingPeriod;
        uint lastContributionTimestamp;
    }

    /* ======== POLICY FUNCTIONS ======== */
    
    function initialize(
        address _rewardToken,
        address _toolbox,
        address _position,
        uint256 _positionTokenId,
        uint _vestingTerm,
        uint _cliffTerm,
        uint _maxReward,
        uint _minDiscountRate,
        uint _maxDiscountRate,
        uint _startTimestamp,
        uint _endTimestamp,
        uint _feeBips
    ) external onlyPolicy {
        position = INonfungiblePositionManager(_position);
        positionTokenId = _positionTokenId;

        require( _rewardToken != address(0) );
        rewardToken = IERC20( _rewardToken );
        rewardToken.approve(address(position), 10000000000000000000000000000000);

        toolbox = IToolBox(_toolbox);
        
        terms = Terms ({
            vestingTerm: _vestingTerm,
            cliffTerm: _cliffTerm,
            maxReward: _maxReward,
            minDiscountRate: _minDiscountRate,
            maxDiscountRate: _maxDiscountRate,
            startTimestamp: _startTimestamp,
            endTimestamp: _endTimestamp,
            feeBips: _feeBips
        });
    }

    function setWhitelist(address[] memory _whiteList) external onlyPolicy {
        for (uint16 i = 0; i < _whiteList.length; i++) {
        whiteList[_whiteList[i]] = true;
        }
        isWhitelist = (_whiteList.length > 0);
    }

    function collectPosition() external onlyPolicy {
        IERC721(address(position)).transferFrom(address(this), msg.sender, positionTokenId);
    }

    function pause() external onlyPolicy() {
        _pause();
    }

    function unpause() external onlyPolicy() {
        _unpause();
    }

    function close() external onlyPolicy {
        require(block.timestamp > terms.endTimestamp, "Cannot do this while deposit period");
        uint256 amountToWithdraw = IERC20(rewardToken).balanceOf(address(this)) - totalRewardGiven;
        IERC20(rewardToken).transfer(address(msg.sender), amountToWithdraw);
        policy.transfer(address(this).balance);
    }

    /* ======== USER FUNCTIONS ======== */
    
    /**
     *  @notice contribute to add liquidity
     *  @return uint
     */
    function contribute(address _referrer) payable external whenNotPaused returns (uint) {
        require(block.timestamp > terms.startTimestamp &&
                block.timestamp < terms.endTimestamp, "Not open time");

        if (isWhitelist)
            require (whiteList[msg.sender], "The user is not included to white list");

        uint256 fee = msg.value.mul(terms.feeBips).div(MAX_BIPS);
        uint256 wethAmount = msg.value.sub(fee);
        uint256 payoutPriceInEth = toolbox.getTokenValueInEth(address(rewardToken), 10 ** 8, 3000);
        uint256 payoutAmountForLiquidity = wethAmount * 10 ** 8 / payoutPriceInEth;

        uint newPayout = payoutForPrinciple(msg.value);
        require( newPayout + totalRewardGiven <= terms.maxReward, "Max capacity reached" );

        // total debt is increased
        pendingReward = pendingReward.add( newPayout );

        // settle reward vested so far
        claim();

        // contributor info is stored
        contributionInfo[msg.sender] = Contribution({
            totalContributed: contributionInfo[msg.sender].totalContributed.add( msg.value ),
            totalReward: contributionInfo[msg.sender].totalReward.add( newPayout ),
            claimed: 0,
            vestingAmount: newPayout
                .add( contributionInfo[msg.sender].vestingAmount )
                .sub( contributionInfo[msg.sender].claimed ),
            vestingPeriod: terms.vestingTerm,
            lastContributionTimestamp: block.timestamp
        });

        // create lp
        INonfungiblePositionManager.IncreaseLiquidityParams memory addLiquidityParams =
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: positionTokenId,
                amount0Desired: wethAmount,
                amount1Desired: payoutAmountForLiquidity * 11 / 10,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });
        position.increaseLiquidity{value: wethAmount}(addLiquidityParams);
        
        emit NewContribution(msg.sender, msg.value, newPayout, block.timestamp.add( terms.cliffTerm ).add( terms.vestingTerm ));

        totalContribution = totalContribution.add(msg.value);
        totalRewardGiven = totalRewardGiven.add(newPayout);

        recordReferral(msg.sender, _referrer);

        return newPayout;
    }
    
    /**
     *  @notice claim reward for user
     *  @return uint
     */
    function claim() public returns (uint) {
        Contribution memory info = contributionInfo[msg.sender];
        uint percentVested = percentVestedFor(msg.sender); // (seconds since last interaction / vesting term remaining)

        if (percentVested == 0)
            return 0;
        
        // calculate payout vested
        uint payout = info.vestingAmount.mul( percentVested ).div( 10000 ).sub(info.claimed);

        // store updated deposit info
        contributionInfo[msg.sender] = Contribution({
            totalContributed: info.totalContributed,
            totalReward: info.totalReward,
            claimed: info.claimed.add( payout ),
            vestingAmount: info.vestingAmount,
            vestingPeriod: info.vestingPeriod,
            lastContributionTimestamp: info.lastContributionTimestamp
        });

        emit RewardClaimed( msg.sender, payout, info.vestingAmount.sub( contributionInfo[msg.sender].claimed ) );
        rewardToken.transfer( msg.sender, payout );
        pendingReward = pendingReward.sub(payout);
        payReferralProfit(msg.sender, payout);
        return payout;
    }

    /**
     *  @notice calculate reward value rate for contribution value
     *  @return discountRate_ uint
     */
    function discountRate() public view returns (uint) {
        return terms.minDiscountRate + ((terms.maxDiscountRate - terms.minDiscountRate) * (10000 - timeRatio())) / 10000;
    }

    /**
     *  @notice calculate time ratio
     *  @return uint
     */
    function timeRatio() public view returns ( uint ) {
        if (block.timestamp < terms.startTimestamp || terms.endTimestamp == 0)
            return 0;
        if (block.timestamp > terms.endTimestamp && terms.endTimestamp > 0)
            return 10000;
        return 10000 * (block.timestamp - terms.startTimestamp) / (terms.endTimestamp - terms.startTimestamp);
    }

    /**
    *   @notice returns payout token valuation of priciple
    *   @param _amount uint
    *   @return value_ uint
     */
    function payoutForPrinciple( uint _amount ) public view returns ( uint value_ ) {
        // convert amount to match payout token decimals
        uint256 payoutPriceInEth = toolbox.getTokenValueInEth(address(rewardToken), 10 ** 8, 3000);
        uint256 payoutAmountForEth = _amount * 10 ** 8 / payoutPriceInEth;
        value_ = payoutAmountForEth.mul(10000).div(10000 - discountRate());
    }

    /**
     *  @notice calculate how far into vesting a contributor is
     *  @param _contributor address
     *  @return uint
     */
    function percentVestedFor( address _contributor ) public view returns (uint) {
        Contribution memory info = contributionInfo[ _contributor ];
        if (block.timestamp <= info.lastContributionTimestamp + terms.cliffTerm) {
            return 0;
        }
        uint secondsSinceLast = block.timestamp.sub(info.lastContributionTimestamp).sub(terms.cliffTerm);

        if ( info.vestingPeriod > 0 ) {
            return secondsSinceLast.mul( 10000 ).div( info.vestingPeriod );
        } else {
            return 0;
        }
    }

    /**
     *  @notice calculate amount of payout token available for claim by contributor
     *  @param _contributor address
     *  @return pendingPayout_ uint
     */
    function pendingPayoutFor( address _contributor ) external view returns ( uint pendingPayout_ ) {
        uint percentVested = percentVestedFor( _contributor );
        Contribution memory info = contributionInfo[ _contributor ];

        if ( percentVested >= 10000 ) {
            pendingPayout_ = info.vestingAmount.sub( info.claimed );
        } else {
            pendingPayout_ = info.vestingAmount.mul( percentVested ).div( 10000 ).sub( info.claimed );
        }
    }
}

