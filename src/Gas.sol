//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./Ownable.sol";

contract Constants {
    uint256 public tradeFlag = 1;
    uint256 public basicFlag = 0;
    uint256 public dividendFlag = 1;
}

contract GasContract is Ownable, Constants {
    uint256 public totalSupply = 0; // cannot be updated
    uint256 public paymentCounter = 0;
    mapping(address => uint256) public balances;
    uint256 public tradePercent = 12;
    address public contractOwner;
    uint256 public tradeMode = 0;
    mapping(address => Payment[]) public payments;
    mapping(address => uint256) public whitelist;
    address[5] public administrators;
    bool public isReady = false;

    enum PaymentType {
        Unknown,
        BasicPayment,
        Refund,
        Dividend,
        GroupPayment
    }

    PaymentType constant defaultPayment = PaymentType.Unknown;

    History[] public paymentHistory; // when a payment was updated

    struct Payment {
        PaymentType paymentType;
        uint256 paymentID;
        bool adminUpdated;
        string recipientName; // max 8 characters
        address recipient;
        address admin; // administrators address
        uint256 amount;
    }

    struct History {
        uint256 lastUpdate;
        address updatedBy;
        uint256 blockNumber;
    }

    uint256 wasLastOdd = 1;
    mapping(address => uint256) public isOddWhitelistUser;

    struct ImportantStruct {
        uint256 amount;
        uint256 valueA; // max 3 digits
        uint256 bigValue;
        uint256 valueB; // max 3 digits
        bool paymentStatus;
        address sender;
    }

    mapping(address => ImportantStruct) public whiteListStruct;

    event AddedToWhitelist(address userAddress, uint256 tier);

    modifier onlyAdminOrOwner() {
        if (msg.sender == contractOwner || checkForAdmin(msg.sender)) {
            _;
        } else {
            revert("Not authorized: Caller is neither admin nor owner");
        }
    }

    modifier checkIfWhiteListed(address sender) {
        require(msg.sender == sender, "Sender mismatch");
        uint256 usersTier = whitelist[msg.sender];
        require(usersTier > 0 && usersTier < 4, "Invalid whitelist tier");
        _;
    }

    event supplyChanged(address indexed, uint256 indexed);
    event Transfer(address recipient, uint256 amount);
    event PaymentUpdated(address admin, uint256 ID, uint256 amount, string recipient);
    event WhiteListTransfer(address indexed);

    constructor(address[] memory _admins, uint256 _totalSupply) {
        contractOwner = msg.sender;
        totalSupply = _totalSupply;
        balances[contractOwner] = totalSupply;

        // Limit the number of administrators to the length of provided _admins array to prevent out-of-bounds access
        uint256 adminCount = _admins.length < administrators.length ? _admins.length : administrators.length;

        for (uint256 i = 0; i < adminCount; i++) {
            address admin = _admins[i];
            if (admin != address(0)) {
                administrators[i] = admin;
                if (admin != contractOwner) {
                    balances[admin] = 0;
                }
                emit supplyChanged(admin, balances[admin]);
            }
        }
    }

    function getPaymentHistory() public view returns (History[] memory) {
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

    function balanceOf(address _user) public view returns (uint256) {
        return balances[_user];
    }

    function getTradingMode() public view returns (bool) {
        // Return the expression result directly
        return tradeFlag == 1 || dividendFlag == 1;
    }

    function addHistory(address _updateAddress, bool _tradeMode) public returns (bool, bool) {
        paymentHistory.push(
            History({blockNumber: block.number, lastUpdate: block.timestamp, updatedBy: _updateAddress})
        );
        return (true, _tradeMode);
    }

    function getPayments(address _user) public view returns (Payment[] memory) {
        require(_user != address(0), "Invalid address");
        return payments[_user];
    }

    function transfer(address _recipient, uint256 _amount, string calldata _name) public returns (bool) {
        require(balances[msg.sender] >= _amount, "Insufficient Balance");
        require(bytes(_name).length < 9, "Recipient name is too long");

        balances[msg.sender] -= _amount;
        balances[_recipient] += _amount;

        emit Transfer(_recipient, _amount);

        payments[msg.sender].push(
            Payment({
                paymentType: PaymentType.BasicPayment,
                paymentID: ++paymentCounter,
                adminUpdated: false,
                recipientName: _name,
                recipient: _recipient,
                admin: address(0),
                amount: _amount
            })
        );

        // Return true directly; avoids unnecessary memory allocation and computation
        return true;
    }

    function updatePayment(address _user, uint256 _ID, uint256 _amount, PaymentType _type) public onlyAdminOrOwner {
        require(_ID > 0, "ID must be greater than 0");
        require(_amount > 0, "Amount must be greater than 0");
        require(_user != address(0), "Address must be valid and non-zero");

        Payment[] storage userPayments = payments[_user];
        bool tradingMode = getTradingMode();

        for (uint256 i = 0; i < userPayments.length; i++) {
            Payment storage payment = userPayments[i];
            if (payment.paymentID == _ID) {
                payment.adminUpdated = true;
                payment.admin = _user;
                payment.paymentType = _type;
                payment.amount = _amount;

                addHistory(_user, tradingMode);
                emit PaymentUpdated(msg.sender, _ID, _amount, payment.recipientName);
                break; // Exit the loop early after updating the payment
            }
        }
    }

    function addToWhitelist(address _userAddrs, uint256 _tier) public onlyAdminOrOwner {
        require(_tier < 255, "Gas Contract - addToWhitelist function -  tier level should not be greater than 255");
        whitelist[_userAddrs] = _tier;
        if (_tier > 3) {
            whitelist[_userAddrs] -= _tier;
            whitelist[_userAddrs] = 3;
        } else if (_tier == 1) {
            whitelist[_userAddrs] -= _tier;
            whitelist[_userAddrs] = 1;
        } else if (_tier > 0 && _tier < 3) {
            whitelist[_userAddrs] -= _tier;
            whitelist[_userAddrs] = 2;
        }
        uint256 wasLastAddedOdd = wasLastOdd;
        if (wasLastAddedOdd == 1) {
            wasLastOdd = 0;
            isOddWhitelistUser[_userAddrs] = wasLastAddedOdd;
        } else if (wasLastAddedOdd == 0) {
            wasLastOdd = 1;
            isOddWhitelistUser[_userAddrs] = wasLastAddedOdd;
        } else {
            revert("Contract hacked, imposible, call help");
        }
        emit AddedToWhitelist(_userAddrs, _tier);
    }

    function whiteTransfer(address _recipient, uint256 _amount) public checkIfWhiteListed(msg.sender) {
        address senderOfTx = msg.sender;
        whiteListStruct[senderOfTx] = ImportantStruct(_amount, 0, 0, 0, true, msg.sender);

        require(
            balances[senderOfTx] >= _amount, "Gas Contract - whiteTransfers function - Sender has insufficient Balance"
        );
        require(_amount > 3, "Gas Contract - whiteTransfers function - amount to send have to be bigger than 3");
        balances[senderOfTx] -= _amount;
        balances[_recipient] += _amount;
        balances[senderOfTx] += whitelist[senderOfTx];
        balances[_recipient] -= whitelist[senderOfTx];

        emit WhiteListTransfer(_recipient);
    }

    function getPaymentStatus(address sender) public view returns (bool, uint256) {
        return (whiteListStruct[sender].paymentStatus, whiteListStruct[sender].amount);
    }

    receive() external payable {
        payable(msg.sender).transfer(msg.value);
    }

    fallback() external payable {
        payable(msg.sender).transfer(msg.value);
    }
}
