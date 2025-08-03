"use client"

import { useState, useEffect } from "react"
import { useAccount } from "wagmi"
import { MarginService, MarginOrderParams } from "@/services/marginService"
import { Token, Position, Order } from "@/components/MarginTradingInterface"

export function useMarginTrading() {
    const { address, isConnected } = useAccount()
    const [isClient, setIsClient] = useState(false)

    const [marginService, setMarginService] = useState<MarginService | null>(null)
    const [positions, setPositions] = useState<Position[]>([])
    const [orders, setOrders] = useState<Order[]>([])
    const [loading, setLoading] = useState(false)
    const [error, setError] = useState<string | null>(null)

    useEffect(() => {
        setIsClient(true)
    }, [])

    useEffect(() => {
        if (isClient && isConnected) {
            const service = new MarginService()
            setMarginService(service)
        } else {
            setMarginService(null)
        }
    }, [isClient, isConnected])

    useEffect(() => {
        if (marginService && address) {
            loadPositions()
            loadOrders()
        }
    }, [marginService, address])

    const loadPositions = async () => {
        if (!marginService || !address) return

        try {
            setLoading(true)
            const userPositions = await marginService.getPositions(address)
            setPositions(userPositions)
        } catch (err) {
            console.error("Error loading positions:", err)
            setError("Failed to load positions")
        } finally {
            setLoading(false)
        }
    }

    const loadOrders = async () => {
        if (!marginService || !address) return

        try {
            setLoading(true)
            const userOrders = await marginService.getOrders(address)
            setOrders(userOrders)
        } catch (err) {
            console.error("Error loading orders:", err)
            setError("Failed to load orders")
        } finally {
            setLoading(false)
        }
    }

    const openPosition = async (params: {
        collateralToken: Token
        debtToken: Token
        collateralAmount: string
        debtAmount: string
        positionType: "long" | "short"
    }) => {
        if (!marginService || !address) {
            throw new Error("Wallet not connected")
        }

        try {
            setLoading(true)
            setError(null)

            // Check and approve tokens if needed
            const allowances = await marginService.checkAllowances(address, [params.collateralToken.address, params.debtToken.address])

            const needsApproval = allowances.some((allowance) => allowance.allowance === "0")

            if (needsApproval) {
                await marginService.approveTokens([params.collateralToken.address, params.debtToken.address])
            }

            // Create margin order
            const orderParams: MarginOrderParams = {
                collateralToken: params.collateralToken.address,
                debtToken: params.debtToken.address,
                collateralAmount: params.collateralAmount,
                debtAmount: params.debtAmount,
                positionType: params.positionType,
            }

            const result = await marginService.createMarginOrder(orderParams)

            // Reload positions and orders
            await Promise.all([loadPositions(), loadOrders()])

            return result
        } catch (err) {
            console.error("Error opening position:", err)
            setError(err instanceof Error ? err.message : "Failed to open position")
            throw err
        } finally {
            setLoading(false)
        }
    }

    const closePosition = async (positionId: string) => {
        if (!marginService) {
            throw new Error("Wallet not connected")
        }

        try {
            setLoading(true)
            setError(null)

            // TODO: Implement position closing logic
            console.log("Closing position:", positionId)

            // Reload positions
            await loadPositions()
        } catch (err) {
            console.error("Error closing position:", err)
            setError(err instanceof Error ? err.message : "Failed to close position")
            throw err
        } finally {
            setLoading(false)
        }
    }

    const cancelOrder = async (orderId: string) => {
        if (!marginService) {
            throw new Error("Wallet not connected")
        }

        try {
            setLoading(true)
            setError(null)

            // TODO: Implement order cancellation logic
            console.log("Cancelling order:", orderId)

            // Reload orders
            await loadOrders()
        } catch (err) {
            console.error("Error cancelling order:", err)
            setError(err instanceof Error ? err.message : "Failed to cancel order")
            throw err
        } finally {
            setLoading(false)
        }
    }

    return {
        // State
        positions,
        orders,
        loading,
        error,
        isConnected,
        address,
        isClient,

        // Actions
        openPosition,
        closePosition,
        cancelOrder,
        loadPositions,
        loadOrders,

        // Utilities
        marginService,
    }
}
