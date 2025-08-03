"use client"

import { useState, useEffect } from "react"
import { ConnectButton } from "@rainbow-me/rainbowkit"
import { useAccount } from "wagmi"
import { MarginTradingInterface } from "@/components/MarginTradingInterface"

export default function Home() {
    const { isConnected } = useAccount()
    const [isClient, setIsClient] = useState(false)

    // Prevent hydration errors
    useEffect(() => {
        setIsClient(true)
    }, [])

    // Don't render until client-side
    if (!isClient) {
        return (
            <div className="min-h-screen bg-base-100">
                <div className="navbar bg-base-200">
                    <div className="flex-1">
                        <h1 className="text-xl font-bold">1Delta Unite</h1>
                    </div>
                    <div className="flex-none">
                        <ConnectButton />
                    </div>
                </div>
                <div className="container mx-auto px-4 py-8">
                    <div className="flex justify-center">
                        <span className="loading loading-spinner loading-lg"></span>
                    </div>
                </div>
            </div>
        )
    }

    return (
        <div className="min-h-screen bg-base-100">
            <div className="navbar bg-base-200 flex flex-row p-3">
                <div className="flex-1">
                    <h1 className="text-2xl font-bold">1Delta Unite</h1>
                </div>
                <div className="flex-none">
                    <ConnectButton />
                </div>
            </div>

            <div className="container mx-auto px-4 py-8">
                {isConnected ? (
                    <MarginTradingInterface />
                ) : (
                    <div className="hero min-h-[60vh] bg-base-200">
                        <div className="hero-content text-center">
                            <div className="max-w-md">
                                <h1 className="text-5xl font-bold">Welcome to 1Delta Unite</h1>
                                <p className="py-6">Connect your wallet to start margin trading with 1inch limit orders</p>
                                <ConnectButton />
                            </div>
                        </div>
                    </div>
                )}
            </div>
        </div>
    )
}
