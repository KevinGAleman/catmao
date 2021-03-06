const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Catmao", function () {
    var catmao;
    var owner, addr1, addr2, marketingWallet, devWallet;
    var router;
    var wbnb;
    var busd;
    const routerABI = require("./RouterABI.json");
    const wbnbABI = require("./WBNBABI.json");
    const busdABI = require("./BUSDABI.json");
    const pcsRouterAddress = "0x10ED43C718714eb63d5aA57B78B54704E256024E";
    const pcsRouterTestnetAddress = "0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3";
    const wbnbAddress = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
    const wbnbTestnetAddress = "0xae13d989dac2f0debff460ac112a837c89baa7cd";
    const liqPairTestnetAddress = "0x99002ff5b686e65bd01f18b5b536e57b1b73ee67";
    const busdAddress = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56";
    const busdTestnetAddress = "0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47";

    before(async function () {
        const catmaoFactory = await ethers.getContractFactory("Catmao");
        catmao = await catmaoFactory.deploy();
        await catmao.deployed();
        [owner, addr1, addr2, marketingWallet, devWallet] = await ethers.getSigners();
        router = new ethers.Contract(pcsRouterTestnetAddress, routerABI, owner);
        wbnb = await ethers.getContractAt(wbnbABI, wbnbTestnetAddress, owner);
        busd = await ethers.getContractAt(busdABI, busdTestnetAddress, owner);

    });

    it("Should be created with the appropriate token distribution", async function () {
        expect(await catmao.totalSupply()).to.equal(ethers.utils.parseUnits("1", 26));
        expect(await catmao.decimals()).to.equal(18);
        expect(await catmao._maxBalance()).to.equal(ethers.utils.parseUnits("2", 24));
        expect(await catmao._maxTx()).to.equal(ethers.utils.parseUnits("5", 23));
        expect(await catmao.name()).to.equal("Catmao");
        expect(await catmao.symbol()).to.equal("CATMAO");
    });

    it("Should be created with the correct fees", async function () {
        expect(await catmao._totalBuyTaxes()).to.equal(99);
        expect(await catmao._totalSellTaxes()).to.equal(99);
    });

    it("Should transfer appropriately", async function () {
        // Transfer 50 tokens from owner to addr1
        await catmao.transfer(addr1.address, 50);
        expect(await catmao.balanceOf(addr1.address)).to.equal(50);

        // Transfer 50 tokens from addr1 to addr2
        await catmao.connect(addr1).transfer(addr2.address, 50);
        expect(await catmao.balanceOf(addr2.address)).to.equal(50);
    });

    it("Should tax the hell out of bots before the launch happens and sell to the contract", async function () {
        // TODO: This is temporary because I don't have WBNB in the other accounts on testnet
        var wbnbTransferAmount = ethers.utils.parseUnits("1", 17);
        var wbnbPurchaseAmount = ethers.utils.parseUnits("1", 15);
        await wbnb.transfer(catmao.address, wbnbTransferAmount);
        await wbnb.transfer(addr1.address, wbnbTransferAmount);
        await wbnb.transfer(addr2.address, wbnbTransferAmount);

        await catmao.approve(pcsRouterTestnetAddress, ethers.utils.parseUnits("3", 24));
        await wbnb.approve(pcsRouterTestnetAddress, ethers.utils.parseUnits("1", 40));

        await router.addLiquidity(
            catmao.address,
            wbnbTestnetAddress,
            ethers.utils.parseUnits("3", 24),
            ethers.utils.parseUnits("5", 17),
            0,
            0,
            owner.address,
            Date.now() + 1000 * 60 * 10
        );

        for (var i = 0; i<7; i++) {
            await router.connect(addr1).swapExactETHForTokensSupportingFeeOnTransferTokens(
                0, 
                [wbnb.address, catmao.address], 
                addr1.address, 
                Date.now() + 1000 * 60 * 10, 
                {
                    'value': wbnbPurchaseAmount,
                    'gasLimit': 2140790,
                    'gasPrice': ethers.utils.parseUnits('10', 'gwei')
                }
            );
        }

        await catmao.connect(addr1).approve(pcsRouterTestnetAddress, ethers.utils.parseUnits("3", 24));
        await router.connect(addr1).swapExactTokensForETHSupportingFeeOnTransferTokens(
            await catmao.balanceOf(addr1.address), 
            0,
            [catmao.address, wbnb.address], 
            addr1.address, 
            Date.now() + 1000 * 60 * 10, 
            {
                'gasLimit': 2140790,
                'gasPrice': ethers.utils.parseUnits('10', 'gwei')
            }
        );
    });

    it("Should change fee percentages when called by the owner", async function () {
        await catmao.setBuyFees(1, 2, 5, 5, 2);
        await catmao.setSellFees(1, 2, 5, 5, 2);

        expect(await catmao._totalBuyTaxes()).to.equal(15);
        expect(await catmao._totalSellTaxes()).to.equal(15);
    });

    it("Should change max balance and max transaction percentages when called by the owner", async function () {
        await catmao.setMaxBalancePercentage(3);
        await catmao.setMaxTxPercentage(10);

        expect(await catmao._maxBalance()).to.equal(ethers.utils.parseUnits("3", 24));
        expect(await catmao._maxTx()).to.equal(ethers.utils.parseUnits("10", 23));
    });

    it("Should not tax the hell out of based buyers who wait for the launch signal", async function () {
        var wbnbPurchaseAmount = ethers.utils.parseUnits("1", 15);

        await router.connect(addr1).swapExactETHForTokensSupportingFeeOnTransferTokens(
            0, 
            [wbnb.address, catmao.address], 
            addr1.address, 
            Date.now() + 1000 * 60 * 10, 
            {
                'value': wbnbPurchaseAmount,
                'gasLimit': 2140790,
                'gasPrice': ethers.utils.parseUnits('10', 'gwei')
            }
        );

        await router.connect(addr1).swapExactTokensForETHSupportingFeeOnTransferTokens(
            await catmao.balanceOf(addr1.address), 
            0,
            [catmao.address, wbnb.address], 
            addr1.address, 
            Date.now() + 1000 * 60 * 10, 
            {
                'gasLimit': 2140790,
                'gasPrice': ethers.utils.parseUnits('10', 'gwei')
            }
        );
    });

    it("Should not allow a wallet to accumulate more than max balance", async function () {
        var wbnbPurchaseAmount = ethers.utils.parseUnits("15", 16);
        
        for (var i = 0; i<4; i++) {
            await router.connect(addr1).swapExactETHForTokensSupportingFeeOnTransferTokens(
                0, 
                [wbnb.address, catmao.address], 
                addr1.address, 
                Date.now() + 1000 * 60 * 10, 
                {
                    'value': wbnbPurchaseAmount,
                    'gasLimit': 2140790,
                    'gasPrice': ethers.utils.parseUnits('10', 'gwei')
                }
            );
        }

        expect(
            router.connect(addr1).swapExactETHForTokensSupportingFeeOnTransferTokens(
                0, 
                [wbnb.address, catmao.address], 
                addr1.address, 
                Date.now() + 1000 * 60 * 10, 
                {
                    'value': wbnbPurchaseAmount,
                    'gasLimit': 2140790,
                    'gasPrice': ethers.utils.parseUnits('10', 'gwei')
                }
            )
        ).to.be.revertedWith("");
    });

    it("Should now allow a wallet to buy/sell more than the max transaction", async function() {
        expect(
            router.connect(addr1).swapExactTokensForETHSupportingFeeOnTransferTokens(
                await catmao.balanceOf(addr1.address), 
                0,
                [catmao.address, wbnb.address], 
                addr1.address, 
                Date.now() + 1000 * 60 * 10, 
                {
                    'gasLimit': 2140790,
                    'gasPrice': ethers.utils.parseUnits('10', 'gwei')
                }
            )
        ).to.be.revertedWith("");

        await router.connect(addr1).swapExactTokensForETHSupportingFeeOnTransferTokens(
            ethers.utils.parseUnits("6", 22), 
            0,
            [catmao.address, wbnb.address], 
            addr1.address, 
            Date.now() + 1000 * 60 * 10, 
            {
                'gasLimit': 2140790,
                'gasPrice': ethers.utils.parseUnits('10', 'gwei')
            }
        );
    });

    it("Should not allow fees to be set higher than expected", async function () {
        await expect(catmao.setBuyFees(3, 3, 3, 3, 3)).to.be.revertedWith("");
        await expect(catmao.setSellFees(3, 3, 3, 3, 3)).to.be.revertedWith("");
        await expect(catmao.setBuyFees(1, 30, 30, 1, 1)).to.be.revertedWith("");
        await expect(catmao.setSellFees(1, 30, 30, 1, 1)).to.be.revertedWith("");

        expect(await catmao._totalBuyTaxes()).to.equal(15);
        expect(await catmao._totalSellTaxes()).to.equal(15);
    });

    it("Should not allow max transaction and max balance percentages to be set too low", async function () {
        await expect(catmao.setMaxBalancePercentage(1)).to.be.revertedWith("");
        await expect(catmao.setMaxTxPercentage(4)).to.be.revertedWith("");

        expect(await catmao._maxBalance()).to.equal(ethers.utils.parseUnits("3", 24));
        expect(await catmao._maxTx()).to.equal(ethers.utils.parseUnits("10", 23));
    });
});