/* 
 ** Description **
 This contract is the recurring lottery based on rate of ethereum.
 Participants can place their bets (rate of ethereum) and as soon as
 necessary quantity of participants will be reached, contract sends
 request to oracle (trusted third party) to receive current ETH rate
 from Coinmarketcap, select winner (bet with the most closest value) and transfer
 amount of lottery serie to winner. Also the new serie of lottery is created 
 when the lottery is executed.
 To initialize the process owner should deploy the factory contract and also 
 create first lottery serie. Parameters of the new lottery series (URL to 
 get the rate by the oracle, number of lottery participants, minimal bate amount)
 can be changed by the owner through changing the factory parameters. 
 Owner can also be changed.
*/
/*
 ** Possible Further Improvements **
 - Charity accounts to be added (so the profit is transfered to set of accounts)
 - Multi-signature approvals of the changes and profit withdraw
*/
/* 
  ** Notes **
 - Oraclize service (oraclize.it) is used as independent and trusted third party to obtain external data
 - Specific compiler version is mentioned as newer versions are not supported by Oracle contract
 - Only limited functions can be tested locally in dev environment (or local oracle should be setup)
 - Contract is tested at Rinkeby and Ropsten networks
*/

pragma solidity ^0.4.20;
	
import  "github.com/oraclize/ethereum-api/oraclizeAPI.sol";

// Contract that performs lottery logic (each serie separately)
contract RateLottery is usingOraclize {
    
    // Serie settings (this parameters cannot be changed for serie)
    address owner;
    address superOwner;
    uint numberOfVotes;
    uint minimalValueOfVote;
    uint winnerPercentage;
    string APIquery;
    
    // Events of the lottery
    event NewVote(address voter, uint rate);
    event LotteryExecuted(address oracle);
    event WinnerSelected(address winner, uint rate, uint amount);
    
    struct Vote{
        address _voter;
        uint _rate;
    }

    Vote[] votes;
    
    // Getters of the contract
    function getOwner() constant external returns(address) {
        return owner;
    }
    
    function getSuperOwner() constant external returns(address) {
        return superOwner;
    }
    
    // Constructor (initalize lottery parameters)
    function RateLottery(string _APIquery, uint _numberOfVotes, uint _minimalValueOfVote, uint _winnerPercentage, address _superOwner) public{
        owner = msg.sender;
        superOwner = _superOwner;
        APIquery = _APIquery;
        numberOfVotes = _numberOfVotes;
        minimalValueOfVote = _minimalValueOfVote;
        winnerPercentage = _winnerPercentage;
    }
    
    // This is to vote, user passes rate (format xxx.xx) and transfer ETH to vote
    function vote(string _rate) external payable {
        // Check for required conditions
        require(nrate>0 && msg.value>=minimalValueOfVote && votes.length<numberOfVotes);
        uint nrate = parseInt(_rate,2);  // Translate rate to uint
        votes.push(Vote(msg.sender, nrate)); // Addthis vote to array
        NewVote(msg.sender, nrate); // Emit event
        if(votes.length >= numberOfVotes) {  //If number of votes is already reached then execute the lottery
            executeLottery();
        }
    }
    
    // Execution of the lottery when all votes already made
    function executeLottery() internal {
        LotteryFactory(owner).createLottery(); // Call factory contract to create new serie
        require(oraclize_getPrice("URL") < this.balance); // Check we have enough balance to call oracle
        oraclize_query("URL", APIquery); // call oracle to check current rate
        LotteryExecuted(oraclize_cbAddress()); // Emit event
    }
    
    // Execute lottery externally if needed by owner (in case oracle haven't returned result)
    function executeLotteryExt() external{
        require(msg.sender==superOwner);
        executeLottery();
    }
    
    // Absolette difference calculation
    function differenceABS(uint _a, uint _b) internal returns (uint){
        if(_a > _b){
            return _a - _b;
        } else {
            return _b - _a;
        }
    }
    
    // This function is called by the oracle back when request is executed, oracle passes the result back
    function __callback(bytes32 myid, string result) {
        require(msg.sender == oraclize_cbAddress()); // Check that oracle sends the result
        uint rate = parseInt(result,2); // Evaluate xxx.xx to operate without decimals
        uint difference = rate**2;  // Make difference max
        address winner = address(0); // Init winner address with zero
        uint winRate; // Winner rate
        for(uint i=0;i<votes.length;i++){ // Check all votes for rate difference
            uint newDifference = differenceABS(rate, votes[i]._rate);
            if(newDifference<difference){ // If difference of vote and actual rate less than this is current winner
                difference = newDifference;
                winner = votes[i]._voter;
                winRate = votes[i]._rate;
            }
        }
        if(winner!=address(0)){ // If winner is identified
            if(winner.send(address(this).balance*winnerPercentage/100)){ // Winner receives fixed percentage
                WinnerSelected(winner, winRate, address(this).balance); // Emit winning event
            } 
        }
        selfdestruct(owner); // The rest goes to owner
    }
    
    // This is better to be removed for purity of the lottery
    function kill() external {
        require(msg.sender==superOwner);
        selfdestruct(owner);
    }
}

// Lottery factory contract
contract LotteryFactory {
    
    // Parameters of the Factory
    address owner;
    address[] lotteries;
    address activeLottery;
    
    // Settings of the lottery
    string APILink;
    uint numberOfVotes;
    uint minimalValueOfVotes;
    uint winnerPercentage;
    
    // Getters functions
    function getCurrentLottery() constant external returns (address){
        return activeLottery;
    }
    
    function getLotteryParameters() constant external returns (string, uint, uint, uint){
        return (APILink, numberOfVotes, minimalValueOfVotes, winnerPercentage);
    }
    
    function getOwner() constant external returns(address) {
        return owner;
    }
    
    function getNumberOfLotteries() constant external returns (uint) {
        return lotteries.length;
    }
    
    // Creates new lottery contract serie, returns address of contract and add to array
    function createLottery() public returns (address) {
        activeLottery = new RateLottery(APILink, numberOfVotes, minimalValueOfVotes, winnerPercentage, owner);
        lotteries.push(activeLottery);
        return activeLottery;
    }
    
    // Updater of the lottery parameters (only by owner)
    function updateLotteryParameters(string _APILink, uint _numberOfVotes, uint _minimalValueOfVotes, uint _winnerPercentage) public {
        require(msg.sender == owner); // Check if the owner
        APILink = _APILink;
        numberOfVotes = _numberOfVotes;
        minimalValueOfVotes = _minimalValueOfVotes;
        winnerPercentage = _winnerPercentage;
    }
    
    // Constructor initializes parameters (can be changed then)
    function LotteryFactory() payable public {
        owner = msg.sender;
        updateLotteryParameters("json(https://api.coinmarketcap.com/v2/ticker/1027/).data.quotes.USD.price",  //ETH price in USD obtained from coinmarketcap API
            3,          // 3 votes for lottery execution
            1000000,    // 1000000 wei is the minimal amout to participate
            95          // 95% to be transfered to winner
        );
    }
    
    // Owner's change
    function changeOwner(address newOwner) external{
        require(msg.sender == owner);
        owner = newOwner;
    }
    
    // Payback of the profit to owner (requested amount)
    function payBack(uint amount) external{
        require(msg.sender==owner);
        owner.transfer(amount);
    }
    
}
