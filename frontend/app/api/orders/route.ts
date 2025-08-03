import { NextRequest, NextResponse } from "next/server"
import { kv } from "@vercel/kv"
import { ethers } from "ethers"

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

// POST /api/orders - Create new order
export async function POST(request: NextRequest) {
    try {
        const body = await request.json()

        // Validate required fields
        const requiredFields = ["orderHash", "order", "orderSignature", "extensionCalldata", "extensionSignature"]
        for (const field of requiredFields) {
            if (!body[field]) {
                return NextResponse.json({ error: `Missing required field: ${field}` }, { status: 400 })
            }
        }

        // Create order ID
        const orderId = `order_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`

        // Validate maker traits for allowed sender restriction
        const makerTraits = body.order.makerTraits || "0x"
        const allowedSender = process.env.RELAYER_ADDRESS || process.env.NEXT_PUBLIC_RELAYER_ADDRESS

        if (allowedSender) {
            // Check if maker traits include allowed sender restriction (last 10 bytes)
            const expectedTraits = makerTraits.slice(0, -20) + allowedSender.slice(2).toLowerCase()
            if (makerTraits.toLowerCase() !== expectedTraits.toLowerCase()) {
                return NextResponse.json(
                    {
                        error: "Order must include allowed sender restriction in maker traits",
                    },
                    { status: 400 }
                )
            }
        }

        const order: Order = {
            id: orderId,
            orderHash: body.orderHash,
            extensionHash: body.extensionHash || "",
            order: body.order,
            orderSignature: body.orderSignature,
            extensionCalldata: body.extensionCalldata,
            extensionSignature: body.extensionSignature,
            status: "pending",
            createdAt: Date.now(),
        }

        // Store order in KV
        await kv.set(`order:${orderId}`, order)
        await kv.sadd("pending_orders", orderId)

        // Trigger order filling (async)
        fetch(`${process.env.VERCEL_URL || "http://localhost:3000"}/api/orders/${orderId}/fill`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
        }).catch(console.error) // Don't wait for response

        return NextResponse.json({
            success: true,
            orderId,
            trackingId: orderId,
            status: "pending",
        })
    } catch (error) {
        console.error("Error creating order:", error)
        return NextResponse.json({ error: "Internal server error" }, { status: 500 })
    }
}

// GET /api/orders - List orders with pagination
export async function GET(request: NextRequest) {
    try {
        const { searchParams } = new URL(request.url)
        const status = searchParams.get("status")
        const limit = parseInt(searchParams.get("limit") || "50")
        const offset = parseInt(searchParams.get("offset") || "0")

        // Get order IDs based on status
        let orderIds: string[]
        if (status) {
            orderIds = (await kv.smembers(`${status}_orders`)) || []
        } else {
            // Get all order IDs (you might want to maintain a master list)
            const pendingIds = (await kv.smembers("pending_orders")) || []
            const fillingIds = (await kv.smembers("filling_orders")) || []
            const filledIds = (await kv.smembers("filled_orders")) || []
            const failedIds = (await kv.smembers("failed_orders")) || []
            orderIds = [...pendingIds, ...fillingIds, ...filledIds, ...failedIds]
        }

        // Paginate
        const paginatedIds = orderIds.slice(offset, offset + limit)

        // Fetch order details
        const orders: Order[] = []
        for (const orderId of paginatedIds) {
            const order = (await kv.get(`order:${orderId}`)) as Order
            if (order) {
                orders.push(order)
            }
        }

        // Sort by creation time (newest first)
        orders.sort((a, b) => b.createdAt - a.createdAt)

        return NextResponse.json({
            orders,
            total: orderIds.length,
            limit,
            offset,
        })
    } catch (error) {
        console.error("Error fetching orders:", error)
        return NextResponse.json({ error: "Internal server error" }, { status: 500 })
    }
}
