import { ethers, BrowserProvider, Signer } from "ethers"
import { LimitOrder, OrderInfoData, MakerTraits, Address, Extension } from "@1inch/limit-order-sdk"
import { handleError, MarginTradingError, ErrorCodes, validateTokenAmount, validateLeverageRatio } from "@/utils/errorHandling"
import { SwapService } from "./swapService"
import { PositionMonitor, AavePosition } from "./positionMonitor"
import { RelayerService, RelayerQuote } from "./relayerService"
import { AAVE_V3_POOL, MARGIN_SETTLER_ADDRESS, USDC, WETH } from "@/shared/consts"

export interface MarginOrderParams {
    collateralToken: string
    debtToken: string
    collateralAmount: string
    debtAmount: string
    positionType: "long" | "short"
}

export interface OrderResult {
    orderHash: string
    extensionHash: string
    order: LimitOrder
    orderInfo: OrderInfoData
    extensionCalldata: string
    orderSignature: string
    extensionSignature: string
}

export class MarginService {
    private provider: BrowserProvider | null = null
    private signer: Signer | null = null
    private swapService: SwapService
    private positionMonitor: PositionMonitor
    private relayerService: RelayerService

    constructor() {
        this.swapService = new SwapService()
        this.positionMonitor = new PositionMonitor()
        this.relayerService = new RelayerService()
        this.initializeProvider()
    }

    private async initializeProvider() {
        if (typeof window !== "undefined" && window.ethereum) {
            this.provider = new BrowserProvider(window.ethereum)
            this.signer = await this.provider.getSigner()
        }
    }

    private createExtensionCalldata(user: string, collateralToken: string, debtToken: string): string {
        // Create the lending operations calldata following the FlashFill test pattern
        const aaveDepositCalldata = this.encodeAaveDeposit(collateralToken, AAVE_V3_POOL)
        const aaveBorrowCalldata = this.encodeAaveBorrow(debtToken, AAVE_V3_POOL)
        const operationsCalldata = ethers.concat([aaveDepositCalldata, aaveBorrowCalldata])

        // Create pre-interaction calldata with target, user, and operations
        const preInteractionCalldata = ethers.concat([
            MARGIN_SETTLER_ADDRESS, // target (20 bytes)
            user, // user (20 bytes)
            operationsCalldata, // operations calldata
        ])

        return preInteractionCalldata
    }

    private createExtension(user: string, collateralToken: string, debtToken: string): Extension {
        // Create pre-interaction data for margin operations
        const preInteractionData = this.createExtensionCalldata(user, collateralToken, debtToken)

        // Create extension with pre-interaction
        return new Extension({
            makerAssetSuffix: "0x",
            takerAssetSuffix: "0x",
            makingAmountData: "0x",
            takingAmountData: "0x",
            predicate: "0x",
            makerPermit: "0x",
            preInteraction: preInteractionData,
            postInteraction: "0x",
            customData: "0x",
        })
    }

    private encodeAaveDeposit(token: string, pool: string): string {
        // Encode Aave deposit operation following LendingEncoder.sol
        // ComposerCommands.LENDING = 0x30, LenderOps.DEPOSIT = 0, LenderIds.UP_TO_AAVE_V3 - 1 = 999
        const encoded = ethers.concat([
            ethers.toBeHex(0x30, 1), // ComposerCommands.LENDING
            ethers.toBeHex(0, 1), // LenderOps.DEPOSIT
            ethers.toBeHex(999, 2), // LenderIds.UP_TO_AAVE_V3 - 1 (uint16)
            token, // asset address (20 bytes)
            pool, // pool address (20 bytes)
        ])
        return ethers.hexlify(encoded)
    }

    private encodeAaveBorrow(token: string, pool: string): string {
        // Encode Aave borrow operation following LendingEncoder.sol
        // ComposerCommands.LENDING = 0x30, LenderOps.BORROW = 1, LenderIds.UP_TO_AAVE_V3 - 1 = 999
        const encoded = ethers.concat([
            ethers.toBeHex(0x30, 1), // ComposerCommands.LENDING
            ethers.toBeHex(1, 1), // LenderOps.BORROW
            ethers.toBeHex(999, 2), // LenderIds.UP_TO_AAVE_V3 - 1 (uint16)
            token, // asset address (20 bytes)
            pool, // pool address (20 bytes)
            ethers.toBeHex(2, 1), // interest rate mode (uint8) - variable rate
        ])
        return ethers.hexlify(encoded)
    }

