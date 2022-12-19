// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;


import '../libraries/Math.sol';
import '../interfaces/IBribeFull.sol';
import '../interfaces/IWrappedBribeFactory.sol';
import '../interfaces/IGauge.sol';
import '../interfaces/IGaugeFactory.sol';
import '../interfaces/IERC20.sol';
import '../interfaces/IMinter.sol';
import '../interfaces/IPair.sol';
import '../interfaces/IPairFactory.sol';
import '../interfaces/IVoter.sol';
import '../interfaces/IVotingEscrow.sol';

import "hardhat/console.sol";

contract PairAPI {


    struct pairInfo {
        // pair info
        address pair_address; 			// pair contract address
        string symbol; 				    // pair symbol
        string name;                    // pair name
        uint decimals; 			        // pair decimals
        bool stable; 				    // pair pool type (stable = false, means it's a variable type of pool)
        uint total_supply; 			    // pair tokens supply
    
        // token pair info
        address token0; 				// pair 1st token address
        string token0_symbol; 			// pair 1st token symbol
        uint token0_decimals; 		    // pair 1st token decimals
        uint reserve0; 			        // pair 1st token reserves (nr. of tokens in the contract)
        uint claimable0;                // claimable 1st token from fees (for unstaked positions)

        address token1; 				// pair 2nd token address
        string token1_symbol;           // pair 2nd token symbol
        uint token1_decimals;    		// pair 2nd token decimals
        uint reserve1; 			        // pair 2nd token reserves (nr. of tokens in the contract)
        uint claimable1; 			    // claimable 2nd token from fees (for unstaked positions)

        // pairs gauge
        address gauge; 				    // pair gauge address
        uint gauge_total_supply; 		// pair staked tokens (less/eq than/to pair total supply)
        address fee; 				    // pair fees contract address
        address bribe; 				    // pair bribes contract address
        address wrapped_bribe; 			// pair wrapped bribe contract address
        uint emissions; 			    // pair emissions (per second)
        address emissions_token; 		// pair emissions token address
        uint emissions_token_decimals; 	// pair emissions token decimals

        // User deposit
        uint account_lp_balance; 		// account LP tokens balance
        uint account_token0_balance; 	// account 1st token balance
        uint account_token1_balance; 	// account 2nd token balance
        uint account_gauge_balance;     // account pair staked in gauge balance
        uint account_gauge_earned; 		// account earned emissions for this pair
    }


    struct tokenBribe {
        address token;
        uint8 decimals;
        uint256 amount;
        string symbol;
    }
    

    struct pairBribeEpoch {
        uint256 epochTimestamp;
        uint256 totalVotes;
        address pair;
        tokenBribe[] bribes;
    }

    uint256 public constant MAX_PAIRS = 1000;
    uint256 public constant MAX_EPOCHS = 200;
    uint256 public constant MAX_REWARDS = 16;
    uint256 public constant WEEK = 7 * 24 * 60 * 60;


    IPairFactory public pairFactory;
    IVoter public voter;
    IWrappedBribeFactory public wBribeFactory;

    address public underlyingToken;

    address public owner;


    event Owner(address oldOwner, address newOwner);
    event Voter(address oldVoter, address newVoter);
    event WBF(address oldWBF, address newWBF);

    constructor(address _voter, address _wBribeFactory) {
        owner = msg.sender;

        voter = IVoter(_voter);

        wBribeFactory = IWrappedBribeFactory(_wBribeFactory);

        require(wBribeFactory.voter() == address(voter), '!= voters');

        voter = IVoter(_voter);
        pairFactory = IPairFactory(voter.factory());
        underlyingToken = IVotingEscrow(voter._ve()).token();
        
    }



    function getAllPair(address _user, uint _amounts, uint _offset) external view returns(pairInfo[] memory Pairs){

        
        require(_amounts <= MAX_PAIRS, 'too many pair');

        Pairs = new pairInfo[](_amounts);
        
        uint i = _offset;
        uint totPairs = pairFactory.allPairsLength();
        address _pair;

        for(i; i < _offset + _amounts; i++){
            // if totalPairs is reached, break.
            if(i == totPairs) {
                break;
            }
            _pair = pairFactory.allPairs(i);
            Pairs[i - _offset] = _pairAddressToInfo(_pair, _user);
        }        

    }

    function getPair(address _pair, address _account) external view returns(pairInfo memory _pairInfo){
        return _pairAddressToInfo(_pair, _account);
    }

    function _pairAddressToInfo(address _pair, address _account) internal view returns(pairInfo memory _pairInfo) {

        IPair ipair = IPair(_pair);
        
        address token_0;
        address token_1;
        uint r0;
        uint r1;
        
        (token_0, token_1) = ipair.tokens();
        (r0, r1, ) = ipair.getReserves();

        IGauge _gauge = IGauge(voter.gauges(_pair));
        uint accountGaugeLPAmount = 0;
        uint earned = 0;
        uint gaugeTotalSupply = 0;
        uint emissions = 0;

        if(address(_gauge) != address(0)){
            accountGaugeLPAmount = _gauge.balanceOf(_account);
            earned = _gauge.earned(underlyingToken, _account);
            gaugeTotalSupply = _gauge.totalSupply();
            emissions = _gauge.rewardRate(underlyingToken);
        }
        
        // Pair General Info
        _pairInfo.pair_address = _pair;
        _pairInfo.symbol = ipair.symbol();
        _pairInfo.name = ipair.name();
        _pairInfo.decimals = ipair.decimals();
        _pairInfo.stable = ipair.isStable();
        _pairInfo.total_supply = ipair.totalSupply();        

        // Token0 Info
        _pairInfo.token0 = token_0;
        _pairInfo.token0_decimals = IERC20(token_0).decimals();
        _pairInfo.token0_symbol = IERC20(token_0).symbol();
        _pairInfo.reserve0 = r0;
        _pairInfo.claimable0 = ipair.claimable0(_account);

        // Token1 Info
        _pairInfo.token1 = token_1;
        _pairInfo.token1_decimals = IERC20(token_1).decimals();
        _pairInfo.token1_symbol = IERC20(token_1).symbol();
        _pairInfo.reserve1 = r1;
        _pairInfo.claimable1 = ipair.claimable1(_account);

        // Pair's gauge Info
        _pairInfo.gauge = address(_gauge);
        _pairInfo.gauge_total_supply = gaugeTotalSupply;
        _pairInfo.emissions = emissions;
        _pairInfo.emissions_token = underlyingToken;
        _pairInfo.emissions_token_decimals = IERC20(underlyingToken).decimals();

        // external address
        _pairInfo.fee = voter.internal_bribes(address(_gauge)); 				    
        _pairInfo.bribe = voter.external_bribes(address(_gauge)); 				    
        _pairInfo.wrapped_bribe = wBribeFactory.oldBribeToNew( voter.external_bribes(address(_gauge)) ); 			


        // Account Info
        _pairInfo.account_lp_balance = IERC20(_pair).balanceOf(_account);
        _pairInfo.account_token0_balance = IERC20(token_0).balanceOf(_account);
        _pairInfo.account_token1_balance = IERC20(token_1).balanceOf(_account);
        _pairInfo.account_gauge_balance = accountGaugeLPAmount;
        _pairInfo.account_gauge_earned = earned;
        

    }

    function getPairBribe(uint _amounts, uint _offset, address _pair) external view returns(pairBribeEpoch[] memory _pairEpoch){

        require(_amounts <= MAX_EPOCHS, 'too many epochs');

        _pairEpoch = new pairBribeEpoch[](_amounts);

        address _gauge = voter.gauges(_pair);
        console.log(_gauge);

        IBribeFull bribe  = IBribeFull(voter.external_bribes(_gauge));
        address _wbribe = wBribeFactory.oldBribeToNew( voter.external_bribes(address(_gauge)) );

        console.log(_wbribe);

        // check bribe and checkpoints exists
        if(address(0) == address(bribe) || address(0) == _wbribe){
            return _pairEpoch;
        }
        uint256 supplyNumCheckpoints = bribe.supplyNumCheckpoints();
        if(supplyNumCheckpoints == 0){
            return _pairEpoch;
        }

        // scan bribes starting from last, we do not know init timestamp.
        // get latest balance and epoch start for bribes
        uint _epochEndTimestamp;
        uint _epochStartTimestamp;
        uint _supplyIndex;
        uint _timestamp;
        uint _supply;

        uint _start = block.timestamp + 7 * 86400;
        uint i = _offset;
        for(i; i < _offset + _amounts; i++){
            
            _epochEndTimestamp      = bribe.getEpochStart(_start) - 1;
            _supplyIndex            = bribe.getPriorSupplyIndex(_epochEndTimestamp);
            (_timestamp,_supply)    = bribe.supplyCheckpoints(_supplyIndex);
            _epochStartTimestamp    = bribe.getEpochStart(_timestamp);


            _pairEpoch[i-_offset].epochTimestamp = _epochStartTimestamp;
            _pairEpoch[i-_offset].pair = _pair;
            _pairEpoch[i-_offset].totalVotes = _supply;
            _pairEpoch[i-_offset].bribes = _bribe(_epochStartTimestamp, _wbribe);

            _start -= WEEK; 

        }

    }

    function _bribe(uint _ts, address _br) internal view returns(tokenBribe[] memory _tb){

        IBribeFull _wb = IBribeFull(_br);
        uint tokenLen = _wb.rewardsListLength();

        _tb = new tokenBribe[](tokenLen);

        uint k;
        uint _rewPerEpoch;
        IERC20 _t;
        for(k = 0; k < tokenLen; k++){
            _t = IERC20(_wb.rewards(k));
            _rewPerEpoch = _wb.tokenRewardsPerEpoch(address(_t), _ts);
            if(_rewPerEpoch > 0){
                _tb[k].token = address(_t);
                _tb[k].symbol = _t.symbol();
                _tb[k].decimals = _t.decimals();
                _tb[k].amount = _rewPerEpoch;
            } else{
                _tb[k].token = address(_t);
                _tb[k].symbol = _t.symbol();
                _tb[k].decimals = _t.decimals();
                _tb[k].amount = 0;
            }
        }
    }


    function setOwner(address _owner) external {
        require(msg.sender == owner, 'not owner');
        require(_owner != address(0), 'zeroAddr');
        owner = _owner;
        emit Owner(msg.sender, _owner);
    }


    function setVoter(address _voter) external {
        require(msg.sender == owner, 'not owner');
        require(_voter != address(0), 'zeroAddr');
        address _oldVoter = address(voter);
        voter = IVoter(_voter);
        
        require(wBribeFactory.voter() == address(voter), '!= voters');

        // update variable depending on voter
        pairFactory = IPairFactory(voter.factory());
        underlyingToken = IVotingEscrow(voter._ve()).token();

        emit Voter(_oldVoter, _voter);
    }

    
    function setWrappedBribeFactory(address _wBribeFactorywBribeFactory) external {
        require(msg.sender == owner, 'not owner');
        require(_wBribeFactorywBribeFactory != address(0), 'zeroAddr');
        
        address _oldwBribeFactory = address(wBribeFactory);
        wBribeFactory = IWrappedBribeFactory(_wBribeFactorywBribeFactory);
        
        require(wBribeFactory.voter() == address(voter), '!= voters');

        emit WBF(_oldwBribeFactory, _wBribeFactorywBribeFactory);
    }


}