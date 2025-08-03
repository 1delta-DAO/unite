import { ethers } from "ethers"
import { handleError, MarginTradingError, ErrorCodes } from "@/utils/errorHandling"

// Uniswap V3 Router
const UNISWAP_V3_ROUTER = "0xE592427A0AEce92De3Edee1F18E0157C05861564"

export interface SwapParams {
    tokenIn: string
    tokenOut: string
    fee: number // Fee tier (500, 3000, 10000)
    recipient: string
    deadline: number
    amountIn: string
    amountOutMinimum: string
    sqrtPriceLimitX96: string
}

export interface SwapRoute {
    path: string
    amountOut: string
    gasEstimate: string
}

export class SwapService {
    private provider: ethers.BrowserProvider | null = null

    constructor() {
        this.initializeProvider()
    }

    private async initializeProvider() {
        if (typeof window !== "undefined" && window.ethereum) {
            this.provider = new ethers.BrowserProvider(window.ethereum)
        }
    }

    /**
     * Create Uniswap V3 exact input single swap calldata
     * This is used by the filler to swap tokens during flash loan execution
     */
    createUniswapV3SwapCalldata(params: SwapParams): string {
        const swapInterface = new ethers.Interface([
            "function exactInputSingle((address tokenIn, address tokenOut, uint24 fee, address recipient, uint256 deadline, uint256 amountIn, uint256 amountOutMinimum, uint160 sqrtPriceLimitX96)) external payable returns (uint256 amountOut)",
        ])

        return swapInterface.encodeFunctionData("exactInputSingle", [
            {
                tokenIn: params.tokenIn,
                tokenOut: params.tokenOut,
                fee: params.fee,
                recipient: params.recipient,
                deadline: params.deadline,
                amountIn: params.amountIn,
                amountOutMinimum: params.amountOutMinimum,
                sqrtPriceLimitX96: params.sqrtPriceLimitX96,
            },
        ])
    }

    /**
     * Create the "uno swap" style calldata used in the FlashFill test
     * This creates a simplified swap routing for demonstration
     */
    createUnoSwapCalldata(tokenIn: string, tokenOut: string, amountIn: string): string {
        try {
            // Create swap parameters for Uniswap V3
            const swapParams: SwapParams = {
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: 3000, // 0.3% fee tier
                recipient: "0x0000000000000000000000000000000000000000", // Will be set by the filler
                deadline: Math.floor(Date.now() / 1000) + 1800, // 30 minutes from now
                amountIn: amountIn,
                amountOutMinimum: "0", // Accept any amount of tokens out
                sqrtPriceLimitX96: "0", // No price limit
            }

            return this.createUniswapV3SwapCalldata(swapParams)
        } catch (error) {
            throw handleError(error, "creating swap calldata")
        }
    }

    /**
     * Get estimated output amount for a swap
     * This would typically call a quoter contract or 1inch API
     */
    async getSwapQuote(tokenIn: string, tokenOut: string, amountIn: string): Promise<string> {
        try {
            if (!this.provider) {
                throw new MarginTradingError("Provider not available", ErrorCodes.NETWORK_ERROR)
            }

            // For demo purposes, return a simplified quote
            // In production, you would call Uniswap V3 Quoter or 1inch API
            const amountInBN = ethers.parseUnits(amountIn, 18) // Assuming 18 decimals
            const estimatedOut = (amountInBN * BigInt(1500)) / BigInt(1) // Rough ETH/USDC rate estimation

            return ethers.formatUnits(estimatedOut, 6) // USDC has 6 decimals
        } catch (error) {
            throw handleError(error, "getting swap quote")
        }
    }

    /**
     * Create complete swap routing for flash loan execution
     * This includes the router target and encoded function call
     */
    createSwapRouting(tokenIn: string, tokenOut: string, amountIn: string, recipient: string): string {
        try {
            const swapCalldata = this.createUnoSwapCalldata(tokenIn, tokenOut, amountIn)

            // Prepend the router address (20 bytes) to the calldata
            return ethers.concat([
                UNISWAP_V3_ROUTER, // Router address (20 bytes)
                swapCalldata, // Function call data
            ])
        } catch (error) {
            throw handleError(error, "creating swap routing")
        }
    }

    /**
     * Estimate gas for a swap operation
     */
    async estimateSwapGas(tokenIn: string, tokenOut: string, amountIn: string): Promise<string> {
        try {
            // Simplified gas estimation
            // In production, you would call the router's estimateGas method
            return "200000" // Typical gas limit for Uniswap V3 swap
        } catch (error) {
            throw handleError(error, "estimating swap gas")
        }
    }

    /**
     * Validate if a token pair is supported for swapping
     */
    async validateTokenPair(tokenIn: string, tokenOut: string): Promise<boolean> {
        try {
            if (!ethers.isAddress(tokenIn) || !ethers.isAddress(tokenOut)) {
                return false
            }

            if (tokenIn.toLowerCase() === tokenOut.toLowerCase()) {
                return false
            }

            // In production, you would check if the pair has liquidity
            // For now, we'll assume all valid addresses are supported
            return true
        } catch (error) {
            console.error("Error validating token pair:", error)
            return false
        }
    }

    /**
     * Create taker traits for the limit order execution
     * This encodes information about where the extension and swap data are located
     */
    createTakerTraits(extensionLength: number, swapLength: number): string {
        try {
            // Simplified taker traits encoding
            // In production, you would use the actual TakerTraits library from 1inch

            // The traits encode:
            // - Extension data offset and length
            // - Swap data offset and length
            // - Other execution parameters

            const extensionOffset = 0
            const swapOffset = extensionLength

            // This is a simplified encoding - actual implementation would be more complex
            const traits = ethers.AbiCoder.defaultAbiCoder().encode(
                ["uint256", "uint256", "uint256", "uint256"],
                [extensionOffset, extensionLength, swapOffset, swapLength]
            )

            return traits
        } catch (error) {
            throw handleError(error, "creating taker traits")
        }
    }
}