    async createMarginOrder(params: MarginOrderParams): Promise<OrderResult> {
        if (!this.signer) {
            throw new MarginTradingError("Wallet not connected - please connect your wallet", ErrorCodes.WALLET_NOT_CONNECTED)
        }

        try {
            // Validate inputs
            validateTokenAmount(params.collateralAmount, 18) // WETH decimals
            validateTokenAmount(params.debtAmount, 6) // USDC decimals
            validateLeverageRatio(params.collateralAmount, params.debtAmount)

            // Validate token addresses
            if (!ethers.isAddress(params.collateralToken) || !ethers.isAddress(params.debtToken)) {
                throw new MarginTradingError("Invalid token addresses", ErrorCodes.INVALID_TOKEN_PAIR)
            }

            const userAddress = await this.signer.getAddress()

            // Create extension object with pre-interaction data
            const extension = this.createExtension(userAddress, params.collateralToken, params.debtToken)
            const extensionCalldata = extension.encode()

            // Create order info with proper salt generation
            const baseSalt = BigInt(Math.floor(Math.random() * 1000000))
            const orderInfo: OrderInfoData = {
                makerAsset: new Address(params.debtToken), // What we're selling (borrowing)
                takerAsset: new Address(params.collateralToken), // What we're buying (depositing)
                makingAmount: BigInt(ethers.parseUnits(params.debtAmount, 6)), // USDC has 6 decimals
                takingAmount: BigInt(ethers.parseUnits(params.collateralAmount, 18)), // WETH has 18 decimals
                maker: new Address(userAddress),
                receiver: new Address(userAddress),
                salt: LimitOrder.buildSalt(extension, baseSalt), // Proper salt generation
            }

            // Create maker traits with allowed sender restriction (only our relayer can fill)
            const relayerAddress = process.env.NEXT_PUBLIC_RELAYER_ADDRESS || process.env.RELAYER_ADDRESS
            let makerTraits = MakerTraits.default()

            // Set HAS_EXTENSION_FLAG since we have extension calldata
            makerTraits = makerTraits.withExtension()

            // Restrict to our relayer only if configured
            if (relayerAddress && relayerAddress !== "0x0000000000000000000000000000000000000000") {
                makerTraits = makerTraits.withAllowedSender(new Address(relayerAddress))
            }

            // Create and sign the order with extension
            const order = new LimitOrder(orderInfo, makerTraits, extension)
            const orderHash = order.getTypedData(42161)

            // Sign the order
            const orderSignature = await this.signer.signTypedData(orderHash.domain, orderHash.types, orderHash.message)

            // Create extension hash and get signature for pre-interaction validation
            const extensionHash = await this.hashExtension(extensionCalldata)
            const extensionSignature = await this.signer.signMessage(ethers.getBytes(extensionHash))

            return {
                orderHash: ethers.keccak256(ethers.toUtf8Bytes(JSON.stringify(orderHash))),
                extensionHash: extensionHash,
                order: order,
                orderInfo: orderInfo,
                extensionCalldata: extensionCalldata,
                orderSignature: orderSignature,
                extensionSignature: extensionSignature,
            }
        } catch (error) {
            throw handleError(error, "creating margin order")
        }
    }

    private async hashExtension(extensionCalldata: string): Promise<string> {
        // This should match the MarginSettler.hashExtension function
        // For now, return a simple keccak256 hash
        return ethers.keccak256(extensionCalldata)
    }

    async getPositions(userAddress: string) {
        // Fetch positions from Aave V3 with detailed monitoring
        try {
            if (!this.provider) return []

            // Check for WETH/USDC position
            const positionData = await this.positionMonitor.getPositionData(userAddress, WETH, USDC)

            if (!positionData || (parseFloat(positionData.collateralAmount) === 0 && parseFloat(positionData.debtAmount) === 0)) {
                return []
            }

            // Get position health monitoring
            const healthMonitoring = await this.positionMonitor.monitorPosition(userAddress, WETH, USDC)

            return [
                {
                    id: `${userAddress}-weth-usdc`,
                    type: "long" as const, // Long WETH position with USDC debt
                    collateralToken: {
                        address: WETH,
                        symbol: "WETH",
                        decimals: 18,
                    },
                    debtToken: {
                        address: USDC,
                        symbol: "USDC",
                        decimals: 6,
                    },
                    collateralAmount: positionData.collateralAmount,
                    debtAmount: positionData.debtAmount,
                    healthFactor: positionData.healthFactor,
                    liquidationThreshold: positionData.liquidationThreshold,
                    // Additional monitoring data
                    riskLevel: healthMonitoring.riskLevel,
                    warnings: healthMonitoring.warnings,
                    collateralValueUSD: positionData.collateralValueUSD,
                    debtValueUSD: positionData.debtValueUSD,
                    netWorthUSD: positionData.netWorthUSD,
                },
            ]
        } catch (error) {
            console.error("Error fetching positions:", error)
            return []
        }
    }

