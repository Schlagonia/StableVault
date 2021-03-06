from pathlib import Path
import click

from brownie import Vault, BeefMaster, YakAttack, StrategyLib, accounts, config, network, project, web3
from eth_utils import is_checksum_address
from brownie.network.gas.strategies import LinearScalingStrategy


API_VERSION = config["dependencies"][0].split("@")[-1]
"""
Vault = project.load(
    Path.home() / ".brownie" / "packages" / config["dependencies"][0]
).Vault
"""
#Variables
vault = Vault.at('0xDecdE3D0e1367155b62DCD497B0A967D6aa41Afd')
lib = StrategyLib.at('0xDB5f0fcfb3428B3e256E4a8e36Af9457866b6e7d')
acct = accounts.add('')
beefVault = '0xEbdf71f56BB3ae1D145a4121d0DDCa5ABEA7a946'
beef = BeefMaster.at('0x19284d07aab8Fa6B8C9B29F9Bc3f101b2ad5f661')
yakFarm = '0xf5Ac502C3662c07489662dE5f0e127799D715E1E'

gas_strategy = LinearScalingStrategy("30 gwei", "100 gwei", 1.1)


param = { 'from': acct, 'gas_price': gas_strategy }


def main():
    print(f"You are using the '{network.show_active()}' network")
    #dev = accounts.load(click.prompt("Account", type=click.Choice(accounts.load())))
    dev = acct
    print(f"You are using: 'dev' [{dev.address}]")

    if input("Is there a Vault for this strategy already? y/[N]: ").lower() != "n":
        click.echo(f"Using vualt at [{vault.address}]")
    else:
        return  # TODO: Deploy one using scripts from Vault project

    print(
        f"""
    Strategy Parameters
       api: {API_VERSION}
     token: {vault.token()}
      name: '{vault.name()}'
    symbol: '{vault.symbol()}'
    """
    )
    print('API version: ', vault.apiVersion())
    if input("Deploy Strategy? y/[N]: ").lower() != "y":
        return

    #lib = StrategyLib.deploy( param )
    #print('Library deployed to ', lib.address )
    strategy = YakAttack.deploy(vault, yakFarm, param)

    print("Strategy Deployed: ", strategy.address)

    #Adjust the debt ratio in order to add new strat
    vault.updateStrategyDebtRatio(beef.address, 4900, param)

    strategy = strategy.address       # Your strategy address
    debt_ratio = 4900                 # 98%
    minDebtPerHarvest = 0             # Lower limit on debt add
    maxDebtPerHarvest = 2 ** 256 - 1  # Upper limit on debt add
    performance_fee = 1000            # Strategist perf fee: 10%

    tx = vault.addStrategy(
        strategy, 
        debt_ratio, 
        minDebtPerHarvest,
        maxDebtPerHarvest,
        performance_fee, 
        param
    )

    print('Strategy added to Vault')