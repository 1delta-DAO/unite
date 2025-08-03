"use client"

export function FlashFillExplainer() {
    return (
        <div className="alert alert-info mb-6">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" className="stroke-current shrink-0 w-6 h-6">
                <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth="2"
                    d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                ></path>
            </svg>
            <div>
                <h3 className="font-bold">How Flash Fill Works</h3>
                <div className="text-sm mt-2">
                    <ol className="list-decimal list-inside space-y-1">
                        <li>You sign an order to borrow USDC and deposit WETH on Aave</li>
                        <li>A filler uses a flash loan to temporarily borrow the USDC</li>
                        <li>The filler swaps your WETH for USDC to repay the flash loan</li>
                        <li>Your position is created without requiring initial USDC balance</li>
                        <li>You end up with borrowed USDC and WETH collateral on Aave</li>
                    </ol>
                </div>
                <div className="mt-3 text-xs opacity-80">⚡ This enables opening leveraged positions without pre-funding</div>
            </div>
        </div>
    )
}
