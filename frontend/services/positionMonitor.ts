import { ethers } from "ethers"
import { handleError, MarginTradingError, ErrorCodes } from "@/utils/errorHandling"

// Aave V3 contract addresses on Arbitrum
const AAVE_V3_POOL = "0x794a61358D6845594F94dc1DB02A252b5b4814aD"
const AAVE_V3_ORACLE = "0xb56c2F0B653B2e0b10C9b928C8580Ac5Df02C7C7"
const AAVE_V3_PROTOCOL_DATA_PROVIDER = "0x69FA688f1Dc47d4B5d8029D5a35FB7a548310654"

export interface AavePosition {
    collateralAmount: string
    debtAmount: string
    healthFactor: string
    liquidationThreshold: string
    ltv: string
    currentLiquidationThreshold: string
    collateralValueUSD: string
    debtValueUSD: string
    availableBorrowsUSD: string
    netWorthUSD: string
}

export interface TokenPrice {
    address: string
    symbol: string
    priceUSD: string
    decimals: number
}

export class PositionMonitor {
    private provider: ethers.BrowserProvider | null = null
    private poolContract: ethers.Contract | null = null
    private oracleContract: ethers.Contract | null = null
    private dataProviderContract: ethers.Contract | null = null

    constructor() {
        this.initializeContracts()
    }

    private async initializeContracts() {
        if (typeof window !== "undefined" && window.ethereum) {
            this.provider = new ethers.BrowserProvider(window.ethereum)

            // Pool contract ABI (simplified)
            const poolABI = [
                "function getUserAccountData(address user) external view returns (uint256 totalCollateralETH, uint256 totalDebtETH, uint256 availableBorrowsETH, uint256 currentLiquidationThreshold, uint256 ltv, uint256 healthFactor)",
            ]

            // Oracle contract ABI (simplified)
            const oracleABI = [
                "function getAssetPrice(address asset) external view returns (uint256)",
                "function getAssetsPrices(address[] calldata assets) external view returns (uint256[])",
            ]

            // Data provider ABI (simplified)
            const dataProviderABI = [
                "function getUserReserveData(address asset, address user) external view returns (uint256 currentATokenBalance, uint256 currentStableDebt, uint256 currentVariableDebt, uint256 principalStableDebt, uint256 scaledVariableDebt, uint256 stableBorrowRate, uint256 liquidityRate, uint40 stableRateLastUpdated, bool usageAsCollateralEnabled)",
                "function getReserveConfigurationData(address asset) external view returns (uint256 decimals, uint256 ltv, uint256 liquidationThreshold, uint256 liquidationBonus, uint256 reserveFactor, bool usageAsCollateralEnabled, bool borrowingEnabled, bool stableBorrowRateEnabled, bool isActive, bool isFrozen)",
            ]

            this.poolContract = new ethers.Contract(AAVE_V3_POOL, poolABI, this.provider)
            this.oracleContract = new ethers.Contract(AAVE_V3_ORACLE, oracleABI, this.provider)
            this.dataProviderContract = new ethers.Contract(AAVE_V3_PROTOCOL_DATA_PROVIDER, dataProviderABI, this.provider)
        }
    }

    /**
     * Get comprehensive position data for a user
     */
    async getPositionData(userAddress: string, collateralToken: string, debtToken: string): Promise<AavePosition | null> {
        try {
            if (!this.poolContract || !this.oracleContract || !this.dataProviderContract) {
                throw new MarginTradingError("Contracts not initialized", ErrorCodes.CONTRACT_ERROR)
            }

            // Get user account data from Aave
            const accountData = await this.poolContract.getUserAccountData(userAddress)

            // Get user-specific reserve data
            const [collateralData, debtData] = await Promise.all([
                this.dataProviderContract.getUserReserveData(collateralToken, userAddress),
                this.dataProviderContract.getUserReserveData(debtToken, userAddress),
            ])

            // Get token prices
            const [collateralPrice, debtPrice] = await Promise.all([
                this.oracleContract.getAssetPrice(collateralToken),
                this.oracleContract.getAssetPrice(debtToken),
            ])

            // Get reserve configuration
            const [collateralConfig, debtConfig] = await Promise.all([
                this.dataProviderContract.getReserveConfigurationData(collateralToken),
                this.dataProviderContract.getReserveConfigurationData(debtToken),
            ])

            // Calculate position metrics
            const collateralAmount = ethers.formatUnits(collateralData[0], 18) // aToken balance
            const debtAmount = ethers.formatUnits(collateralData[2], 6) // Variable debt

            const collateralValueUSD = this.calculateUSDValue(
                collateralData[0],
                collateralPrice,
                18 // WETH decimals
            )

            const debtValueUSD = this.calculateUSDValue(
                collateralData[2],
                debtPrice,
                6 // USDC decimals
            )

            // Health factor calculation (from Aave)
            const healthFactor = accountData[5] > 0 ? ethers.formatUnits(accountData[5], 18) : "∞" // No debt means infinite health factor

            return {
                collateralAmount,
                debtAmount,
                healthFactor,
                liquidationThreshold: ethers.formatUnits(collateralConfig[2], 2), // Convert from basis points
                ltv: ethers.formatUnits(collateralConfig[1], 2), // Convert from basis points
                currentLiquidationThreshold: ethers.formatUnits(accountData[3], 4), // Already in percentage
                collateralValueUSD,
                debtValueUSD,
                availableBorrowsUSD: ethers.formatEther(accountData[2]), // Available borrows in ETH
                netWorthUSD: (parseFloat(collateralValueUSD) - parseFloat(debtValueUSD)).toString(),
            }
        } catch (error) {
            throw handleError(error, "fetching position data")
        }
    }

