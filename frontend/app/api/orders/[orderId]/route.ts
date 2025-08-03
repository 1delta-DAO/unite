import { NextRequest, NextResponse } from "next/server"
import { kv } from "@vercel/kv"

interface Order {
    id: string
    orderHash: string
    extensionHash: string
    order: {
        salt: string
        maker: string
        receiver: string
        makerAsset: string
        takerAsset: string
        makingAmount: string
        takingAmount: string
        makerTraits: string
    }
    orderSignature: string
    extensionCalldata: string
    extensionSignature: string
    status: "pending" | "filling" | "filled" | "failed" | "cancelled"
    createdAt: number
    filledAt?: number
    txHash?: string
    errorMessage?: string
}

// GET /api/orders/[orderId] - Get order status
export async function GET(request: NextRequest, { params }: { params: Promise<{ orderId: string }> }) {
    try {
        const { orderId } = await params

        const order = (await kv.get(`order:${orderId}`)) as Order
        if (!order) {
            return NextResponse.json({ error: "Order not found" }, { status: 404 })
        }

        return NextResponse.json(order)
    } catch (error) {
        console.error("Error fetching order:", error)
        return NextResponse.json({ error: "Internal server error" }, { status: 500 })
    }
}

// DELETE /api/orders/[orderId] - Cancel order
export async function DELETE(request: NextRequest, { params }: { params: Promise<{ orderId: string }> }) {
    try {
        const { orderId } = await params

        const order = (await kv.get(`order:${orderId}`)) as Order
        if (!order) {
            return NextResponse.json({ error: "Order not found" }, { status: 404 })
        }

        if (order.status === "filled" || order.status === "filling") {
            return NextResponse.json(
                {
                    error: "Cannot cancel order that is already filled or being filled",
                },
                { status: 400 }
            )
        }

        // Update order status
        const updatedOrder: Order = {
            ...order,
            status: "cancelled",
        }

        await kv.set(`order:${orderId}`, updatedOrder)

        // Move from pending to cancelled
        await kv.srem("pending_orders", orderId)
        await kv.sadd("cancelled_orders", orderId)

        return NextResponse.json({
            success: true,
            message: "Order cancelled successfully",
            order: updatedOrder,
        })
    } catch (error) {
        console.error("Error cancelling order:", error)
        return NextResponse.json({ error: "Internal server error" }, { status: 500 })
    }
}
