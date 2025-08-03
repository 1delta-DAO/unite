import { ethers } from "ethers"
import { handleError, MarginTradingError, ErrorCodes } from "@/utils/errorHandling"
import { OrderResult } from "./marginService"
import { SwapService } from "./swapService"
import { OrderMonitor, OrderStatus as MonitorOrderStatus } from "./orderMonitor"

// Relayer configuration
const RELAYER_API_URL = process.env.RELAYER_API_URL || "http://localhost:3000/api"
const MARGIN_SETTLER_ADDRESS = process.env.NEXT_PUBLIC_MARGIN_SETTLER_ADDRESS || "0x0000000000000000000000000000000000000000"

export interface RelayerQuote {
    fillPrice: string
    estimatedGas: string
    estimatedTime: string // in seconds
    relayerFee: string
    slippage: string
    success: boolean
    errorMessage?: string
}

export interface RelayerSubmission {
    transactionHash: string
    relayerAddress: string
    estimatedConfirmation: string
    trackingId: string
}

export interface OrderStatus {
    status: "pending" | "executing" | "completed" | "failed" | "cancelled"
    transactionHash?: string
    blockNumber?: number
    executedAt?: Date
    failureReason?: string
    gasUsed?: string
    effectivePrice?: string
    relayerFee?: string
}

export class RelayerService {
    private provider: ethers.BrowserProvider | null = null
    private swapService: SwapService
    private marginSettlerContract: ethers.Contract | null = null
    private orderMonitor: OrderMonitor

    constructor() {
        this.swapService = new SwapService()
        this.orderMonitor = new OrderMonitor()
        this.initializeProvider()
    }

    private async initializeProvider() {
        if (typeof window !== "undefined" && window.ethereum) {
            this.provider = new ethers.BrowserProvider(window.ethereum)

            // MarginSettler contract ABI (simplified)
            const marginSettlerABI = [
                "function flashLoanFill(address asset, uint256 amount, bytes calldata params) external",
                "function hashExtension(bytes memory extension) external view returns (bytes32)",
                "function hashOrder(tuple(uint256 salt, address maker, address receiver, address makerAsset, address takerAsset, uint256 makingAmount, uint256 takingAmount, uint256 makerTraits) order) external view returns (bytes32)",
            ]

            this.marginSettlerContract = new ethers.Contract(MARGIN_SETTLER_ADDRESS, marginSettlerABI, this.provider)
        }
    }

    /**
     * Get a quote for filling an order through the relayer network
     */
    async getRelayerQuote(orderResult: OrderResult): Promise<RelayerQuote> {
        try {
            const orderInfo = orderResult.orderInfo

            // For now, provide a simple quote calculation
            // In production, this could call external pricing APIs
            const makingAmount = parseFloat(ethers.formatUnits(orderInfo.makingAmount?.toString() || "0", 6)) // USDC
            const takingAmount = parseFloat(ethers.formatUnits(orderInfo.takingAmount?.toString() || "0", 18)) // WETH

            // Simulate price calculation with slippage
            const basePrice = makingAmount / takingAmount
            const slippage = 0.5 // 0.5%
            const fillPrice = basePrice * (1 - slippage / 100)

            return {
                fillPrice: fillPrice.toFixed(2),
                estimatedGas: "300000",
                estimatedTime: "30",
                relayerFee: (makingAmount * 0.001).toFixed(2), // 0.1% fee
                slippage: slippage.toString(),
                success: true,
            }
        } catch (error) {
            throw handleError(error, "getting relayer quote")
        }
    }

    /**
     * Submit order to relayer network for execution
     */
    async submitToRelayer(orderResult: OrderResult): Promise<RelayerSubmission> {
        try {
            // Get quote first to validate
            const quote = await this.getRelayerQuote(orderResult)

            if (!quote.success) {
                throw new MarginTradingError(quote.errorMessage || "Relayer rejected the order", ErrorCodes.FLASH_LOAN_FAILED)
            }

            // Submit to backend relayer
            const { orderId, trackingId } = await this.orderMonitor.submitOrder(orderResult)

            return {
                transactionHash: "", // Will be filled when order is executed
                relayerAddress: process.env.NEXT_PUBLIC_RELAYER_ADDRESS || "0x0000000000000000000000000000000000000000",
                estimatedConfirmation: (Date.now() + 30000).toString(), // 30 seconds from now
                trackingId: trackingId,
            }
        } catch (error) {
            throw handleError(error, "submitting order to relayer")
        }
    }