    async getOrders(userAddress: string) {
        // Fetch orders from the limit order protocol
        // This would typically involve calling the 1inch API or indexing events
        console.log("Fetching orders for:", userAddress)
        return []
    }

    async approveTokens(tokenAddresses: string[]) {
        if (!this.signer) {
            throw new Error("Wallet not connected")
        }

        const approvals = []
        for (const tokenAddress of tokenAddresses) {
            const tokenContract = new ethers.Contract(tokenAddress, ["function approve(address,uint256) returns (bool)"], this.signer)

            const tx = await tokenContract.approve(MARGIN_SETTLER_ADDRESS, ethers.MaxUint256)
            approvals.push(tx.wait())
        }

        await Promise.all(approvals)
    }

    async checkAllowances(userAddress: string, tokenAddresses: string[]) {
        if (!this.provider) {
            throw new Error("Provider not available")
        }

        const results = []
        for (const tokenAddress of tokenAddresses) {
            const tokenContract = new ethers.Contract(tokenAddress, ["function allowance(address,address) view returns (uint256)"], this.provider)

            const allowance = await tokenContract.allowance(userAddress, MARGIN_SETTLER_ADDRESS)
            results.push({
                token: tokenAddress,
                allowance: allowance.toString(),
            })
        }

        return results
    }

    async submitOrder(
        orderResult: OrderResult,
        useRelayer: boolean = true
    ): Promise<{
        success: boolean
        transactionHash?: string
        trackingId?: string
        quote?: RelayerQuote
    }> {
        try {
            console.log("Submitting order for execution:", {
                orderHash: orderResult.orderHash,
                extensionHash: orderResult.extensionHash,
                useRelayer,
            })

            if (useRelayer) {
                // Submit to relayer network
                const quote = await this.relayerService.getRelayerQuote(orderResult)

                if (!quote.success) {
                    throw new MarginTradingError(quote.errorMessage || "Relayer rejected the order", ErrorCodes.FLASH_LOAN_FAILED)
                }

                const submission = await this.relayerService.submitToRelayer(orderResult)

                console.log("Order submitted to relayer successfully:", submission)

                return {
                    success: true,
                    transactionHash: submission.transactionHash,
                    trackingId: submission.trackingId,
                    quote,
                }
            } else {
                // Execute directly by user
                const txHash = await this.relayerService.executeOrderDirectly(orderResult)

                console.log("Order executed directly:", txHash)

                return {
                    success: true,
                    transactionHash: txHash,
                }
            }
        } catch (error) {
            throw handleError(error, "submitting order for execution")
        }
    }

    // Helper function that would be used by a relayer or advanced user
    async createFlashLoanFillCalldata(orderResult: OrderResult, swapCalldata: string): Promise<string> {
        // Create the complete calldata for flashLoanFill
        // This follows the pattern from FlashFill.t.sol

        // Access order data from the stored orderInfo
        const orderInfo = orderResult.orderInfo
        const takingAmount = orderInfo.takingAmount || BigInt(0)

        // Create taker traits (this would include extension and swap data)
        const takerTraits = this.createTakerTraits(orderResult.extensionCalldata.length, swapCalldata.length)

        // Combine extension and swap calldata
        const combinedArgs = ethers.concat([orderResult.extensionCalldata, swapCalldata])

        // Encode all parameters for flashLoanFill
        const flashLoanParams = ethers.AbiCoder.defaultAbiCoder().encode(
            ["tuple(uint256,address,address,address,address,uint256,uint256,uint256)", "bytes", "uint256", "uint256", "bytes", "bytes"],
            [
                [
                    orderInfo.salt || BigInt(0),
                    orderInfo.maker || "0x0000000000000000000000000000000000000000",
                    orderInfo.receiver || "0x0000000000000000000000000000000000000000",
                    orderInfo.makerAsset || "0x0000000000000000000000000000000000000000",
                    orderInfo.takerAsset || "0x0000000000000000000000000000000000000000",
                    orderInfo.makingAmount || BigInt(0),
                    orderInfo.takingAmount || BigInt(0),
                    0, // makerTraits - default value
                ],
                orderResult.orderSignature,
                takingAmount,
                takerTraits,
                combinedArgs,
                orderResult.extensionSignature,
            ]
        )

        return flashLoanParams
    }

    private createTakerTraits(extensionLength: number, swapLength: number): string {
        // Create taker traits that point to extension and swap data
        return this.swapService.createTakerTraits(extensionLength, swapLength)
    }
}
