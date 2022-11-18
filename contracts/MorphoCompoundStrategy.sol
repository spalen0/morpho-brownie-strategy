// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./MorphoStrategy.sol";
import "../interfaces/IUniswapV2Router01.sol";
import "../interfaces/lens/ILensCompound.sol";
import "../interfaces/ySwap/ITradeFactory.sol";

contract MorphoCompoundStrategy is MorphoStrategy {
    // ySwap TradeFactory:
    address public tradeFactory;
    // Router used for swapping reward token (COMP)
    IUniswapV2Router01 public currentV2Router;
    // Minimum amount of COMP to be claimed or sold
    uint256 public minCompToClaimOrSell = 0.1 ether;

    address private constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IUniswapV2Router01 private constant UNI_V2_ROUTER =
        IUniswapV2Router01(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IUniswapV2Router01 private constant SUSHI_V2_ROUTER =
        IUniswapV2Router01(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);

    // use aave metric for seconds per year: https://docs.aave.com/developers/v/2.0/guides/apy-and-apr#compute-data
    // block per year = seconds per year / 4 = 31536000 / 4 = 2628000
    uint256 private constant BLOCKS_PER_YEAR = 2628000;

    constructor(
        address _vault,
        address _poolToken,
        string memory _strategyName
    )
        public
        MorphoStrategy(
            _vault,
            _poolToken,
            _strategyName,
            0x8888882f8f843896699869179fB6E4f7e3B58888,
            0x930f1b46e1D081Ec1524efD95752bE3eCe51EF67
        )
    {
        currentV2Router = SUSHI_V2_ROUTER;
        IERC20 comp = IERC20(COMP);
        // COMP max allowance is uint96
        comp.safeApprove(address(SUSHI_V2_ROUTER), type(uint96).max);
        comp.safeApprove(address(UNI_V2_ROUTER), type(uint96).max);
    }

    // ---------------------- MorphoStrategy overriden contract function ----------------
    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        claimComp();
        sellComp();

        return super.prepareReturn(_debtOutstanding);
    }

    function prepareMigration(address _newStrategy) internal override {
        super.prepareMigration(_newStrategy);

        claimComp();
        IERC20 comp = IERC20(COMP);
        comp.safeTransfer(_newStrategy, comp.balanceOf(address(this)));
    }

    function getSupplyBalancesForAmount(uint256 _amount)
        public
        view
        override
        returns (
            uint256 _balanceInP2P,
            uint256 _balanceOnPool,
            uint256 _apr
        )
    {
        uint256 nextSupplyRatePerBlock;
        (
            nextSupplyRatePerBlock,
            _balanceOnPool,
            _balanceInP2P,

        ) = ILensCompound(address(lens)).getNextUserSupplyRatePerBlock(
            poolToken,
            address(this),
            _amount
        );
        _apr = nextSupplyRatePerBlock.mul(BLOCKS_PER_YEAR);
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {
        address[] memory superProtected = super.protectedTokens();
        address[] memory protected = new address[](superProtected.length + 1);
        for (uint256 i = 0; i < superProtected.length; i++) {
            protected[i] = superProtected[i];
        }
        protected[protected.length - 1] = COMP;
        return protected;
    }

    // ---------------------- functions for claiming reward token COMP ------------------
    function claimComp() internal {
        address[] memory pools = new address[](1);
        pools[0] = poolToken;
        if (
            lens.getUserUnclaimedRewards(pools, address(this)) >
            minCompToClaimOrSell
        ) {
            // claim the underlying pool's rewards, currently COMP token
            morpho.claimRewards(pools, false);
        }
    }

    // ---------------------- functions for selling reward token COMP -------------------
    /**
     * @notice
     *  Set toggle v2 swap router between sushiv2 and univ2
     */
    function setToggleV2Router() external onlyAuthorized {
        currentV2Router = currentV2Router == SUSHI_V2_ROUTER
            ? UNI_V2_ROUTER
            : SUSHI_V2_ROUTER;
    }

    /**
     * @notice
     *  Set the minimum amount of compount token need to claim or sell it for `want` token.
     */
    function setMinCompToClaimOrSell(uint256 _minCompToClaimOrSell)
        external
        onlyAuthorized
    {
        minCompToClaimOrSell = _minCompToClaimOrSell;
    }

    function sellComp() internal {
        if (tradeFactory == address(0)) {
            uint256 compBalance = IERC20(COMP).balanceOf(address(this));
            if (compBalance > minCompToClaimOrSell) {
                currentV2Router.swapExactTokensForTokens(
                    compBalance,
                    0,
                    getTokenOutPathV2(COMP, address(want)),
                    address(this),
                    block.timestamp
                );
            }
        }
    }

    function getTokenOutPathV2(address _tokenIn, address _tokenOut)
        internal
        pure
        returns (address[] memory _path)
    {
        bool isWeth = _tokenIn == address(WETH) || _tokenOut == address(WETH);
        _path = new address[](isWeth ? 2 : 3);
        _path[0] = _tokenIn;

        if (isWeth) {
            _path[1] = _tokenOut;
        } else {
            _path[1] = address(WETH);
            _path[2] = _tokenOut;
        }
    }

    // ---------------------- YSWAPS FUNCTIONS ----------------------
    function setTradeFactory(address _tradeFactory) external onlyGovernance {
        if (tradeFactory != address(0)) {
            _removeTradeFactoryPermissions();
        }
        IERC20(COMP).safeApprove(_tradeFactory, type(uint96).max);
        ITradeFactory tf = ITradeFactory(_tradeFactory);
        tf.enable(COMP, address(want));
        tradeFactory = _tradeFactory;
    }

    function removeTradeFactoryPermissions() external onlyEmergencyAuthorized {
        _removeTradeFactoryPermissions();
    }

    function _removeTradeFactoryPermissions() internal {
        IERC20(COMP).safeApprove(tradeFactory, 0);
        tradeFactory = address(0);
    }
}