    /**
     * Execute order directly (if user wants to be the filler)
     */
    async executeOrderDirectly(orderResult: OrderResult): Promise<string> {
        try {
            if (!this.provider || !this.marginSettlerContract) {
                throw new MarginTradingError("Provider not available", ErrorCodes.NETWORK_ERROR)
            }

            const signer = await this.provider.getSigner()
            const orderInfo = orderResult.orderInfo

            // Create swap calldata
            const swapCalldata = this.swapService.createSwapRouting(
                orderInfo.takerAsset?.toString() || "0x0000000000000000000000000000000000000000",
                orderInfo.makerAsset?.toString() || "0x0000000000000000000000000000000000000000",
                orderInfo.takingAmount?.toString() || "0",
                await signer.getAddress()
            )

            // Create taker traits
            const takerTraits = this.swapService.createTakerTraits(orderResult.extensionCalldata.length, swapCalldata.length)

            // Combine extension and swap data
            const combinedArgs = ethers.concat([orderResult.extensionCalldata, swapCalldata])

            // Encode flash loan parameters
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
                    orderInfo.takingAmount || BigInt(0),
                    takerTraits,
                    combinedArgs,
                    orderResult.extensionSignature,
                ]
            )

            // Prepend filler address to flash loan params
            const fillerAddress = await signer.getAddress()
            const finalParams = ethers.concat([fillerAddress, flashLoanParams])

            // Execute flash loan fill
            const marginSettlerWithSigner = this.marginSettlerContract.connect(signer)
            const tx = await (marginSettlerWithSigner as any).flashLoanFill(
                orderInfo.makerAsset || "0x0000000000000000000000000000000000000000", // Asset to flash loan (USDC)
                orderInfo.makingAmount || BigInt(0), // Amount to flash loan
                finalParams
            )

            return tx.hash
        } catch (error) {
            throw handleError(error, "executing order directly")
        }
    }

    /**
     * Check the status of an order
     */
    async getOrderStatus(trackingId: string): Promise<OrderStatus> {
        try {
            const orderStatus = await this.orderMonitor.getOrderStatus(trackingId)

            // Map status values between the interfaces
            let mappedStatus: OrderStatus["status"]
            switch (orderStatus.status) {
                case "pending":
                    mappedStatus = "pending"
                    break
                case "filling":
                    mappedStatus = "executing"
                    break
                case "filled":
                    mappedStatus = "completed"
                    break
                case "failed":
                    mappedStatus = "failed"
                    break
                case "cancelled":
                    mappedStatus = "cancelled"
                    break
            }

            return {
                status: mappedStatus,
                transactionHash: orderStatus.txHash,
                blockNumber: undefined, // Will be extracted from transaction receipt if needed
                executedAt: orderStatus.filledAt ? new Date(orderStatus.filledAt) : undefined,
                failureReason: orderStatus.errorMessage,
                gasUsed: undefined, // Can be added later
                effectivePrice: undefined, // Can be calculated from transaction
                relayerFee: undefined, // Can be calculated
            }
        } catch (error) {
            throw handleError(error, "getting order status")
        }
    }

    /**
     * Cancel a pending order
     */
    async cancelOrder(trackingId: string): Promise<boolean> {
        try {
            return await this.orderMonitor.cancelOrder(trackingId)
        } catch (error) {
            throw handleError(error, "cancelling order")
        }
    }

    /**
     * Get available relayers and their performance metrics
     */
    async getAvailableRelayers(): Promise<
        {
            address: string
            name: string
            successRate: string
            averageTime: string
            feeRate: string
            isActive: boolean
        }[]
    > {
        try {
            // Get statistics from backend
            const stats = await this.orderMonitor.getStatistics()
            const totalOrders = stats.filled + stats.failed
            const successRate = totalOrders > 0 ? ((stats.filled / totalOrders) * 100).toFixed(1) : "0.0"

            // Return our own relayer info
            return [
                {
                    address: process.env.NEXT_PUBLIC_RELAYER_ADDRESS || "0x0000000000000000000000000000000000000000",
                    name: "Unite Protocol Relayer",
                    successRate: `${successRate}%`,
                    averageTime: "30s",
                    feeRate: "0.1%",
                    isActive: true,
                },
            ]
        } catch (error) {
            throw handleError(error, "getting available relayers")
        }
    }
}
