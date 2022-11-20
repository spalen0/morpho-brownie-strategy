// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {
    BaseStrategy,
    StrategyParams
} from "@yearnvaults/contracts/BaseStrategy.sol";
import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";

import "../interfaces/IMorpho.sol";
import "../interfaces/IRewardsDistributor.sol";
import "../interfaces/lens/ILens.sol";
import "../interfaces/ySwap/ITradeFactory.sol";

abstract contract MorphoStrategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public rewardsDistributor =
        0x3B14E5C73e0A56D607A8688098326fD4b4292135;
    address public constant MORPHO_TOKEN =
        0x9994E35Db50125E0DF82e4c2dde62496CE330999;

    // ySwap TradeFactory:
    address public tradeFactory;
    // Morpho is a contract to handle interaction with the protocol
    IMorpho public immutable morpho;
    // Lens is a contract to fetch data about Morpho protocol
    ILens public immutable lens;
    // poolToken = Morpho Market for want token, address of poolToken
    address public immutable poolToken;
    // Max gas used for matching with p2p deals
    uint256 public maxGasForMatching = 100000;
    string internal strategyName;

    constructor(
        address _vault,
        address _poolToken,
        string memory _strategyName,
        address _morpho,
        address _lens
    ) public BaseStrategy(_vault) {
        poolToken = _poolToken;
        strategyName = _strategyName;
        lens = ILens(_lens);
        morpho = IMorpho(_morpho);
        want.safeApprove(_morpho, type(uint256).max);
    }

    // ******** BaseStrategy overriden contract function ************

    function name() external view override returns (string memory) {
        return strategyName;
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        return want.balanceOf(address(this)).add(getTotalSupplyBalance());
    }

    // NOTE: Return `_profit` which is value generated by all positions, priced in `want`
    // NOTE: Should try to free up at least `_debtOutstanding` of underlying position
    function prepareReturn(uint256 _debtOutstanding)
        internal
        virtual
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        uint256 totalDebt = vault.strategies(address(this)).totalDebt;
        uint256 totalAssetsAfterProfit = estimatedTotalAssets();
        _profit = totalAssetsAfterProfit > totalDebt
            ? totalAssetsAfterProfit.sub(totalDebt)
            : 0;

        (_debtPayment, _loss) = liquidatePosition(
            _debtOutstanding.add(_profit)
        );
        _debtPayment = Math.min(_debtPayment, _debtOutstanding);

        // Net profit and loss calculation
        if (_loss > _profit) {
            _loss = _loss.sub(_profit);
            _profit = 0;
        } else {
            _profit = _profit.sub(_loss);
            _loss = 0;
        }
    }

    // NOTE: Try to adjust positions so that `_debtOutstanding` can be freed up on *next* harvest (not immediately)
    function adjustPosition(uint256 _debtOutstanding) internal override {
        uint256 wantBalance = want.balanceOf(address(this));
        if (wantBalance > _debtOutstanding) {
            morpho.supply(
                poolToken,
                address(this),
                wantBalance.sub(_debtOutstanding),
                maxGasForMatching
            );
        }
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        uint256 wantBalance = want.balanceOf(address(this));
        if (_amountNeeded > wantBalance) {
            _liquidatedAmount = Math.min(
                _amountNeeded.sub(wantBalance),
                getTotalSupplyBalance()
            );
            morpho.withdraw(poolToken, _liquidatedAmount);
            _liquidatedAmount = Math.min(
                want.balanceOf(address(this)),
                _amountNeeded
            );
            _loss = _amountNeeded > _liquidatedAmount
                ? _amountNeeded.sub(_liquidatedAmount)
                : 0;
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        uint256 balanceToWithdraw = getTotalSupplyBalance();
        if (balanceToWithdraw > 0) {
            morpho.withdraw(poolToken, type(uint256).max);
        }
        return want.balanceOf(address(this));
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary
    // NOTE: `migrate` will automatically forward all `want` in this strategy to the new one
    function prepareMigration(address _newStrategy) internal virtual override {
        liquidateAllPositions();
    }

    // NOTE: Do *not* include `want`, already included in `sweep` below
    function protectedTokens()
        internal
        view
        virtual
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](1);
        protected[0] = poolToken;
        return protected;
    }

    /**
     * @notice
     *  Provide an accurate conversion from `_amtInWei` (denominated in wei)
     *  to `want` (using the native decimal characteristics of `want`).
     * @dev
     *  Care must be taken when working with decimals to assure that the conversion
     *  is compatible. As an example:
     *
     *      given 1e17 wei (0.1 ETH) as input, and want is USDC (6 decimals),
     *      with USDC/ETH = 1800, this should give back 1800000000 (180 USDC)
     *
     * @param _amtInWei The amount (in wei/1e-18 ETH) to convert to `want`
     * @return The amount in `want` of `_amtInEth` converted to `want`
     **/
    function ethToWant(uint256 _amtInWei)
        public
        view
        virtual
        override
        returns (uint256)
    {
        // TODO create an accurate price oracle
        return _amtInWei;
    }

    /**
     * @notice
     *  Set the maximum amount of gas to consume to get matched in peer-to-peer.
     * @dev
     *  This value is needed in morpho supply liquidity calls.
     *  Supplyed liquidity goes to loop with current loans on Compound
     *  and creates a match for p2p deals. The loop starts from bigger liquidity deals.
     * @param _maxGasForMatching new maximum gas value for
     */
    function setMaxGasForMatching(uint256 _maxGasForMatching)
        external
        onlyAuthorized
    {
        maxGasForMatching = _maxGasForMatching;
    }

    /**
     * @notice Set new rewards distributor contract
     * @param _rewardsDistributor address of new contract
     */
    function setRewardsDistributor(address _rewardsDistributor)
        external
        onlyAuthorized
    {
        rewardsDistributor = _rewardsDistributor;
    }

    /**
     * @notice
     *  Claims MORPHO rewards. Use Morpho API to get the data: https://api.morpho.xyz/rewards/{address}
     * @dev See stages of Morpho rewards distibution: https://docs.morpho.xyz/usdmorpho/ages-and-epochs/age-2
     * @param _account The address of the claimer.
     * @param _claimable The overall claimable amount of token rewards.
     * @param _proof The merkle proof that validates this claim.
     */
    function claimMorphoRewards(
        address _account,
        uint256 _claimable,
        bytes32[] calldata _proof
    ) external onlyAuthorized {
        IRewardsDistributor(rewardsDistributor).claim(
            _account,
            _claimable,
            _proof
        );
    }

    // ---------------------- View functions ----------------------
    /**
     * @notice
     *  Computes and returns the total amount of underlying ERC20 token a given user has supplied through Morpho
     *  on a given market, taking into account interests accrued.
     * @dev
     *  The value is in `want` precision, decimals so there is no need to convert this value if calculating with `want`.
     * @return _balance of `want` token supplied to Morpho in `want` precision
     */
    function getTotalSupplyBalance() public view returns (uint256 _balance) {
        (, , _balance) = lens.getCurrentSupplyBalanceInOf(
            poolToken,
            address(this)
        );
    }

    /**
     * @notice
     *  Computes and returns the total amount of underlying ERC20 token a given user has supplied through Morpho
     *  on a given market, taking into account interests accrued.
     * @return _balanceOnPool balance of pool token provided to pool, underlying protocol
     * @return _balanceInP2P balance provided to P2P deals
     * @return _totalBalance equals to balanceOnPool + balanceInP2P
     */
    function getStrategySupplyBalance()
        public
        view
        returns (
            uint256 _balanceOnPool,
            uint256 _balanceInP2P,
            uint256 _totalBalance
        )
    {
        (_balanceOnPool, _balanceInP2P, _totalBalance) = lens
            .getCurrentSupplyBalanceInOf(poolToken, address(this));
    }

    /**
     * @notice
     *  Gets the current liquditiy, both P2P and pool, for supplied and borrowed amount in Morpho protocol for strategy pool token
     * @return _p2pSupplyAmount supplied amount of pool token in P2P deals
     * @return _p2pBorrowAmount borrowed amount of pool token in P2P deals
     * @return _poolSupplyAmount supplied amount of pool token in pool deals, non P2P deals
     * @return _poolBorrowAmount borrowed amount of pool token in pool deals, non P2P deals
     */
    function getCurrentMarketLiquidity()
        external
        view
        returns (
            uint256 _p2pSupplyAmount,
            uint256 _p2pBorrowAmount,
            uint256 _poolSupplyAmount,
            uint256 _poolBorrowAmount
        )
    {
        (
            ,
            ,
            _p2pSupplyAmount,
            _p2pBorrowAmount,
            _poolSupplyAmount,
            _poolBorrowAmount
        ) = lens.getMainMarketData(poolToken);
    }

    /**
     * @notice
     *  Caluclates the maximum amount that can be supplied to just P2P deals.
     * @return _maxP2PSupply maximum amount that can be supplied to P2P deals
     */
    function getMaxP2PSupply() external view returns (uint256 _maxP2PSupply) {
        (_maxP2PSupply, , ) = getSupplyBalancesForAmount(type(uint128).max);
    }

    /**
     * @notice
     *  For a given amount of pool tokens it will return balance that will end in P2P deal and balance of pool deal.
     * @param _amount Token amount intended to supply to Morpho protocol
     * @return _balanceInP2P balance that will end up in P2P deals
     * @return _balanceOnPool balance that will end up in pool deal, underlying protocol
     * @return _apr hypothetical supply rate per year experienced by the user on the given market,
     * devide by 10^16 to get a number in percentage
     */
    function getSupplyBalancesForAmount(uint256 _amount)
        public
        view
        virtual
        returns (
            uint256 _balanceInP2P,
            uint256 _balanceOnPool,
            uint256 _apr
        );

    // ---------------------- YSWAPS FUNCTIONS ----------------------
    function setTradeFactory(address _tradeFactory) external onlyGovernance {
        if (tradeFactory != address(0)) {
            _removeTradeFactoryPermissions();
        }
        tradeFactory = _tradeFactory;
        _setTradeFactoryPermissions();
    }

    function _setTradeFactoryPermissions() internal virtual {
        IERC20(MORPHO_TOKEN).safeApprove(tradeFactory, type(uint96).max);
        ITradeFactory tf = ITradeFactory(tradeFactory);
        tf.enable(MORPHO_TOKEN, address(want));
    }

    function removeTradeFactoryPermissions() external onlyEmergencyAuthorized {
        _removeTradeFactoryPermissions();
    }

    function _removeTradeFactoryPermissions() internal virtual {
        IERC20(MORPHO_TOKEN).safeApprove(tradeFactory, 0);
        tradeFactory = address(0);
    }
}
