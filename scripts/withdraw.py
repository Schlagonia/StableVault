from pathlib import Path
import click

from brownie import Vault, Token, BeefMaster, StrategyLib, accounts, config, network, project, web3
from eth_utils import is_checksum_address
from brownie.network.gas.strategies import LinearScalingStrategy


#Variables
vault = Vault.at('0xDecdE3D0e1367155b62DCD497B0A967D6aa41Afd')
acct = accounts.add('')
beefVault = '0xEbdf71f56BB3ae1D145a4121d0DDCa5ABEA7a946'
gas_strategy = LinearScalingStrategy("30 gwei", "100 gwei", 1.1)
beef = BeefMaster.at('0x19284d07aab8Fa6B8C9B29F9Bc3f101b2ad5f661')
usdc = Token.at('0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664')

param = { 'from': acct, 'gas_price': gas_strategy }

def get_address(msg: str) -> str:
    while True:
        val = input(msg)
        if is_checksum_address(val):
            return val
        else:
            addr = web3.ens.address(val)
            if addr:
                print(f"Found ENS '{val}' [{addr}]")
                return addr
        print(f"I'm sorry, but '{val}' is not a checksummed address or ENS")


def main():
    print(f"You are using the '{network.show_active()}' network")
    #dev = accounts.load(click.prompt("Account", type=click.Choice(accounts.load())))
    dev = acct
    print(f"You are using: 'dev' [{dev.address}]")

    shares = vault.balanceOf(acct.address)
    print('Vault USDC balance: ', usdc.balanceOf(vault.address))
    print('Strategy usdc balance: ', usdc.balanceOf(beef.address))
    print('Acct usdc: ', usdc.balanceOf(acct.address))
    print('Account cvUSDC: ', vault.balanceOf(acct.address))
    tx = vault.withdraw(shares, param);
    print('Funds withdrawn')
    print('Vault USDC balance: ', usdc.balanceOf(vault.address))
    print('Strategy usdc balance: ', usdc.balanceOf(beef.address))
    print('Acct usdc: ', usdc.balanceOf(acct.address))
    print('Account cvUSDC: ', vault.balanceOf(acct.address))