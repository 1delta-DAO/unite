"use client"

import { useState, useEffect } from "react"
import { useMarginTrading } from "@/hooks/useMarginTrading"
import { loadTokenData, Token } from "@/shared/consts"
import { OrdersList } from "./OrdersList"
import { PositionsList } from "./PositionsList"

export interface Position {
    id: string
    type: "long" | "short"
    collateralToken: Token
    debtToken: Token
    collateralAmount: string
    debtAmount: string
    healthFactor: string
    liquidationThreshold: string
}

export interface Order {
    id: string
    type: "long" | "short"
    status: "pending" | "filled" | "cancelled"
    collateralToken: Token
    debtToken: Token
    collateralAmount: string
    debtAmount: string
    createdAt: Date
}

export function MarginTradingInterface() {
    const [shortAmount, setShortAmount] = useState("0.0")
    const [longAmount, setLongAmount] = useState("0.0")
    const [shortToken, setShortToken] = useState<Token | null>(null)
    const [longToken, setLongToken] = useState<Token | null>(null)
    const [isClient, setIsClient] = useState(false)
    const [tokens, setTokens] = useState<Token[]>([])

    useEffect(() => {
        setIsClient(true)
    }, [])

    useEffect(() => {
        const loadTokens = async () => {
            const loadedTokens = await loadTokenData()
            setTokens(loadedTokens)
        }
        loadTokens()
    }, [])

    const marginTrading = useMarginTrading()
    const { loading, error, openPosition, isConnected, address, orders, positions, cancelOrder, closePosition } = marginTrading

    const handleOpenPosition = async () => {
        if (!shortToken || !longToken || shortAmount === "0.0" || longAmount === "0.0") {
            alert("Please fill in all fields")
            return
        }

        try {
            await openPosition({
                collateralToken: shortToken,
                debtToken: longToken,
                collateralAmount: shortAmount,
                debtAmount: longAmount,
                positionType: "short",
            })

            setShortAmount("0.0")
            setLongAmount("0.0")
            setShortToken(null)
            setLongToken(null)

            alert("Position opened successfully!")
        } catch (err) {
            console.error("Failed to open position:", err)
            alert(`Failed to open position: ${err instanceof Error ? err.message : "Unknown error"}`)
        }
    }

    const handleSwapTokens = () => {
        // Swap tokens
        const tempToken = shortToken
        setShortToken(longToken)
        setLongToken(tempToken)

        // Swap amounts
        const tempAmount = shortAmount
        setShortAmount(longAmount)
        setLongAmount(tempAmount)
    }

    if (!isClient) {
        return (
            <div className="flex justify-center items-center min-h-screen">
                <span className="loading loading-spinner loading-lg"></span>
            </div>
        )
    }

    return (
        <div className="max-w-4xl mx-auto p-6">
            {/* Error */}
            {error && (
                <div className="alert alert-error mb-6">
                    <svg xmlns="http://www.w3.org/2000/svg" className="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
                        <path
                            strokeLinecap="round"
                            strokeLinejoin="round"
                            strokeWidth="2"
                            d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"
                        />
                    </svg>
                    <span>{error}</span>
                </div>
            )}

            <div className="tabs tabs-lift">
                <input type="radio" name="my_tabs_3" className="tab" aria-label="Open" defaultChecked />
                <div className="tab-content bg-base-100 border-base-300 p-6">
                    {/* Position Sections */}
                    <div className="card bg-base-200 shadow-xl">
                        <div className="card-body">
                            {/* Short Position */}
                            <div className="mb-6">
                                <label className="text-base-content text-sm font-medium mb-2 block">Short</label>
                                <div className="flex items-center gap-4">
                                    <input
                                        type="number"
                                        placeholder="0.0"
                                        className="input input-bordered flex-1 text-2xl font-light"
                                        value={shortAmount}
                                        onChange={(e) => setShortAmount(e.target.value)}
                                    />
                                    <div className="dropdown dropdown-end">
                                        <div tabIndex={0} role="button" className="btn btn-outline gap-2">
                                            {shortToken ? (
                                                <>
                                                    {shortToken.logoURI ? (
                                                        <img
                                                            src={shortToken.logoURI}
                                                            alt={shortToken.symbol}
                                                            className="w-6 h-6 rounded-full"
                                                            onError={(e) => {
                                                                const target = e.target as HTMLImageElement
                                                                target.style.display = "none"
                                                                target.nextElementSibling?.classList.remove("hidden")
                                                            }}
                                                        />
                                                    ) : null}
                                                    <div
                                                        className={`w-6 h-6 rounded-full bg-yellow-400 flex items-center justify-center text-black font-bold text-sm ${
                                                            shortToken.logoURI ? "hidden" : ""
                                                        }`}
                                                    >
                                                        {shortToken.symbol.charAt(0)}
                                                    </div>
                                                    <span>{shortToken.symbol}</span>
                                                </>
                                            ) : (
                                                <>
                                                    <div className="w-6 h-6 rounded-full bg-yellow-400 flex items-center justify-center text-black font-bold text-sm">
                                                        S
                                                    </div>
                                                    <span>Select Token</span>
                                                </>
                                            )}
                                            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                                            </svg>
                                        </div>
                                        <ul
                                            tabIndex={0}
                                            className="dropdown-content z-[1] menu p-2 shadow bg-base-100 rounded-box w-52 max-h-60 overflow-y-auto"
                                        >
                                            {tokens.map((token) => (
                                                <li key={token.address}>
                                                    <button
                                                        onClick={() => setShortToken(token)}
                                                        className="flex items-center justify-between w-full p-2 hover:bg-base-200 text-left"
                                                    >
                                                        <div className="flex items-center gap-2">
                                                            {token.logoURI ? (
                                                                <img
                                                                    src={token.logoURI}
                                                                    alt={token.symbol}
                                                                    className="w-6 h-6 rounded-full"
                                                                    onError={(e) => {
                                                                        const target = e.target as HTMLImageElement
                                                                        target.style.display = "none"
                                                                        target.nextElementSibling?.classList.remove("hidden")
                                                                    }}
                                                                />
                                                            ) : null}
                                                            <div
                                                                className={`w-6 h-6 rounded-full bg-yellow-400 flex items-center justify-center text-black font-bold text-sm ${
                                                                    token.logoURI ? "hidden" : ""
                                                                }`}
                                                            >
                                                                {token.symbol.charAt(0)}
                                                            </div>
                                                            <span className="font-medium">{token.symbol}</span>
                                                        </div>
                                                        <span className="text-xs opacity-60">
                                                            {token.address.slice(0, 6)}...{token.address.slice(-4)}
                                                        </span>
                                                    </button>
                                                </li>
                                            ))}
                                        </ul>
                                    </div>
                                </div>
                            </div>

                            {/* Swap Button */}
                            <div className="flex justify-center mb-6">
                                <button className="btn btn-circle btn-sm" onClick={handleSwapTokens} disabled={!shortToken || !longToken}>
                                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path
                                            strokeLinecap="round"
                                            strokeLinejoin="round"
                                            strokeWidth={2}
                                            d="M7 16V4m0 0L3 8m4-4l4 4m6 0v12m0 0l4-4m-4 4l-4-4"
                                        />
                                    </svg>
                                </button>
                            </div>

                            {/* Long Position */}
                            <div className="mb-6">
                                <label className="text-base-content text-sm font-medium mb-2 block">Long</label>
                                <div className="flex items-center gap-4">
                                    <input
                                        type="number"
                                        placeholder="0.0"
                                        className="input input-bordered flex-1 text-2xl font-light"
                                        value={longAmount}
                                        onChange={(e) => setLongAmount(e.target.value)}
                                    />
                                    <div className="dropdown dropdown-end">
                                        <div tabIndex={0} role="button" className="btn btn-outline gap-2">
                                            {longToken ? (
                                                <>
                                                    {longToken.logoURI ? (
                                                        <img
                                                            src={longToken.logoURI}
                                                            alt={longToken.symbol}
                                                            className="w-6 h-6 rounded-full"
                                                            onError={(e) => {
                                                                const target = e.target as HTMLImageElement
                                                                target.style.display = "none"
                                                                target.nextElementSibling?.classList.remove("hidden")
                                                            }}
                                                        />
                                                    ) : null}
                                                    <div
                                                        className={`w-6 h-6 bg-blue-500 flex items-center justify-center text-white font-bold text-sm ${
                                                            longToken.logoURI ? "hidden" : ""
                                                        }`}
                                                    >
                                                        {longToken.symbol.charAt(0)}
                                                    </div>
                                                    <span>{longToken.symbol}</span>
                                                </>
                                            ) : (
                                                <>
                                                    <div className="w-6 h-6 bg-blue-500 flex items-center justify-center text-white font-bold text-sm">
                                                        L
                                                    </div>
                                                    <span>Select Token</span>
                                                </>
                                            )}
                                            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                                            </svg>
                                        </div>
                                        <ul
                                            tabIndex={0}
                                            className="dropdown-content z-[1] menu p-2 shadow bg-base-100 rounded-box w-52 max-h-60 overflow-y-auto"
                                        >
                                            {tokens.map((token) => (
                                                <li key={token.address}>
                                                    <button
                                                        onClick={() => setLongToken(token)}
                                                        className="flex items-center justify-between w-full p-2 hover:bg-base-200 text-left"
                                                    >
                                                        <div className="flex items-center gap-2">
                                                            {token.logoURI ? (
                                                                <img
                                                                    src={token.logoURI}
                                                                    alt={token.symbol}
                                                                    className="w-6 h-6 rounded-full"
                                                                    onError={(e) => {
                                                                        const target = e.target as HTMLImageElement
                                                                        target.style.display = "none"
                                                                        target.nextElementSibling?.classList.remove("hidden")
                                                                    }}
                                                                />
                                                            ) : null}
                                                            <div
                                                                className={`w-6 h-6 bg-blue-500 flex items-center justify-center text-white font-bold text-sm ${
                                                                    token.logoURI ? "hidden" : ""
                                                                }`}
                                                            >
                                                                {token.symbol.charAt(0)}
                                                            </div>
                                                            <span className="font-medium">{token.symbol}</span>
                                                        </div>
                                                        <span className="text-xs opacity-60">
                                                            {token.address.slice(0, 6)}...{token.address.slice(-4)}
                                                        </span>
                                                    </button>
                                                </li>
                                            ))}
                                        </ul>
                                    </div>
                                </div>
                            </div>

                            {/* Connect Button */}
                            <div className="mt-8">
                                <button
                                    className="btn btn-success btn-lg w-full"
                                    onClick={handleOpenPosition}
                                    disabled={!shortToken || !longToken || shortAmount === "0.0" || longAmount === "0.0" || loading}
                                >
                                    {loading ? (
                                        <>
                                            <span className="loading loading-spinner loading-sm"></span>
                                            Opening Position...
                                        </>
                                    ) : !isConnected ? (
                                        "Connect"
                                    ) : (
                                        "Open Position"
                                    )}
                                </button>
                            </div>
                        </div>
                    </div>
                </div>

                <input disabled type="radio" name="my_tabs_3" className="tab" aria-label="Close" />
                <div className="tab-content bg-base-100 border-base-300 p-6"></div>

                <input disabled type="radio" name="my_tabs_3" className="tab" aria-label="Manage" />
                <div className="tab-content bg-base-100 border-base-300 p-6"></div>

                <input disabled type="radio" name="my_tabs_3" className="tab" aria-label="Triggers" />
                <div className="tab-content bg-base-100 border-base-300 p-6"></div>
            </div>

            {/* Orders and Positions Section */}
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-8">
                <OrdersList orders={orders} onCancelOrder={cancelOrder} />
                <PositionsList positions={positions} onClosePosition={closePosition} />
            </div>
        </div>
    )
}
