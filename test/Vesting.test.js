const { expect } = require("chai");
const { ether, expectRevert, time } = require('@openzeppelin/test-helpers');
const {
    increaseTime,
    address
} = require('./Utils/Ethereum');

const Switch = artifacts.require("Switch");
const Vesting = artifacts.require("Vesting");

const oneYearInSeconds = time.duration.days(365);
const thirtySixMonthsInSeconds = time.duration.days(1080);

contract('Vesting', accounts => {
    let vesting;
    let switchToken;
    let now;
    const cap = ether('40000000');

    beforeEach(async () => {
        [root, tokenRoot, a1, a2, a3, ...otherAccounts] = accounts;
        switchToken = await Switch.new({from: tokenRoot});
        vesting = await Vesting.new(true, switchToken.address, {from: root});

        await switchToken.mint(tokenRoot, cap.toString(), {from: tokenRoot});
        await switchToken.transfer(vesting.address, cap, {from: tokenRoot});

        now = (await time.latest()).toNumber();
    });

    describe('revocable', () => {
        it('reflects correct revocable status', async () => {
            expect(await vesting.revocable()).to.equal(true);

        });

        it('cannot change revocable status if not owner', async () => {
            await expectRevert(vesting.finalizeContract({from: a1}), 'revert Ownable: caller is not the owner');
        });

        it('owner can change revocable status', async () => {
            await vesting.finalizeContract();
            expect(await vesting.revocable()).to.equal(false);
        })
    });

    describe('beneficiary', () => {
        it('can add beneficiary', async () => {
            //1 year cliff with 36 months vesting schedule.
            await vesting.addBeneficiary(a1, now, oneYearInSeconds, thirtySixMonthsInSeconds, ether('15000000'), 0);
            expect((await vesting.start(a1)).toNumber()).to.equal(now);
            expect((await vesting.duration(a1, {from: a1})).toNumber()).to.equal(thirtySixMonthsInSeconds.toNumber());
            expect((await vesting.cliff(a1)).toNumber()).to.equal(now + oneYearInSeconds.toNumber());
        });

        it('cannot add zero address as beneficiary', async () => {
            await expectRevert(vesting.addBeneficiary(address(0), now, oneYearInSeconds, thirtySixMonthsInSeconds, ether('15000000'), 0),
                "Vesting: beneficiary is the zero address");
        });

        it('cannot add 0 duration', async () => {
            await expectRevert(vesting.addBeneficiary(a1, now, oneYearInSeconds, 0, ether('15000000'), 0),
                "Vesting: duration is 0");
        });

        it('cannot add beneficiary if duraing is less than cliffDuration', async () => {
            await expectRevert(vesting.addBeneficiary(a1, now, thirtySixMonthsInSeconds, oneYearInSeconds, ether('15000000'), 0),
                "Vesting: cliff is longer than duration");
        });
    });

    describe('claim', () => {
        it('can claim upfront tokens', async () => {
            //1 year cliff with 36 months vesting schedule. 15% upfront
            let upfront = ether('2250000');
            await vesting.addBeneficiary(a1, now, oneYearInSeconds, thirtySixMonthsInSeconds, ether('15000000'), upfront);
            expect((await switchToken.balanceOf(a1)).toString()).to.equal('0');
            switchToken.approve(a1, upfront);
            await vesting.claim({from: a1});
            expect((await switchToken.balanceOf(a1)).toString()).to.equal(upfront.toString());
        });

        it('cannot claim upfront tokesn again', async () => {
            //1 year cliff with 36 months vesting schedule. 15% upfront
            let upfront = ether('2250000');
            await vesting.addBeneficiary(a1, now, oneYearInSeconds, thirtySixMonthsInSeconds, ether('15000000'), upfront);
            await vesting.claim({from: a1});
            await expectRevert(vesting.claim({from: a1}), "Vesting: token already claimed");
        });
    });

    describe('release', () => {
        it('cannot release token during cliff period', async () => {
            let upfront = ether('2250000');
            await vesting.addBeneficiary(a1, now, oneYearInSeconds, thirtySixMonthsInSeconds, ether('15000000'), upfront);
            expect((await vesting.released(a1)).toString()).to.equal('0')
            await expectRevert(vesting.release({from: a1}), "Vesting: no tokens are due");
        });

        it('can release token after cliff', async () => {
            let upfront = ether('225');
            let amount = ether('1500');
            await vesting.addBeneficiary(a2, now, oneYearInSeconds, thirtySixMonthsInSeconds, amount, upfront);
            expect((await vesting.released(a2)).toString()).to.equal('0');
            await increaseTime(oneYearInSeconds.toNumber() + time.duration.days(60).toNumber());
            await vesting.release({from: a2});
            // let expectN = (amount - upfront) / (thirtySixMonthsInSeconds.toNumber() - oneYearInSeconds.toNumber()) * time.duration.days(30).toNumber();
            expect((await vesting.released(a2)).toString()).to.equal('110869565217391304347');
            expect((await switchToken.balanceOf(a2)).toString()).to.equal('110869565217391304347');
        });

        it('can release all token after duration', async () => {
            let upfront = ether('225');
            let amount = ether('1500');
            await vesting.addBeneficiary(a3, now, oneYearInSeconds, thirtySixMonthsInSeconds, amount, upfront);
            expect((await vesting.released(a3)).toString()).to.equal('0');
            await increaseTime(oneYearInSeconds.toNumber() + thirtySixMonthsInSeconds.toNumber());
            await vesting.release({from: a3});
            let expectR = amount - upfront;
            expect((await vesting.released(a3)).toString()).to.equal(expectR.toLocaleString('fullwide', {useGrouping:false}));
        });
    });
});