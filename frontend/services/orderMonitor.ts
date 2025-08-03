import { OrderResult } from "./marginService"

export interface OrderStatus {
    id: string
    status: "pending" | "filling" | "filled" | "failed" | "cancelled"
    createdAt: number
    filledAt?: number
    txHash?: string
    errorMessage?: string
}

export class OrderMonitor {
    private apiUrl: string

    constructor() {
        this.apiUrl = process.env.RELAYER_API_URL || "/api"
    }

    /**
     * Submit order to backend relayer
     */
    async submitOrder(orderResult: OrderResult): Promise<{ orderId: string; trackingId: string }> {
        try {
            const response = await fetch(`${this.apiUrl}/orders`, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                },
                body: JSON.stringify({
                    orderHash: orderResult.orderHash,
                    extensionHash: orderResult.extensionHash,
                    order: {
                        salt: orderResult.orderInfo.salt?.toString() || "0",
                        maker: orderResult.orderInfo.maker?.toString() || "",
                        receiver: orderResult.orderInfo.receiver?.toString() || "",
                        makerAsset: orderResult.orderInfo.makerAsset?.toString() || "",
                        takerAsset: orderResult.orderInfo.takerAsset?.toString() || "",
                        makingAmount: orderResult.orderInfo.makingAmount?.toString() || "0",
                        takingAmount: orderResult.orderInfo.takingAmount?.toString() || "0",
                        makerTraits: orderResult.order.makerTraits?.toString() || "0",
                    },
                    orderSignature: orderResult.orderSignature,
                    extensionCalldata: orderResult.extensionCalldata,
                    extensionSignature: orderResult.extensionSignature,
                }),
            })

            if (!response.ok) {
                const error = await response.json()
                throw new Error(error.error || "Failed to submit order")
            }

            const result = await response.json()
            return {
                orderId: result.orderId,
                trackingId: result.trackingId,
            }
        } catch (error) {
            console.error("Error submitting order:", error)
            throw error
        }
    }

    /**
     * Get order status by ID
     */
    async getOrderStatus(orderId: string): Promise<OrderStatus> {
        try {
            const response = await fetch(`${this.apiUrl}/orders/${orderId}`)

            if (!response.ok) {
                if (response.status === 404) {
                    throw new Error("Order not found")
                }
                throw new Error("Failed to get order status")
            }

            const order = await response.json()
            return {
                id: order.id,
                status: order.status,
                createdAt: order.createdAt,
                filledAt: order.filledAt,
                txHash: order.txHash,
                errorMessage: order.errorMessage,
            }
        } catch (error) {
            console.error("Error getting order status:", error)
            throw error
        }
    }

    /**
     * Cancel an order
     */
    async cancelOrder(orderId: string): Promise<boolean> {
        try {
            const response = await fetch(`${this.apiUrl}/orders/${orderId}`, {
                method: "DELETE",
            })

            if (!response.ok) {
                const error = await response.json()
                throw new Error(error.error || "Failed to cancel order")
            }

            return true
        } catch (error) {
            console.error("Error cancelling order:", error)
            throw error
        }
    }

    /**
     * List orders with optional filtering
     */
    async listOrders(options?: { status?: string; limit?: number; offset?: number }): Promise<{
        orders: OrderStatus[]
        total: number
        limit: number
        offset: number
    }> {
        try {
            const params = new URLSearchParams()
            if (options?.status) params.append("status", options.status)
            if (options?.limit) params.append("limit", options.limit.toString())
            if (options?.offset) params.append("offset", options.offset.toString())

            const response = await fetch(`${this.apiUrl}/orders?${params}`)

            if (!response.ok) {
                throw new Error("Failed to list orders")
            }

            const result = await response.json()
            return {
                orders: result.orders.map((order: any) => ({
                    id: order.id,
                    status: order.status,
                    createdAt: order.createdAt,
                    filledAt: order.filledAt,
                    txHash: order.txHash,
                    errorMessage: order.errorMessage,
                })),
                total: result.total,
                limit: result.limit,
                offset: result.offset,
            }
        } catch (error) {
            console.error("Error listing orders:", error)
            throw error
        }
    }

    /**
     * Get relayer statistics
     */
    async getStatistics(): Promise<{
        pending: number
        filling: number
        filled: number
        failed: number
        cancelled: number
        total: number
    }> {
        try {
            const response = await fetch(`${this.apiUrl}/orders/process`)

            if (!response.ok) {
                throw new Error("Failed to get statistics")
            }

            const result = await response.json()
            return result.statistics
        } catch (error) {
            console.error("Error getting statistics:", error)
            throw error
        }
    }

    /**
     * Start monitoring an order with polling
     */
    startMonitoring(orderId: string, onUpdate: (status: OrderStatus) => void, intervalMs: number = 5000): () => void {
        let isActive = true

        const poll = async () => {
            if (!isActive) return

            try {
                const status = await this.getOrderStatus(orderId)
                onUpdate(status)

                // Continue polling if order is still in progress
                if (status.status === "pending" || status.status === "filling") {
                    setTimeout(poll, intervalMs)
                }
            } catch (error) {
                console.error("Error polling order status:", error)
                if (isActive) {
                    setTimeout(poll, intervalMs * 2) // Back off on error
                }
            }
        }

        // Start polling
        poll()

        // Return stop function
        return () => {
            isActive = false
        }
    }
}
