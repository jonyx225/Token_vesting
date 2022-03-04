pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../SwitchToken.sol";

contract PrivateVesting is Ownable, ReentrancyGuard {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    uint256 public constant WAVE_1 = 90 days;
    uint256 public constant WAVE_2 = 180 days;
    uint256 public constant WAVE_3 = 365 days;

    event TokensReleased(address beneficiary, uint256 amount);
    event TokenVestingRevoked(address beneficiary);
    event TokenClaimed(address beneficiary, uint256 amount);

    // Info of vesting plan.
    struct VestingInfo {
        uint256 start;
        uint256 amount;
        uint256 upfront;
    }

    // beneficiary of tokens after they are released
    mapping(address => VestingInfo) private _beneficiaries;

    bool private _revocable;

    mapping(address => uint256) private _released;
    mapping(address => bool) private _revoked;
    mapping(address => bool) private _upfrontReleased;

    IERC20 public Switch;

    constructor (bool revocable, IERC20 token) public {
        _revocable = revocable;
        Switch = token;
    }


    /**
     * @return the start time of the token vesting.
     */
    function start(address beneficiary) external view returns (uint256) {
        return _beneficiaries[beneficiary].start;
    }

    /**
     * @return true if the vesting is revocable.
     */
    function revocable() external view returns (bool) {
        return _revocable;
    }

    /**
     * @return the amount of the token released.
     */
    function released(address beneficiary) external view returns (uint256) {
        return _released[beneficiary];
    }

    /**
     * @return true if the token is revoked.
     */
    function revoked(address beneficiary) external view returns (bool) {
        return _revoked[beneficiary];
    }

    function addBeneficiary(address beneficiary, uint256 start, uint256 amount) external onlyOwner {
        require(beneficiary != address(0), "Vesting: beneficiary is the zero address");
        require(start.add(WAVE_3) > block.timestamp, "Vesting: final time is before current time");

        VestingInfo storage vesting = _beneficiaries[beneficiary];
        vesting.start = start;
        vesting.amount = amount;
        vesting.upfront = amount.mul(3).div(20);
    }

    /**
     * @notice Transfers vested tokens to beneficiary.
     */
    function release() external {
        address beneficiary = msg.sender;
        uint256 unreleased = _releasableAmount(beneficiary);

        require(unreleased > 0, "Vesting: no tokens are due");

        _released[beneficiary] = _released[beneficiary].add(unreleased);

        Switch.safeTransfer(beneficiary, unreleased);

        emit TokensReleased(beneficiary, unreleased);
    }

    /**
     * @notice Transfers upfront tokens to beneficiary.
     */
    function claim() external nonReentrant {
        require(!_upfrontReleased[msg.sender], "Vesting: token already claimed");

        uint256 upfront = _beneficiaries[msg.sender].upfront;
        Switch.safeTransfer(msg.sender, upfront);
        _upfrontReleased[msg.sender] = true;

        emit TokenClaimed(msg.sender, upfront);
    }

    /**
     * @notice Allows the owner to revoke the vesting. Tokens already vested
     * remain in the contract, the rest are returned to the owner.
     */
    function revoke(address beneficiary) external onlyOwner {
        require(_revocable, "Vesting: cannot revoke");
        require(!_revoked[beneficiary], "Vesting: token already revoked");

        uint256 balance = _beneficiaries[beneficiary].amount;

        uint256 unreleased = _releasableAmount(beneficiary);
        uint256 refund = balance.sub(unreleased);

        if (_upfrontReleased[beneficiary]) {
            refund = refund.sub(_beneficiaries[beneficiary].upfront);
        }

        _revoked[beneficiary] = true;

        Switch.safeTransfer(owner(), refund);

        emit TokenVestingRevoked(beneficiary);
    }

    /**
     * @notice Make contract non-revocable.
     */
    function finalizeContract() external onlyOwner {
        _revocable = false;
    }

    /**
     * @dev Calculates the amount that has already vested but hasn't been released yet.
     * @param beneficiary address
     */
    function _releasableAmount(address beneficiary) private view returns (uint256) {
        return _vestedAmount(beneficiary).sub(_released[beneficiary]);
    }

    /**
     * @dev Calculates the amount that has already vested.
     * @param beneficiary address
     */
    function _vestedAmount(address beneficiary) private view returns (uint256) {
        uint256 totalBalance = _beneficiaries[beneficiary].amount.sub(_beneficiaries[beneficiary].upfront);

        if (block.timestamp < _beneficiaries[beneficiary].start) {
            return 0;
        } else if (block.timestamp >= _beneficiaries[beneficiary].start.add(WAVE_1) && block.timestamp < _beneficiaries[beneficiary].start.add(WAVE_2)) {
            return totalBalance.div(5);
        } else if (block.timestamp >= _beneficiaries[beneficiary].start.add(WAVE_2) && block.timestamp < _beneficiaries[beneficiary].start.add(WAVE_3)) {
            return totalBalance.div(5).mul(2);
        } else if (block.timestamp >= _beneficiaries[beneficiary].start.add(WAVE_3) || _revoked[beneficiary]) {
            return totalBalance;
        } else {
            return 0;
        }
    }
}
