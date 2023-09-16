// SPDX-Licesne-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "lib/forge-std/src/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import {Script, console} from "lib/forge-std/src/Script.sol";

contract DSCEngineTest is Test {
    error DSCEngineTest__xIsZero();

    DeployDSC public deployer;
    DecentralizedStableCoin public dsc;
    DSCEngine public dsce;
    HelperConfig public helperConfig;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployerKey;

    address public fakeTestAddress = 0x694aA1769357215De4fAc081Bf1F309ADC325303;

    address public user = address(1);
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant AMOUNT_DSCTOMINT = 100 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint(user, STARTING_ERC20_BALANCE);
    }
    ///////////////////////
    // Constructor Tests //
    ///////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertIfTokenLengthDoesntMatchPriceeFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /////////////////
    // Price Tests //
    /////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000/ETH = 30,000e18
        uint256 expectedEthUsdValue = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedEthUsdValue, actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        // $2,000 / ETH, 100 USD
        uint256 expectedWethAmount = 0.05 ether;
        uint256 actualWethAmount = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWethAmount, actualWethAmount);
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertswithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", user, AMOUNT_COLLATERAL);
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralWithoutMinting() public depositedCollateral {
        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, 0);
    }

    function testCanDepositedCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(user);
        uint256 expectedDepositedAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        console.log(expectedDepositedAmount);
        assertEq(totalDscMinted, 0);
        assertEq(expectedDepositedAmount, AMOUNT_COLLATERAL);
    }

    modifier depositedAndMintedCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSCTOMINT);
        vm.stopPrank();
        _;
    }

    function testDepostCollateralAndMintDsc() public depositedAndMintedCollateral {
        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, AMOUNT_DSCTOMINT);
    }

    function testRedeemCollateralForDsc() public depositedAndMintedCollateral {
        vm.startPrank(user);
        dsc.approve(address(dsce), AMOUNT_DSCTOMINT);
        dsce.redeemCollateralForDsc(weth, 1 ether, AMOUNT_DSCTOMINT);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, 0);
    }

    function testRedeemCollateral() public depositedCollateral {
        vm.startPrank(user);
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);

        uint256 userBalance = ERC20Mock(weth).balanceOf(user);
        assertEq(userBalance, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testMintDsc() public depositedCollateral {
        vm.startPrank(user);
        dsc.approve(address(dsce), AMOUNT_DSCTOMINT);
        dsce.mintDsc(AMOUNT_DSCTOMINT);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, AMOUNT_DSCTOMINT);
    }
}
