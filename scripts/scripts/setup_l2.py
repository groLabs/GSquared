import os
from enum import Enum

from brownie import CurveOracle  # noqa
from brownie import GMigration  # noqa
from brownie import GRouter  # noqa
from brownie import GTranche  # noqa
from brownie import GVault  # noqa
from brownie import JuniorTranche  # noqa
from brownie import PnL  # noqa
from brownie import PnLFixedRate  # noqa
from brownie import RouterOracle  # noqa
from brownie import SeniorTranche  # noqa
from brownie import accounts
from brownie import web3  # noqa
from dotenv import load_dotenv
from rich.console import Console

from scripts.scripts.addresses import CHAINLINK_AGG_ADDRESSES
from scripts.scripts.addresses import THREE_POOL_ADDRESS
from scripts.scripts.addresses import THREE_POOL_TOKEN_ADDRESS

console = Console()
load_dotenv()

DEPLOYER = "deployer"
SILENT_DEPLOYMENT = True
PUBLISH_SOURCE = os.getenv("PUBLISH_SOURCE", False)


class Env(Enum):
    LOCAL = "local"
    TESTNET = "testnet"


def load_env() -> Env:
    if os.getenv('environment') == Env.LOCAL.value:
        return Env.LOCAL
    else:
        return Env.TESTNET


def load_pkey(account_name: str = DEPLOYER) -> str:
    """
    Load private key from env vars
    """
    env = load_env()  # type: Env
    if env == Env.LOCAL:
        with open(f"./{account_name}") as keyfile:
            encrypted_key = keyfile.read()
            pass_ = os.getenv(account_name)
            private_key = web3.eth.account.decrypt(encrypted_key, pass_)
        return accounts.add(private_key)
    else:
        web3.provider.make_request("hardhat_impersonateAccount", [os.getenv(account_name)])
        return accounts.at(os.getenv(account_name), force=True)


def deploy_to_l2() -> None:
    """
    Main script to deploy GRo protocol to L2
    """
    console.log("Deploying G2 protocol...", style="bold blue")
    deployer = accounts.at(load_pkey(account_name=DEPLOYER))
    console.log(f"Deploying with {deployer.address} account", style="bold blue")

    # Deploy GVault
    console.log("Deploying GVault...", style="bold yellow")
    gro_vault = deployer.deploy(
        GVault, THREE_POOL_TOKEN_ADDRESS, publish_source=False, silent=SILENT_DEPLOYMENT
    )
    console.log(f"GVault deployed at {gro_vault}", style="bold cyan")

    # Deploy GMigration
    console.log("Deploying GMigration...", style="bold yellow")
    gmigration = deployer.deploy(GMigration, gro_vault, publish_source=False,
                                 silent=SILENT_DEPLOYMENT)
    console.log(f"GMigration deployed at {gmigration}", style="bold cyan")

    # Deploy Curve Oracle
    console.log("Deploying Curve Oracle...", style="bold yellow")
    curve_oracle = deployer.deploy(CurveOracle, publish_source=False, silent=SILENT_DEPLOYMENT)
    console.log(f"Curve Oracle deployed at {curve_oracle}", style="bold cyan")

    # Deploy tokens, starting from Junior tranche:
    console.log("Deploying Junior Tranche...", style="bold yellow")
    jtranche = deployer.deploy(JuniorTranche, "Gro Vault Token", "GVT", publish_source=False,
                               silent=SILENT_DEPLOYMENT)
    console.log(f"Junior Tranche deployed at {jtranche}", style="bold cyan")

    # Now, deploy senior tranche
    console.log("Deploying Senior Tranche...", style="bold yellow")
    stranche = deployer.deploy(SeniorTranche, "PWRD Stablecoin", "PWRD", publish_source=False,
                               silent=SILENT_DEPLOYMENT)
    console.log(f"Senior Tranche deployed at {jtranche}", style="bold cyan")

    # Deploying GTranche and connecting all the dots:
    console.log("Deploying GTranche...", style="bold yellow")
    gtranche = deployer.deploy(
        GTranche,
        [gro_vault],
        [jtranche, stranche],
        curve_oracle,
        gmigration.address,
        publish_source=False, silent=SILENT_DEPLOYMENT
    )
    console.log(f"GTranche deployed at {gtranche}", style="bold cyan")

    console.log("Deploying RouterOracle", style="bold yellow")
    router_oracle = deployer.deploy(
        RouterOracle, CHAINLINK_AGG_ADDRESSES, publish_source=False,
        silent=SILENT_DEPLOYMENT
    )
    console.log(f"RouterOracle deployed at {router_oracle}", style="bold cyan")
    console.log("Deploying Gro Router", style="bold yellow")
    gro_router = deployer.deploy(
        GRouter,
        gtranche,
        gro_vault,
        router_oracle,
        THREE_POOL_ADDRESS,
        THREE_POOL_TOKEN_ADDRESS,
        publish_source=False,
        silent=SILENT_DEPLOYMENT
    )
    console.log(f"Gro Router deployed at {gro_router}", style="bold cyan")
    console.log("Deploying PnLFixedRate", style="bold yellow")
    pnl = deployer.deploy(
        PnLFixedRate, gtranche.address, publish_source=False,
        silent=SILENT_DEPLOYMENT)
    console.log(f"PnLFixedRate deployed at {pnl}", style="bold cyan")

    console.log(f"Setting PNL for Gtranche", style="bold yellow")
    gtranche.setPnL(pnl.address, {"from": deployer.address})
    console.log(f"PNL For Gtranche set at {pnl.address}", style="bold cyan")