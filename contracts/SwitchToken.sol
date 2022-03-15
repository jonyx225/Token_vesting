/*
 .----------------.  .----------------.  .----------------.  .----------------.  .----------------.  .----------------.  .----------------.  .----------------.  .----------------.  .----------------.  .----------------.
| .--------------. || .--------------. || .--------------. || .--------------. || .--------------. || .--------------. || .--------------. || .--------------. || .--------------. || .--------------. || .--------------. |
| |   ______     | || |     ____     | || |   _____      | || |  ___  ____   | || |      __      | || |    _______   | || | _____  _____ | || |     _____    | || |  _________   | || |     ______   | || |  ____  ____  | |
| |  |_   __ \   | || |   .'    `.   | || |  |_   _|     | || | |_  ||_  _|  | || |     /  \     | || |   /  ___  |  | || ||_   _||_   _|| || |    |_   _|   | || | |  _   _  |  | || |   .' ___  |  | || | |_   ||   _| | |
| |    | |__) |  | || |  /  .--.  \  | || |    | |       | || |   | |_/ /    | || |    / /\ \    | || |  |  (__ \_|  | || |  | | /\ | |  | || |      | |     | || | |_/ | | \_|  | || |  / .'   \_|  | || |   | |__| |   | |
| |    |  ___/   | || |  | |    | |  | || |    | |   _   | || |   |  __'.    | || |   / ____ \   | || |   '.___`-.   | || |  | |/  \| |  | || |      | |     | || |     | |      | || |  | |         | || |   |  __  |   | |
| |   _| |_      | || |  \  `--'  /  | || |   _| |__/ |  | || |  _| |  \ \_  | || | _/ /    \ \_ | || |  |`\____) |  | || |  |   /\   |  | || |     _| |_    | || |    _| |_     | || |  \ `.___.'\  | || |  _| |  | |_  | |
| |  |_____|     | || |   `.____.'   | || |  |________|  | || | |____||____| | || ||____|  |____|| || |  |_______.'  | || |  |__/  \__|  | || |    |_____|   | || |   |_____|    | || |   `._____.'  | || | |____||____| | |
| |              | || |              | || |              | || |              | || |              | || |              | || |              | || |              | || |              | || |              | || |              | |
| '--------------' || '--------------' || '--------------' || '--------------' || '--------------' || '--------------' || '--------------' || '--------------' || '--------------' || '--------------' || '--------------' |
 '----------------'  '----------------'  '----------------'  '----------------'  '----------------'  '----------------'  '----------------'  '----------------'  '----------------'  '----------------'  '----------------'

description: Cross-chain liquidity built for traders.
website: https://polkaswitch.com/
telegram: https://t.me/polkaswitchANN
*/
// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

