// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


interface IPriceFeed {
    function queryRate(address sourceTokenAddress, address destTokenAddress) external view returns (uint256 rate, uint256 precision);
}

interface IEIP20Permit {
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
}

contract Converter is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private manualRate;
    uint256 public minConvertAmount;
    address public InitialHolder;

    bool public usePriceFeeds;
    IPriceFeed public priceFeed;

    IERC20 public immutable gnbuToken;
    IERC20 public immutable receiveToken;

    event Rescue(address to, uint256 amount);
    event RescueToken(address indexed to, address indexed token, uint256 amount);
    event ToggleUsePriceFeeds(bool indexed usePriceFeeds);

    event Convert(address to, uint256 purchaseAmount, uint256 receiveAmount, uint256 time);
    event SetManualRate(uint256 newRate);
    event SetNewMinConvertAmount(uint256 newMinConvertAmount);
    event UpdatePriceFeed(address newPriceFeed);

  
    constructor(address _gnbuToken, address _receiveToken, address _InitialHolder) {
        require(Address.isContract(_gnbuToken), 'Purchase token should be a contract');
        require(Address.isContract(_receiveToken), 'Receive token should be a contract');

        gnbuToken = IERC20(_gnbuToken);
        receiveToken = IERC20(_receiveToken);
        
        manualRate = 1 ether;
        minConvertAmount = 1 ether;

        InitialHolder = _InitialHolder;
        
    }

    /**
     * @notice Convertion from purchaseToken to receiveToken
     * @param amount amount of purchaseToken to convert
     * @dev This method converts purchaseToken to ReceiveToken using rates from PriceFeed. 
     * Amount should be greater than minimal amount to Convert. "Purchase" tokens are being transfered to Contract.
     * "Receive" tokens are being transfered to caller.
     */
    function convert(uint256 amount) external whenNotPaused nonReentrant {
        require(amount >= minConvertAmount, "Amount should be more then min amount");

        uint256 receiveAmount = getEquivalentAmount(amount);
        gnbuToken.safeTransferFrom(msg.sender, InitialHolder, amount);
        receiveToken.safeTransfer(msg.sender, receiveAmount);
        
        emit Convert(msg.sender, amount, receiveAmount, block.timestamp);
    }

    /**
     * @notice Convertion from purchaseToken to receiveToken
     * @param amount amount of purchaseToken to convert
     * @param permitDeadline deadline of Permit operation
     * @param v the recovery id
     * @param r outputs of an ECDSA signature
     * @param s outputs of an ECDSA signature
     * @dev This method converts purchaseToken to ReceiveToken using rates from PriceFeed. 
     * Amount should be greater than minimal amount to Convert. "Purchase" tokens are being transfered to Contract.
     * "Receive" tokens are being transfered to caller.
     */
    function convertWithPermit(uint256 amount, uint256 permitDeadline, uint8 v, bytes32 r, bytes32 s) external whenNotPaused nonReentrant {
        require(amount >= minConvertAmount, "Amount should be more then min amount");

        uint256 receiveAmount = getEquivalentAmount(amount);
        IEIP20Permit(address(gnbuToken)).permit(msg.sender,address(this), amount, permitDeadline, v, r, s);
        
        gnbuToken.safeTransferFrom(msg.sender, InitialHolder, amount);
        receiveToken.safeTransfer(msg.sender, receiveAmount);
        
        emit Convert(msg.sender, amount, receiveAmount, block.timestamp);
    }

    /**
     * @notice View method for getting equivalent amount of ReceiveTokens in PurchaseTokens
     * @param amount amount of purchaseToken
     * @dev This method gets amount of ReceiveTokens equivalent to PurchaseToken amount using PriceFeed.
     */
    function getEquivalentAmount(uint256 amount) public view returns (uint256) {
        if (!usePriceFeeds) return amount * manualRate / 1 ether;

        (uint256 rate, uint256 precision) = priceFeed.queryRate(address(gnbuToken), address(receiveToken));
        return amount * rate / precision;
    }

    /**
     * @notice View method for getting reserve of receiveToken
     * @dev This method is getter for amount of ReceiveTokens that are stored on current Contract.
     */
    function receiveTokenSupply() public view returns(uint256) {
        return receiveToken.balanceOf(address(this));
    }

    /**
     * @notice Sets rate of PurchaseToken/ReceiveToken manually
     * @param newRate new rate of PurchaseToken/ReceiveToken
     * @dev This method sets Rate for convertion PurchaseTokens to RecieveTokens.
     * Can be executed only by owner.
     */
    function setManualRate(uint256 newRate) external onlyOwner {
        require(newRate > 0, "Rate should be more then 0");
        manualRate = newRate;
        emit SetManualRate(newRate);
    }
     function setInitialHolder(address _InitialHolder) external onlyOwner {
        InitialHolder = _InitialHolder;
 }

    /**
     * @notice Sets minimum amount for convertion
     * @param newMinConvertAmount new minimum amount for convertion
     * @dev This method sets new minimum amount for convertion PurchaseTokens to RecieveTokens.
     * Can be executed only by owner.
     */
    function setMinConvertAmount(uint256 newMinConvertAmount) external onlyOwner {
        minConvertAmount = newMinConvertAmount;
        emit SetNewMinConvertAmount(newMinConvertAmount);
    }

    /**
     * @notice Updates PriceFeed
     * @param newPriceFeed new PriceFeed`s address
     * @dev This method sets new PriceFeed for rate of PurchaseToken/ReceiveToken
     * Can be executed only by owner.
     */
    function updatePriceFeed(address newPriceFeed) external onlyOwner {
        require(Address.isContract(newPriceFeed), 'Purchase token should be a contract');
        priceFeed = IPriceFeed(newPriceFeed);
        emit UpdatePriceFeed(newPriceFeed);
    }

    /**
     * @notice Enables/Disables convertion using PriceFeed 
     * @param isEnabled boolean of "PriceFeed-mode"
     * @dev This method enables/disables PriceFeed usage in tokens convertion
     * Can be executed only by owner.
     */
    function updateUsePriceFeeds(bool isEnabled) external onlyOwner {
        require(!isEnabled || isEnabled && Address.isContract(address(priceFeed)), 'Price feed not set');
        usePriceFeeds = isEnabled;
        emit ToggleUsePriceFeeds(usePriceFeeds);
    }

    /**
     * @notice Sets Contract as paused
     * @param isPaused Pausable mode
     */
    function setPaused(bool isPaused) external onlyOwner {
        if (isPaused) _pause();
        else _unpause();
    }

    /**
     * @notice Rescues ERC20 tokens from Contract
     * @param to address to withdraw tokens
     * @param token address of ERC20 token
     * @param amount amount of ERC20 token
     * @dev This method rescues particular amount of ERC20 token from contract to given address.
     * Can be executed only by owner.
     */
    function rescueERC20(address to, IERC20 token, uint256 amount) external onlyOwner {
        require(to != address(0), "Cannot rescue to the zero address");
        require(amount > 0, "Cannot rescue 0");

        token.safeTransfer(to, amount);
        emit RescueToken(to, address(token), amount);
    }

}
