// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import {Owned} from "../solmate/src/auth/Owned.sol";
import "./MockFixedTokens.sol";
import "../interfaces/IGTranche.sol";
import "../interfaces/IOracle.sol";

contract MockGTranche is IGTranche, MockFixedTokens, ReentrancyGuard, Owned {
    uint256 public utilisationThreshold = 5000;
    IOracle public immutable oracle;

    event LogNewDeposit(
        address indexed sender,
        address recipient,
        uint256 amount,
        uint256 indexed index,
        bool indexed tranche
    );

    event LogNewWithdrawal(
        address indexed sender,
        address recipient,
        uint256 amount,
        uint256 indexed index,
        bool indexed tranche
    );

    event LogNewRatio(uint256 newRatio);

    constructor(
        address[] memory _yieldTokens,
        address[2] memory _trancheTokens,
        address _oracle
    ) MockFixedTokens(_yieldTokens, _trancheTokens) Owned(msg.sender) {
        oracle = IOracle(_oracle);
    }

    /////////////////////////////// setters ////////////////////////////////////////////////
    function setUtilisationRatio(uint256 _newRatio) external onlyOwner {
        utilisationThreshold = _newRatio;
        emit LogNewRatio(_newRatio);
    }

    /////////////////////////////// DEPOSIT / WITHDRAW FLOWS ////////////////////////////////////////////////
    function deposit(
        uint256 _amount,
        uint256 _index,
        bool _tranche,
        address _recipient
    ) external override returns (uint256, uint256) {
        ERC4626 token = ERC4626(getYieldToken(_index));
        token.transferFrom(msg.sender, address(this), _amount);
        GToken trancheToken = getTrancheToken(_tranche);
        uint256 factor = trancheToken.factor();

        token_balances[_index] += _amount;

        uint256 calc_amount = _calcTokenValue(_index, _amount, true);
        tranche_balances[_tranche] += calc_amount;
        if (_tranche)
            require(utilisation() <= utilisationThreshold, "!utilisation");
        trancheToken.mint(_recipient, trancheToken.factor(), calc_amount);
        uint256 trancheAmount;
        if (_tranche) trancheAmount = calc_amount;
        else trancheAmount = (calc_amount * factor) / DEFAULT_FACTOR;
        emit LogNewDeposit(msg.sender, _recipient, _amount, _index, _tranche);
        return (trancheAmount, calc_amount);
    }

    function withdraw(
        uint256 _amount,
        uint256 _index,
        bool _tranche,
        address _recipient
    ) external override returns (uint256, uint256) {
        GToken trancheToken = getTrancheToken(_tranche);
        require(_amount <= trancheToken.balanceOf(msg.sender));

        ERC4626 token = ERC4626(getYieldToken(_index));
        uint256 calc_amount = _calcTokenValue(_index, _amount, false);

        trancheToken.burn(msg.sender, trancheToken.factor(), calc_amount);
        tranche_balances[_tranche] -= calc_amount;
        if (!_tranche) require(utilisation() <= utilisationThreshold);
        token_balances[_index] -= _amount;
        token.transfer(msg.sender, _amount);
        emit LogNewWithdrawal(
            msg.sender,
            _recipient,
            _amount,
            _index,
            _tranche
        );
        return (_amount, calc_amount);
    }

    // TODO price yieldTokens and trancheTokens against each other
    function _calcTokenValue(
        uint256 _index,
        uint256 _amount,
        bool _deposit
    ) public view returns (uint256) {
        return
            oracle.getSinglePrice(
                _index,
                getYieldTokenValue(_index, _amount),
                _deposit
            );
    }

    /////////////////////////////// PNL ////////////////////////////////////////////////
    function utilisation() public view returns (uint256) {
        return
            (tranche_balances[SENIOR_TRANCHE_ID] * DEFAULT_DECIMALS) /
            (tranche_balances[JUNIOR_TRANCHE_ID] + 1);
    }

    function _calcUtilisation() internal view returns (uint256) {
        uint256[NO_OF_TRANCHES] memory _totalValue = _calcTotalValue();
        return (_totalValue[1] * DEFAULT_DECIMALS) / _totalValue[0];
    }

    function _calcTotalValue()
        internal
        view
        returns (uint256[NO_OF_TRANCHES] memory trancheAssets)
    {
        return pnlDistribution();
    }

    function pnlDistribution()
        public
        view
        returns (uint256[NO_OF_TRANCHES] memory _tranche_balances)
    {
        uint256 totalValue = _calcUnfiedValue();
        _tranche_balances[0] = tranche_balances[JUNIOR_TRANCHE_ID];
        _tranche_balances[1] = tranche_balances[SENIOR_TRANCHE_ID];
        uint256 currentTotal = _tranche_balances[0] + _tranche_balances[1];
        if (currentTotal > totalValue) {
            if (currentTotal - totalValue > _tranche_balances[0]) {
                _tranche_balances[0] -= 0;
                _tranche_balances[1] =
                    currentTotal -
                    totalValue -
                    _tranche_balances[0];
            } else {
                _tranche_balances[0] -= currentTotal - totalValue;
            }
        } else if (currentTotal < totalValue) {
            uint256 _utilisation = (_tranche_balances[1] * DEFAULT_DECIMALS) /
                _tranche_balances[0];
            uint256[NO_OF_TRANCHES] memory profits = _distributeProfit(
                totalValue - currentTotal,
                _utilisation
            );
            _tranche_balances[0] += profits[0];
            _tranche_balances[1] += profits[1];
        }
    }

    // Not used in mock
    function finalizeMigration() external override {}

    // TODO update default profit distribution curve
    function _distributeProfit(uint256 _amount, uint256 _utilisation)
        internal
        pure
        returns (uint256[NO_OF_TRANCHES] memory profit)
    {
        uint256 juniorProfit = (_amount * _utilisation) / DEFAULT_DECIMALS;
        uint256 seniorProfit = _amount - juniorProfit;

        if (_utilisation > 10000) _utilisation = 10000;
        else if (_utilisation < 8000)
            _utilisation = (_utilisation * 3) / 8 + 3000;
        else _utilisation = (_utilisation - 8000) * 2 + 6000;

        uint256 profitFromSeniorTranche = (seniorProfit * _utilisation) / 10000;
        profit[0] = juniorProfit + profitFromSeniorTranche;
        profit[1] = seniorProfit - profitFromSeniorTranche;
    }

    /////////////////////////////// Swapping ////////////////////////////////////////////////
    // TODO implement bonding curve
    function _calcUnfiedValue() internal view returns (uint256 totalValue) {
        uint256[NO_OF_TOKENS] memory yieldTokenValues = getYieldTokenValues();
        uint256[] memory tokenValues = new uint256[](NO_OF_TOKENS);
        for (uint256 i; i < NO_OF_TOKENS; ++i) {
            tokenValues[i] = yieldTokenValues[i];
        }
        totalValue = oracle.getTotalValue(tokenValues);
    }

    /////////////////////////////// LEGACY ////////////////////////////////////////////////
    function gTokenTotalAssets() external view returns (uint256) {
        if (msg.sender == JUNIOR_TRANCHE)
            return tranche_balances[JUNIOR_TRANCHE_ID];
        else if (msg.sender == SENIOR_TRANCHE)
            return tranche_balances[SENIOR_TRANCHE_ID];
        else
            return
                tranche_balances[JUNIOR_TRANCHE_ID] +
                tranche_balances[SENIOR_TRANCHE_ID];
    }
}
