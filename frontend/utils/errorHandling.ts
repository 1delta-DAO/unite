export class MarginTradingError extends Error {
    constructor(message: string, public code: string, public originalError?: unknown) {
        super(message)
        this.name = "MarginTradingError"
    }
}

export enum ErrorCodes {
    WALLET_NOT_CONNECTED = "WALLET_NOT_CONNECTED",
    INSUFFICIENT_BALANCE = "INSUFFICIENT_BALANCE",
    INSUFFICIENT_ALLOWANCE = "INSUFFICIENT_ALLOWANCE",
    INVALID_TOKEN_PAIR = "INVALID_TOKEN_PAIR",
    INVALID_AMOUNT = "INVALID_AMOUNT",
    NETWORK_ERROR = "NETWORK_ERROR",
    CONTRACT_ERROR = "CONTRACT_ERROR",
    SIGNATURE_REJECTED = "SIGNATURE_REJECTED",
    TRANSACTION_FAILED = "TRANSACTION_FAILED",
    EXTENSION_CREATION_FAILED = "EXTENSION_CREATION_FAILED",
    ORDER_CREATION_FAILED = "ORDER_CREATION_FAILED",
    AAVE_OPERATION_FAILED = "AAVE_OPERATION_FAILED",
    FLASH_LOAN_FAILED = "FLASH_LOAN_FAILED",
    LEVERAGE_TOO_HIGH = "LEVERAGE_TOO_HIGH",
    HEALTH_FACTOR_TOO_LOW = "HEALTH_FACTOR_TOO_LOW",
}

export function handleError(error: unknown, operation: string): MarginTradingError {
    console.error(`Error in ${operation}:`, error)

    // Handle ethers.js errors
    if (error && typeof error === "object" && "code" in error) {
        const ethersError = error as any

        switch (ethersError.code) {
            case "ACTION_REJECTED":
            case "USER_REJECTED":
                return new MarginTradingError("Transaction was rejected by user", ErrorCodes.SIGNATURE_REJECTED, error)

            case "INSUFFICIENT_FUNDS":
                return new MarginTradingError("Insufficient funds for this operation", ErrorCodes.INSUFFICIENT_BALANCE, error)

            case "NETWORK_ERROR":
                return new MarginTradingError("Network error - please check your connection", ErrorCodes.NETWORK_ERROR, error)

            case "CALL_EXCEPTION":
                return new MarginTradingError("Smart contract call failed - please check parameters", ErrorCodes.CONTRACT_ERROR, error)
        }
    }

    // Handle specific error messages
    if (error instanceof Error) {
        const message = error.message.toLowerCase()

        if (message.includes("user rejected") || message.includes("rejected")) {
            return new MarginTradingError("Transaction was rejected by user", ErrorCodes.SIGNATURE_REJECTED, error)
        }

        if (message.includes("insufficient") && message.includes("balance")) {
            return new MarginTradingError("Insufficient token balance for this operation", ErrorCodes.INSUFFICIENT_BALANCE, error)
        }

        if (message.includes("allowance")) {
            return new MarginTradingError("Token allowance is insufficient - please approve tokens", ErrorCodes.INSUFFICIENT_ALLOWANCE, error)
        }

        if (message.includes("network") || message.includes("connection")) {
            return new MarginTradingError("Network connectivity issue - please try again", ErrorCodes.NETWORK_ERROR, error)
        }

        if (message.includes("health factor") || message.includes("liquidation")) {
            return new MarginTradingError("Position would be at risk of liquidation - reduce leverage", ErrorCodes.HEALTH_FACTOR_TOO_LOW, error)
        }

        if (message.includes("leverage") || message.includes("borrow")) {
            return new MarginTradingError("Leverage ratio is too high for this position", ErrorCodes.LEVERAGE_TOO_HIGH, error)
        }

        // Return the original error message for unknown errors
        return new MarginTradingError(`${operation} failed: ${error.message}`, ErrorCodes.CONTRACT_ERROR, error)
    }

    // Fallback for unknown error types
    return new MarginTradingError(`${operation} failed with unknown error`, ErrorCodes.CONTRACT_ERROR, error)
}

export function getUserFriendlyErrorMessage(error: MarginTradingError): string {
    switch (error.code) {
        case ErrorCodes.WALLET_NOT_CONNECTED:
            return "Please connect your wallet to continue"

        case ErrorCodes.INSUFFICIENT_BALANCE:
            return "You don't have enough tokens for this operation"

        case ErrorCodes.INSUFFICIENT_ALLOWANCE:
            return "Please approve token spending first"

        case ErrorCodes.INVALID_TOKEN_PAIR:
            return "This token pair is not supported"

        case ErrorCodes.INVALID_AMOUNT:
            return "Please enter a valid amount"

        case ErrorCodes.SIGNATURE_REJECTED:
            return "Transaction was cancelled - please try again"

        case ErrorCodes.NETWORK_ERROR:
            return "Network error - please check your connection and try again"

        case ErrorCodes.LEVERAGE_TOO_HIGH:
            return "Leverage is too high - please reduce the borrowed amount"

        case ErrorCodes.HEALTH_FACTOR_TOO_LOW:
            return "Position health factor would be too low - increase collateral or reduce debt"

        case ErrorCodes.AAVE_OPERATION_FAILED:
            return "Aave lending operation failed - please try again"

        case ErrorCodes.FLASH_LOAN_FAILED:
            return "Flash loan execution failed - please try again"

        default:
            return error.message
    }
}

// Validation functions
export function validateTokenAmount(amount: string, decimals: number): void {
    if (!amount || amount === "0" || amount === "0.0") {
        throw new MarginTradingError("Amount must be greater than 0", ErrorCodes.INVALID_AMOUNT)
    }

    try {
        const parsed = parseFloat(amount)
        if (parsed <= 0 || isNaN(parsed)) {
            throw new MarginTradingError("Invalid amount format", ErrorCodes.INVALID_AMOUNT)
        }
    } catch {
        throw new MarginTradingError("Invalid amount format", ErrorCodes.INVALID_AMOUNT)
    }
}

export function validateLeverageRatio(collateral: string, debt: string): void {
    const collateralNum = parseFloat(collateral)
    const debtNum = parseFloat(debt)

    if (collateralNum <= 0 || debtNum <= 0) {
        throw new MarginTradingError("Both collateral and debt amounts must be positive", ErrorCodes.INVALID_AMOUNT)
    }

    const leverage = (collateralNum + debtNum) / collateralNum

    // Maximum 10x leverage for safety
    if (leverage > 10) {
        throw new MarginTradingError("Maximum leverage is 10x", ErrorCodes.LEVERAGE_TOO_HIGH)
    }
}