    /**
     * Calculate USD value of a token amount
     */
    private calculateUSDValue(amount: bigint, priceInETH: bigint, decimals: number): string {
        try {
            // Price is typically in ETH terms, need to convert to USD
            // For simplification, we'll assume 1 ETH = $2000 USD
            const ETH_USD_PRICE = BigInt(2000)

            const amountFormatted = ethers.formatUnits(amount, decimals)
            const priceETH = ethers.formatEther(priceInETH)
            const priceUSD = parseFloat(priceETH) * Number(ETH_USD_PRICE)

            const valueUSD = parseFloat(amountFormatted) * priceUSD
            return valueUSD.toFixed(2)
        } catch (error) {
            console.error("Error calculating USD value:", error)
            return "0.00"
        }
    }

    /**
     * Get token prices for multiple assets
     */
    async getTokenPrices(tokens: string[]): Promise<TokenPrice[]> {
        try {
            if (!this.oracleContract) {
                throw new MarginTradingError("Oracle contract not initialized", ErrorCodes.CONTRACT_ERROR)
            }

            const prices = await this.oracleContract.getAssetsPrices(tokens)

            return tokens.map((token, index) => ({
                address: token,
                symbol: this.getTokenSymbol(token), // You'd need a mapping or registry
                priceUSD: ethers.formatEther(prices[index]),
                decimals: this.getTokenDecimals(token), // You'd need a mapping or registry
            }))
        } catch (error) {
            throw handleError(error, "fetching token prices")
        }
    }

    /**
     * Monitor position health and emit warnings
     */
    async monitorPosition(
        userAddress: string,
        collateralToken: string,
        debtToken: string
    ): Promise<{
        isHealthy: boolean
        warnings: string[]
        riskLevel: "low" | "medium" | "high" | "critical"
    }> {
        try {
            const position = await this.getPositionData(userAddress, collateralToken, debtToken)

            if (!position) {
                return {
                    isHealthy: true,
                    warnings: [],
                    riskLevel: "low",
                }
            }

            const healthFactor = parseFloat(position.healthFactor)
            const warnings: string[] = []
            let riskLevel: "low" | "medium" | "high" | "critical" = "low"

            // Health factor warnings
            if (healthFactor < 1.1) {
                warnings.push("CRITICAL: Position is very close to liquidation!")
                riskLevel = "critical"
            } else if (healthFactor < 1.3) {
                warnings.push("HIGH RISK: Consider adding collateral or repaying debt")
                riskLevel = "high"
            } else if (healthFactor < 1.5) {
                warnings.push("MEDIUM RISK: Monitor position closely")
                riskLevel = "medium"
            }

            // Net worth warnings
            const netWorth = parseFloat(position.netWorthUSD)
            if (netWorth < 0) {
                warnings.push("Position is underwater - debt exceeds collateral value")
            }

            return {
                isHealthy: healthFactor > 1.3,
                warnings,
                riskLevel,
            }
        } catch (error) {
            throw handleError(error, "monitoring position")
        }
    }

    /**
     * Calculate maximum safe borrow amount
     */
    async getMaxSafeBorrow(userAddress: string, collateralToken: string, collateralAmount: string): Promise<string> {
        try {
            if (!this.dataProviderContract || !this.oracleContract) {
                throw new MarginTradingError("Contracts not initialized", ErrorCodes.CONTRACT_ERROR)
            }

            // Get collateral configuration
            const collateralConfig = await this.dataProviderContract.getReserveConfigurationData(collateralToken)
            const ltv = collateralConfig[1] // LTV in basis points

            // Get collateral price
            const collateralPrice = await this.oracleContract.getAssetPrice(collateralToken)

            // Calculate max borrow with safety margin
            const collateralValueETH = (BigInt(ethers.parseUnits(collateralAmount, 18)) * collateralPrice) / BigInt(10 ** 18)
            const maxBorrowETH = (collateralValueETH * ltv) / BigInt(10000) // Convert from basis points
            const safeBorrowETH = (maxBorrowETH * BigInt(80)) / BigInt(100) // 80% of max for safety

            return ethers.formatEther(safeBorrowETH)
        } catch (error) {
            throw handleError(error, "calculating max safe borrow")
        }
    }

    // Helper functions (in production these would come from a token registry)
    private getTokenSymbol(address: string): string {
        const symbols: { [key: string]: string } = {
            "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1": "WETH",
            "0xaf88d065e77c8cc2239327c5edb3a432268e5831": "USDC",
            // Add more as needed
        }
        return symbols[address] || "UNKNOWN"
    }

    private getTokenDecimals(address: string): number {
        const decimals: { [key: string]: number } = {
            "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1": 18, // WETH
            "0xaf88d065e77c8cc2239327c5edb3a432268e5831": 6, // USDC
            // Add more as needed
        }
        return decimals[address] || 18
    }
}