// SwitchToken with Governance and adds a cap to the supply of tokens..
contract Switch is IERC20, Ownable {
    using SafeMath for uint256;

    uint256 immutable private _cap = 1e26;

    /// @notice EIP-20 token name for this token
    string public constant name = "Polkaswitch";

    /// @notice EIP-20 token symbol for this token
    string public constant symbol = "SWITCH";

    /// @notice EIP-20 token decimals for this token
    uint8 public constant decimals = 18;

    /// @dev Official record of token balances for each account
    mapping (address => uint96) internal _balances;

    /// @notice Allowance amounts on behalf of others
    mapping (address => mapping (address => uint96)) private _allowances;

    /// @notice Total number of tokens in circulation
    uint96 private _totalSupply;

    /// @dev A record of each accounts delegate
    mapping (address => address) internal _delegates;

    /// @notice A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint96 votes;
    }

    /// @notice A record of votes checkpoints for each account, by index
    mapping (address => mapping (uint32 => Checkpoint)) public checkpoints;

    /// @notice The number of checkpoints for each account
    mapping (address => uint32) public numCheckpoints;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    /// @notice A record of states for signing / validating signatures
    mapping (address => uint) public nonces;

    /// @notice An event thats emitted when an account changes its delegate
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /// @notice An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(address indexed delegate, uint previousBalance, uint newBalance);

    /// @notice The standard EIP-20 transfer event
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @notice The standard EIP-20 approval event
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    uint256 public constant TAX_PERCENT = 5; // 5% tax on transfers
    uint256 public constant BURN_PERCENT = 2; // 2% of tax goes to burn
    uint256 public constant REFLECTION_PERCENT = 3; // 3% of tax goes to reflection

    uint256 public cooldownTime = 60; // 60 seconds cooldown for anti-bot
    mapping(address => uint256) private _lastTransferTime;

    uint96 private _totalSupplyForReflection;
    mapping(address => bool) private _excludedFromReflection;

    event TaxTaken(address from, address to, uint256 amount, uint256 tax);
    event Burned(uint256 amount);
    event Reflected(uint256 amount);

    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner.
    function mint(address _to, uint _rawAmount) external onlyOwner {
        uint96 _amount = safe96(_rawAmount, "SWITCH::mint: amount exceeds 96 bits");
        require(_totalSupply + _amount <= _cap, "SWITCH::mint: cap exceeded");
        _mint(_to, _amount);
    }

    /// @notice Destroys `_amount` token from `_account`. Must only be called by the owner.
    function burn(address _from, uint _rawAmount) external onlyOwner {
        uint96 _amount = safe96(_rawAmount, "SWITCH::burn: amount exceeds 96 bits");
        _burn(_from, _amount);
    }

    /**
     * @notice Get the number of tokens `spender` is approved to spend on behalf of `account`
     * @param account The address of the account holding the funds
     * @param spender The address of the account spending the funds
     * @return The number of tokens approved
     */
    function allowance(address account, address spender) external override view returns (uint) {
        return _allowances[account][spender];
    }

    /**
     * @notice Approve `spender` to transfer up to `amount` from `src`
     * @dev This will overwrite the approval amount for `spender`
     *  and is subject to issues noted [here](https://eips.ethereum.org/EIPS/eip-20#approve)
     * @param spender The address of the account which may transfer tokens
     * @param rawAmount The number of tokens that are approved (2^256-1 means infinite)
     * @return Whether or not the approval succeeded
     */
    function approve(address spender, uint rawAmount) external override returns (bool) {
        uint96 amount;
        if (rawAmount == uint(-1)) {
            amount = uint96(-1);
        } else {
            amount = safe96(rawAmount, "SWITCH::approve: amount exceeds 96 bits");
        }

        _allowances[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /**
     * @notice Transfer `amount` tokens from `msg.sender` to `dst`
     * @param dst The address of the destination account
     * @param rawAmount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transfer(address dst, uint rawAmount) external override returns (bool) {
        uint96 amount = safe96(rawAmount, "SWITCH::transfer: amount exceeds 96 bits");
        _transferTokens(msg.sender, dst, amount);
        return true;
    }

    /**
     * @notice Transfer `amount` tokens from `src` to `dst`
     * @param src The address of the source account
     * @param dst The address of the destination account
     * @param rawAmount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transferFrom(address src, address dst, uint rawAmount) external override returns (bool) {
        address spender = msg.sender;
        uint96 spenderAllowance = _allowances[src][spender];
        uint96 amount = safe96(rawAmount, "SWITCH::transferFrom: amount exceeds 96 bits");

        if (spender != src && spenderAllowance != uint96(-1)) {
            uint96 newAllowance = sub96(spenderAllowance, amount, "SWITCH::transferFrom: transfer amount exceeds spender allowance");
            _allowances[src][spender] = newAllowance;

            emit Approval(src, spender, newAllowance);
        }

        _transferTokens(src, dst, amount);
        return true;
    }


    /**
     * @notice Get the number of tokens held by the `account`
     * @param account The address of the account to get the balance of
     * @return The number of tokens held
     */
    function balanceOf(address account) external override view returns (uint) {
        if (_excludedFromReflection[account]) {
            return _balances[account];
        }
        return uint256(_balances[account]) * uint256(_totalSupply) / uint256(_totalSupplyForReflection);
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() external view override returns (uint) {
        return _totalSupply;
    }

    /**
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegator The address to get delegatee for
     */
    function delegates(address delegator)
        external
        view
    returns (address)
    {
        return _delegates[delegator];
    }

    /**
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegatee The address to delegate votes to
     */
    function delegate(address delegatee) external {
        emit DelegateChanged(msg.sender, address(0), delegatee);
        return _delegate(msg.sender, delegatee);
    }

    /**
     * @notice Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(
        address delegatee,
        uint nonce,
        uint expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
    {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name)),
                getChainId(),
                address(this)
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
                DELEGATION_TYPEHASH,
                delegatee,
                nonce,
                expiry
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "SWITCH::delegateBySig: invalid signature");
        require(nonce == nonces[signatory]++, "SWITCH::delegateBySig: invalid nonce");
        require(block.timestamp <= expiry, "SWITCH::delegateBySig: signature expired");
        return _delegate(signatory, delegatee);
    }

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account)
        external
        view
    returns (uint256)
    {
        uint32 nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @notice Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint blockNumber)
        external
        view
    returns (uint256)
    {
        require(blockNumber < block.number, "SWITCH::getPriorVotes: not yet determined");

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    function _delegate(address delegator, address delegatee)
        internal
    {
        address currentDelegate = _delegates[delegator];
        uint96 delegatorBalance = _balances[delegator];
        _delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _transferTokens(address src, address dst, uint96 amount) internal {
        require(src != address(0), "SWITCH::_transferTokens: cannot transfer from the zero address");
        require(dst != address(0), "SWITCH::_transferTokens: cannot transfer to the zero address");

        // Anti-bot: Check cooldown
        require(block.timestamp >= _lastTransferTime[src] + cooldownTime, "Anti-bot: Transfer cooldown active");
        _lastTransferTime[src] = block.timestamp;
        _lastTransferTime[dst] = block.timestamp; // Also set for recipient to prevent immediate resell

        uint256 u_amount = uint256(amount);
        uint256 u_taxAmount = u_amount * TAX_PERCENT / 100;
        uint256 u_burnAmount = u_taxAmount * BURN_PERCENT / TAX_PERCENT;
        uint256 u_reflectionAmount = u_taxAmount * REFLECTION_PERCENT / TAX_PERCENT;
        uint256 u_transferAmount = u_amount - u_taxAmount;

        uint96 taxAmount = safe96(u_taxAmount, "SWITCH::taxAmount exceeds 96 bits");
        uint96 burnAmount = safe96(u_burnAmount, "SWITCH::burnAmount exceeds 96 bits");
        uint96 reflectionAmount = safe96(u_reflectionAmount, "SWITCH::reflectionAmount exceeds 96 bits");
        uint96 transferAmount = safe96(u_transferAmount, "SWITCH::transferAmount exceeds 96 bits");

        // Burn
        _burn(src, burnAmount);
        emit Burned(u_burnAmount);

        // Reflection
        _totalSupplyForReflection = sub96(_totalSupplyForReflection, reflectionAmount, "SWITCH::reflection underflow");
        emit Reflected(u_reflectionAmount);

        // Transfer the rest
        _balances[src] = sub96(_balances[src], transferAmount, "SWITCH::_transferTokens: transfer amount exceeds balance");
        _balances[dst] = add96(_balances[dst], transferAmount, "SWITCH::_transferTokens: transfer amount overflows");
        emit Transfer(src, dst, transferAmount);

        _moveDelegates(_delegates[src], _delegates[dst], transferAmount);

        emit TaxTaken(src, dst, u_amount, u_taxAmount);
    }

    function _moveDelegates(address srcRep, address dstRep, uint96 amount) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                // decrease old representative
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint96 srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint96 srcRepNew = sub96(srcRepOld, amount, "SWITCH::_moveVotes: vote amount underflows");
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                // increase new representative
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint96 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint96 dstRepNew = add96(dstRepOld, amount, "SWITCH::_moveVotes: vote amount overflows");
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(
        address delegatee,
        uint32 nCheckpoints,
        uint96 oldVotes,
        uint96 newVotes
    )
        internal
    {
        uint32 blockNumber = safe32(block.number, "SWITCH::_writeCheckpoint: block number exceeds 32 bits");

        if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function safe32(uint n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2**32, errorMessage);
        return uint32(n);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     */
    function _mint(address _account, uint96 _amount) internal {
        require(_account != address(0), "SWITCH: mint to the zero address");

        _totalSupply = add96(_totalSupply, _amount, "SWITCH::mint: totalSupply amount overflows");
        _balances[_account] = add96(_balances[_account], _amount, "SWITCH::mint: balance amount overflows");
        _moveDelegates(address(0), _delegates[_account], _amount);
        emit Transfer(address(0), _account, _amount);

        if (_totalSupplyForReflection == 0) {
            _totalSupplyForReflection = _totalSupply;
            _excludedFromReflection[address(0)] = true;
            _excludedFromReflection[owner()] = true;
        }
    }

    /** @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address _account, uint96 _amount) internal {
        require(_account != address(0), "SWITCH: burn from the zero address");

        _balances[_account] = sub96(_balances[_account], _amount, "SWITCH::burn: amount exceeds balance");
        _totalSupply = sub96(_totalSupply, _amount, "SWITCH::burn: amount exceeds total supply");
        _moveDelegates(_delegates[_account], address(0), _amount);
        emit Transfer(_account, address(0), _amount);
    }


    function safe96(uint n, string memory errorMessage) internal pure returns (uint96) {
        require(n < 2**96, errorMessage);
        return uint96(n);
    }

    function add96(uint96 a, uint96 b, string memory errorMessage) internal pure returns (uint96) {
        uint96 c = a + b;
        require(c >= a, errorMessage);
        return c;
    }

    function sub96(uint96 a, uint96 b, string memory errorMessage) internal pure returns (uint96) {
        require(b <= a, errorMessage);
        return a - b;
    }

    function getChainId() internal view returns (uint) {
        uint256 chainId;
        assembly { chainId := chainid() }
        return chainId;
    }

    /**
     * @dev Owner can update cooldown time for anti-bot.
     */
    function setCooldownTime(uint256 newCooldown) external onlyOwner {
        cooldownTime = newCooldown;
    }

    /**
     * @dev Owner can exclude/include addresses from reflection.
     */
    function setExcludedFromReflection(address account, bool excluded) external onlyOwner {
        _excludedFromReflection[account] = excluded;
    }
}