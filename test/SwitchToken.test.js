const { expect } = require("chai");
const { ether, expectRevert } = require('@openzeppelin/test-helpers');
const {
    address,
    minerStart,
    minerStop,
    mineBlock
} = require('./Utils/Ethereum');

const EIP712 = require('./Utils/EIP712');

const Switch = artifacts.require("Switch");

contract('Switch', accounts => {
    const name = 'Polkaswitch';
    const symbol = 'SWITCH';
    const secretKey = "cd3376bb711cb332ee3fb2ca04c6a8b9f70c316fcdf7a1f44ef4c7999483295f";
    const cap = ether('100000000');

    let root, a1, a2, otherAccounts, chainId;
    let switchToken;

    beforeEach(async () => {
        [root, a1, a2, ...otherAccounts] = accounts;
        chainId = 1337; //await web3.eth.net.getId(); See: https://github.com/trufflesuite/ganache-core/issues/515
        switchToken = await Switch.new();
    });

    describe('metadata', () => {
        it('has given name', async () => {
            expect(await switchToken.name()).to.equal(name);
        });

        it('has given symbol', async () => {
            expect(await switchToken.symbol()).to.equal(symbol);
        });
    });

    describe('balanceOf', () => {
        it('grants to initial account', async () => {
            await switchToken.mint(root, cap.toString());
            let balance = await switchToken.balanceOf(root);
            expect(balance.toString()).to.equal(cap.toString());
        });

        it('Cannot grants more', async() => {
            let exceedCap = ether('100000001');
            await expectRevert(switchToken.mint(root, exceedCap.toString()), 'revert SWITCH::mint: cap exceeded');
        });
    });

    //TODO: Test Mint and Burn

    describe('delegateBySig', () => {
        const Domain = (switchToken) => ({ name, chainId, verifyingContract: switchToken.address });
        const Types = {
            Delegation: [
                { name: 'delegatee', type: 'address' },
                { name: 'nonce', type: 'uint256' },
                { name: 'expiry', type: 'uint256' }
            ]
        };

        it('reverts if the signatory is invalid', async () => {
            const delegatee = root, nonce = 0, expiry = 0;
            await expectRevert(switchToken.delegateBySig(delegatee, nonce, expiry, 0, '0xbad', '0xbad'), 'revert SWITCH::delegateBySig: invalid signature');
        });

        it('reverts if the nonce is bad ', async () => {
            const delegatee = root, nonce = 1, expiry = 0;
            const { v, r, s } = EIP712.sign(Domain(switchToken), 'Delegation', { delegatee, nonce, expiry }, Types, Buffer.from(secretKey, 'hex'));
            await expectRevert(switchToken.delegateBySig(delegatee, nonce, expiry, v, r, s), "revert SWITCH::delegateBySig: invalid nonce");
        });

        it('reverts if the signature has expired', async () => {
            const delegatee = root, nonce = 0, expiry = 0;
            const { v, r, s } = EIP712.sign(Domain(switchToken), 'Delegation', { delegatee, nonce, expiry }, Types, Buffer.from(secretKey, 'hex'));
            await expectRevert(switchToken.delegateBySig(delegatee, nonce, expiry, v, r, s), "revert SWITCH::delegateBySig: signature expired");
        });

        it('delegates on behalf of the signatory', async () => {
            const a1 = web3.eth.accounts.privateKeyToAccount(secretKey);

            const delegatee = root, nonce = 0, expiry = 10e9;
            const { v, r, s } = EIP712.sign(Domain(switchToken), 'Delegation', { delegatee, nonce, expiry }, Types, Buffer.from(secretKey, 'hex'));
            expect(await switchToken.delegates(a1.address)).to.equal(address(0));
            const tx = await switchToken.delegateBySig(delegatee, nonce, expiry, v, r, s);
            expect(tx.gasUsed < 80000);
            expect(await switchToken.delegates(a1.address)).to.equal(root);
        });
    });

    //TODO: Check numCheckPoints of mint and burn.
    describe('numCheckpoints', () => {
        it('returns the number of checkpoints for a delegate', async () => {
            let amount = ether('100');
            let guy = accounts[4];

            await switchToken.mint(root, cap);
            await switchToken.transfer(guy, amount, {from: root});

            let checkPoint = await switchToken.numCheckpoints(a1);
            expect(checkPoint.toString()).to.equal('0');

            let balance = await switchToken.balanceOf(guy);
            expect(balance.toString()).to.equal(amount.toString());

            const t1 = await switchToken.delegate(a1, {from: guy});
            checkPoint = await switchToken.numCheckpoints(a1);
            expect(checkPoint.toString()).to.equal('1');

            const t2 = await switchToken.transfer(a2, ether('10'), { from: guy });
            checkPoint = await switchToken.numCheckpoints(a1);
            expect(checkPoint.toString()).to.equal('2');

            const t3 = await switchToken.transfer(a2, ether('10'), { from: guy });
            checkPoint = await switchToken.numCheckpoints(a1);
            expect(checkPoint.toString()).to.equal('3');

            const t4 = await switchToken.transfer(guy, ether('20'), { from: root });
            checkPoint = await switchToken.numCheckpoints(a1);
            expect(checkPoint.toString()).to.equal('4');

            let cp = await switchToken.checkpoints(a1, 0);
            expect(cp.fromBlock.toString()).to.equal(t1.receipt.blockNumber.toString());
            expect(cp.votes.toString()).to.equal(ether('100').toString());

            cp = await switchToken.checkpoints(a1, 1);
            expect(cp.fromBlock.toString()).to.equal(t2.receipt.blockNumber.toString());
            expect(cp.votes.toString()).to.equal(ether('90').toString());

            cp = await switchToken.checkpoints(a1, 2);
            expect(cp.fromBlock.toString()).to.equal(t3.receipt.blockNumber.toString());
            expect(cp.votes.toString()).to.equal(ether('80').toString());

            cp = await switchToken.checkpoints(a1, 3);
            expect(cp.fromBlock.toString()).to.equal(t4.receipt.blockNumber.toString());
            expect(cp.votes.toString()).to.equal(ether('100').toString());
        });

        it('does not add more than one checkpoint in a block', async () => {
            let amount = ether('100');
            let guy = accounts[4];

            await switchToken.mint(root, cap);
            await switchToken.transfer.sendTransaction(guy, amount, {from: root});

            let checkPoint = await switchToken.numCheckpoints(a1);
            expect(checkPoint.toString()).to.equal('0');
            await minerStop();

            let t1 = switchToken.delegate.sendTransaction(a1, {from: guy});
            let t2 = switchToken.transfer.sendTransaction(a2, ether('10'), { from: guy });
            let t3 = switchToken.transfer.sendTransaction(a2, ether('10'), { from: guy });

            new Promise(resolve => setTimeout(resolve, 1000));

            await minerStart();
            t1 = await t1;
            t2 = await t2;
            t3 = await t3;

            checkPoint = await switchToken.numCheckpoints(a1);
            expect(checkPoint.toString()).to.equal('1');

            let cp = await switchToken.checkpoints(a1, 0);
            expect(cp.fromBlock.toString()).to.equal(t1.receipt.blockNumber.toString());
            expect(cp.votes.toString()).to.equal(ether('80').toString());

            cp = await switchToken.checkpoints(a1, 1);
            expect(cp.fromBlock.toString()).to.equal('0');
            expect(cp.votes.toString()).to.equal('0');

            cp = await switchToken.checkpoints(a1, 2);
            expect(cp.fromBlock.toString()).to.equal('0');
            expect(cp.votes.toString()).to.equal('0');

            const t4 = await switchToken.transfer(guy, ether('20'), { from: root });

            checkPoint = await switchToken.numCheckpoints(a1);
            expect(checkPoint.toString()).to.equal('2');

            cp = await switchToken.checkpoints(a1, 1);
            expect(cp.fromBlock.toString()).to.equal(t4.receipt.blockNumber.toString());
            expect(cp.votes.toString()).to.equal(ether('100').toString());
        });
    });

    describe('getPriorVotes', () => {
        it('reverts if block number >= current block', async () => {
            await expectRevert(switchToken.getPriorVotes(a1, 5e10), "revert SWITCH::getPriorVotes: not yet determined");
        });

        it('returns 0 if there are no checkpoints', async () => {
            const pv = await switchToken.getPriorVotes(a1, 0);
            expect(pv.toString()).to.equal('0');
        });

        it('returns the latest block if >= last checkpoint block', async () => {
            await switchToken.mint(root, cap);

            const t1 = await switchToken.delegate(a1, {from: root});
            await mineBlock();
            await mineBlock();

            let pv = await switchToken.getPriorVotes(a1, t1.receipt.blockNumber);
            expect(pv.toString()).to.equal('100000000000000000000000000');

            pv = await switchToken.getPriorVotes(a1, t1.receipt.blockNumber + 1);
            expect(pv.toString()).to.equal('100000000000000000000000000');
        });

        it('returns zero if < first checkpoint block', async () => {
            await switchToken.mint(root, cap);

            await mineBlock();
            const t1 = await switchToken.delegate(a1, {from: root});
            await mineBlock();
            await mineBlock();

            let pv = await switchToken.getPriorVotes(a1, t1.receipt.blockNumber - 1);
            expect(pv.toString()).to.equal('0');
            pv = await switchToken.getPriorVotes(a1, t1.receipt.blockNumber + 1)
            expect(pv.toString()).to.equal('100000000000000000000000000');
        });

        it('generally returns the voting balance at the appropriate checkpoint', async () => {
            await switchToken.mint(root, cap);

            const t1 = await switchToken.delegate(a1, {from: root});
            await mineBlock();
            await mineBlock();
            const t2 = await switchToken.transfer(a2, ether('10'), { from: root});
            await mineBlock();
            await mineBlock();
            const t3 = await switchToken.transfer(a2, ether('10'), { from: root});
            await mineBlock();
            await mineBlock();
            const t4 = await switchToken.transfer(root, ether('20'), { from: a2});
            await mineBlock();
            await mineBlock();

            let pv = await switchToken.getPriorVotes(a1, t1.receipt.blockNumber - 1);
            expect(pv.toString()).to.equal('0');

            pv = await switchToken.getPriorVotes(a1, t1.receipt.blockNumber);
            expect(pv.toString()).to.equal('100000000000000000000000000');

            pv = await switchToken.getPriorVotes(a1, t1.receipt.blockNumber + 1);
            expect(pv.toString()).to.equal('100000000000000000000000000');

            pv = await switchToken.getPriorVotes(a1, t2.receipt.blockNumber);
            expect(pv.toString()).to.equal('99999990000000000000000000');

            pv = await switchToken.getPriorVotes(a1, t2.receipt.blockNumber + 1);
            expect(pv.toString()).to.equal('99999990000000000000000000');

            pv = await switchToken.getPriorVotes(a1, t3.receipt.blockNumber);
            expect(pv.toString()).to.equal('99999980000000000000000000');

            pv = await switchToken.getPriorVotes(a1, t3.receipt.blockNumber + 1);
            expect(pv.toString()).to.equal('99999980000000000000000000');


            pv = await switchToken.getPriorVotes(a1, t4.receipt.blockNumber);
            expect(pv.toString()).to.equal('100000000000000000000000000');

            pv = await switchToken.getPriorVotes(a1, t4.receipt.blockNumber + 1);
            expect(pv.toString()).to.equal('100000000000000000000000000');
        });
    });
});