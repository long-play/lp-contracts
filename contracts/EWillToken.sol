pragma solidity ^0.4.18;

import 'zeppelin-solidity/contracts/ownership/Ownable.sol';
import 'zeppelin-solidity/contracts/token/DetailedERC20.sol';
import 'zeppelin-solidity/contracts/token/StandardToken.sol';
//import './EWillTokenIf.sol'; // removed due to a bug of truffle - https://github.com/trufflesuite/truffle/issues/593


contract EWillToken is /*EWillTokenIf,*/ Ownable, DetailedERC20('E-Will Token', 'EWILL', 18), StandardToken {
    // State Variables
    mapping (address => uint256)  public merchants;

    // Events
    event Charged(address merchant, address payer, uint256 amount, bytes32 note);

    // Modifiers
    modifier onlyMerchant() {
        require(merchants[msg.sender] != 0);
        _;
    }

    // Constructor
    function EWillToken(uint256 _totalSupply) public {
        totalSupply = _totalSupply;
        balances[msg.sender] = totalSupply;
    }

    // Configuration
    function addMerchant(address _merchant) public onlyOwner {
        merchants[_merchant] = now;
    }

    function deleteMerchant(address _merchant) public onlyOwner {
        delete merchants[_merchant];
    }

    // EWillTokenIf
    function charge(address _payer, uint256 _amount, bytes32 _note) public onlyMerchant {
        require(_payer == tx.origin);
        require(_amount <= balances[_payer]);

        balances[_payer] = balances[_payer].sub(_amount);
        balances[msg.sender] = balances[msg.sender].add(_amount);

        Charged(msg.sender, _payer, _amount, _note);
    }
}
