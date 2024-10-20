//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./Ownable.sol";

contract Constants {
    uint256 public constant tradeFlag = 1;
    uint256 public constant basicFlag = 0;
    uint256 public constant dividendFlag = 1;
}

contract GasContract is Ownable, Constants {
    bool private isReady = false;
    uint256 private totalSupply = 0; // cannot be updated
    uint256 private paymentCounter = 0;
    uint256 private constant tradePercent = 12;
    uint256 private constant tradeMode = 0;
    uint256 private wasLastOdd = 1;

    address private immutable contractOwner;
    address[5] public administrators;

    mapping(address => uint256) public balances;
    mapping(address => uint256) public whitelist;
    mapping(address => uint256) private isOddWhitelistUser;
    mapping(address => ImportantStruct) private whiteListStruct;
    mapping(address => Payment[]) private payments;

    enum PaymentType {
        Unknown,
        BasicPayment,
        Refund,
        Dividend,
        GroupPayment
    }

    PaymentType private constant defaultPayment = PaymentType.Unknown;

    History[] private paymentHistory; // when a payment was updated

    struct Payment {
        PaymentType paymentType;
        uint256 paymentID;
        uint256 amount;
        bool adminUpdated;
        string recipientName; // max 8 characters
        address recipient;
        address admin; // administrators address
    }

    struct History {
        uint256 lastUpdate;
        uint256 blockNumber;
        address updatedBy;
    }

    struct ImportantStruct {
        uint256 amount;
        uint256 valueA; // max 3 digits
        uint256 bigValue;
        uint256 valueB; // max 3 digits
        bool paymentStatus;
        address sender;
    }

    event AddedToWhitelist(address userAddress, uint256 tier);

    modifier onlyAdminOrOwner() {
        if (msg.sender == contractOwner || checkForAdmin(msg.sender)) {
            _;
        } else {
            revert();
        }
    }

    modifier checkIfWhiteListed(address sender) {
        require(msg.sender == sender, "Bad");
        uint256 usersTier = whitelist[msg.sender];
        require(usersTier > 0 && usersTier < 4, "Bad");
        _;
    }

    event supplyChanged(address indexed initiator, uint256 newAmount);
    event Transfer(address indexed recipient, uint256 amount);
    event PaymentUpdated(address indexed admin, uint256 id, uint256 amount, string recipientName);
    event WhiteListTransfer(address indexed account);

    constructor(address[] memory _admins, uint256 _totalSupply) {
        contractOwner = msg.sender;
        totalSupply = _totalSupply;
        balances[contractOwner] = totalSupply;

        // Initialize administrators up to the provided _admins array length
        uint256 adminCount = _admins.length;
        for (uint256 i = 0; i < adminCount; i++) {
            address admin = _admins[i];
            if (admin == address(0)) continue; // Skip zero addresses immediately

            administrators[i] = admin;

            // Ensure owner is not set as an admin and skip balance assignment
            if (admin != contractOwner) {
                balances[admin] = 0;
                emit supplyChanged(admin, 0); // Assuming the emitted balance is intended to be zero for admins
            }
        }
    }

    function getPaymentHistory() external view returns (History[] memory) {
        return paymentHistory;
    }

    function checkForAdmin(address _user) public view returns (bool) {
        for (uint256 ii = 0; ii < administrators.length; ii++) {
            if (administrators[ii] == _user) {
                return true; // Exit loop early if admin is found
            }
        }
        return false; // If no match was found
    }

    function balanceOf(address _user) external view returns (uint256) {
        return balances[_user];
    }

    function getTradingMode() private pure returns (bool) {
        return tradeFlag == 1 || dividendFlag == 1;
    }

    function addHistory(address _updateAddress, bool _tradeMode) private returns (bool, bool) {
        paymentHistory.push(
            History({blockNumber: block.number, lastUpdate: block.timestamp, updatedBy: _updateAddress})
        );
        return (true, _tradeMode);
    }

    function getPayments(address _user) private view returns (Payment[] memory) {
        require(_user != address(0), "Bad");
        return payments[_user];
    }

    function transfer(address _recipient, uint256 _amount, string calldata _name) public returns (bool) {
        require(balances[msg.sender] >= _amount, "Bad");
        require(bytes(_name).length < 9, "Bad");

        balances[msg.sender] -= _amount;
        balances[_recipient] += _amount;

        emit Transfer(_recipient, _amount);

        payments[msg.sender].push(
            Payment({
                paymentType: PaymentType.BasicPayment,
                amount: _amount,
                paymentID: ++paymentCounter,
                adminUpdated: false,
                recipientName: _name,
                recipient: _recipient,
                admin: address(0)
            })
        );

        // Return true directly; avoids unnecessary memory allocation and computation
        return true;
    }

    function updatePayment(address _user, uint256 _ID, uint256 _amount, PaymentType _type) private onlyAdminOrOwner {
        require(_user != address(0), "Bad");
        require(_ID > 0 && _amount > 0, "Bad");

        Payment[] memory userPayments = payments[_user];
        uint256 len = userPayments.length;

        for (uint256 i = 0; i < len;) {
            Payment memory payment = userPayments[i];
            if (payment.paymentID == _ID) {
                payment.adminUpdated = true;
                payment.admin = msg.sender; // This assumes msg.sender is the admin making the update
                payment.paymentType = _type;
                payment.amount = _amount;

                addHistory(_user, getTradingMode()); // Inline getTradingMode to reduce storage access
                emit PaymentUpdated(msg.sender, _ID, _amount, payment.recipientName);
                break;
            }
            unchecked {
                ++i;
            } // Use unchecked to save gas on loop increment
        }
    }

    function addToWhitelist(address _userAddrs, uint256 _tier) public onlyAdminOrOwner {
        require(_tier < 255, "Bad");
        whitelist[_userAddrs] = _tier;
        if (_tier > 3) {
            whitelist[_userAddrs] = 3;
        }

        uint256 wasLastAddedOdd = wasLastOdd;
        wasLastOdd = 1 - wasLastAddedOdd; // Efficiently toggle between 0 and 1
        isOddWhitelistUser[_userAddrs] = wasLastAddedOdd; // Set the current state

        emit AddedToWhitelist(_userAddrs, _tier);
    }

    // function addToWhitelist(address _userAddrs, uint256 _tier) public onlyAdminOrOwner {
    //     require(_tier > 0 && _tier < 255, "Invalid tier");

    //     uint256 adjustedTier = _tier > 3 ? 3 : _tier;
    //     whitelist[_userAddrs] = adjustedTier;

    //     // Toggle the wasLastOdd flag using arithmetic
    //     wasLastOdd = 1 - wasLastOdd;
    //     isOddWhitelistUser[_userAddrs] = wasLastOdd;

    //     emit AddedToWhitelist(_userAddrs, adjustedTier);
    // }

    function whiteTransfer(address _recipient, uint256 _amount) public checkIfWhiteListed(msg.sender) {
        require(balances[msg.sender] >= _amount, "Bad");
        require(_amount > 3, "Bad");

        // Directly initialize ImportantStruct without unnecessary zero assignments
        whiteListStruct[msg.sender] = ImportantStruct(_amount, 0, 0, 0, true, msg.sender);

        // Adjust balances efficiently
        uint256 whitelistBonus = whitelist[msg.sender];
        balances[msg.sender] = balances[msg.sender] - _amount + whitelistBonus;
        balances[_recipient] = balances[_recipient] + _amount - whitelistBonus;

        emit WhiteListTransfer(_recipient);
    }

    function getPaymentStatus(address sender) external view returns (bool, uint256) {
        return (whiteListStruct[sender].paymentStatus, whiteListStruct[sender].amount);
    }

    receive() external payable {
        payable(msg.sender).transfer(msg.value);
    }

    fallback() external payable {
        payable(msg.sender).transfer(msg.value);
    }
}
