import { NextRequest, NextResponse } from "next/server"
import { kv } from "@vercel/kv"

// POST /api/orders/process - Background job to process pending orders
export async function POST(request: NextRequest) {
    try {
        // Get all pending orders
        const pendingOrderIds = (await kv.smembers("pending_orders")) || []

        if (pendingOrderIds.length === 0) {
            return NextResponse.json({
                message: "No pending orders to process",
                processed: 0,
            })
        }

        console.log(`Processing ${pendingOrderIds.length} pending orders`)

        const results = []

        // Process each order (you might want to limit this for large numbers)
        for (const orderId of pendingOrderIds.slice(0, 10)) {
            // Process max 10 at a time
            try {
                // Call the fill endpoint for each order
                const fillResponse = await fetch(`${process.env.VERCEL_URL || "http://localhost:3000"}/api/orders/${orderId}/fill`, {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                })

                const fillResult = await fillResponse.json()
                results.push({
                    orderId,
                    success: fillResponse.ok,
                    result: fillResult,
                })

                // Add small delay between fills to avoid rate limiting
                await new Promise((resolve) => setTimeout(resolve, 1000))
            } catch (error) {
                console.error(`Error processing order ${orderId}:`, error)
                results.push({
                    orderId,
                    success: false,
                    error: error instanceof Error ? error.message : "Unknown error",
                })
            }
        }

        const successful = results.filter((r) => r.success).length
        const failed = results.filter((r) => !r.success).length

        return NextResponse.json({
            message: `Processed ${results.length} orders`,
            successful,
            failed,
            results,
        })
    } catch (error) {
        console.error("Error in process endpoint:", error)
        return NextResponse.json({ error: "Internal server error" }, { status: 500 })
    }
}

// GET /api/orders/process - Get processing status
export async function GET(request: NextRequest) {
    try {
        const pendingCount = (await kv.scard("pending_orders")) || 0
        const fillingCount = (await kv.scard("filling_orders")) || 0
        const filledCount = (await kv.scard("filled_orders")) || 0
        const failedCount = (await kv.scard("failed_orders")) || 0
        const cancelledCount = (await kv.scard("cancelled_orders")) || 0

        return NextResponse.json({
            statistics: {
                pending: pendingCount,
                filling: fillingCount,
                filled: filledCount,
                failed: failedCount,
                cancelled: cancelledCount,
                total: pendingCount + fillingCount + filledCount + failedCount + cancelledCount,
            },
        })
    } catch (error) {
        console.error("Error getting statistics:", error)
        return NextResponse.json({ error: "Internal server error" }, { status: 500 })
    }
}
