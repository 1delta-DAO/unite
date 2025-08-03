import { NextRequest, NextResponse } from "next/server"

// POST /api/cron/process-orders - Automated background processing
export async function POST(request: NextRequest) {
    try {
        const authHeader = request.headers.get("authorization")
        if (process.env.NODE_ENV === "production" && authHeader !== `Bearer ${process.env.CRON_SECRET}`) {
            return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
        }

        console.log("Starting daily background order processing...")

        const batchRuns = 5
        const results = []

        for (let i = 0; i < batchRuns; i++) {
            try {
                const processResponse = await fetch(`${process.env.VERCEL_URL || "http://localhost:3000"}/api/orders/process`, {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                })

                const batchResult = await processResponse.json()
                results.push({
                    batch: i + 1,
                    ...batchResult,
                })

                // If no pending orders, break early
                if (batchResult.processed === 0) {
                    console.log(`No more pending orders after batch ${i + 1}`)
                    break
                }

                // Small delay between batches to avoid overwhelming the system
                if (i < batchRuns - 1) {
                    await new Promise((resolve) => setTimeout(resolve, 2000))
                }
            } catch (batchError) {
                console.error(`Error in batch ${i + 1}:`, batchError)
                results.push({
                    batch: i + 1,
                    error: batchError instanceof Error ? batchError.message : "Unknown error",
                })
            }
        }

        const totalProcessed = results.reduce((sum, batch) => sum + (batch.processed || 0), 0)
        const totalSuccessful = results.reduce((sum, batch) => sum + (batch.successful || 0), 0)
        const totalFailed = results.reduce((sum, batch) => sum + (batch.failed || 0), 0)

        console.log(`Daily processing completed - Processed: ${totalProcessed}, Successful: ${totalSuccessful}, Failed: ${totalFailed}`)

        return NextResponse.json({
            success: true,
            timestamp: new Date().toISOString(),
            summary: {
                totalProcessed,
                totalSuccessful,
                totalFailed,
                batchCount: results.length,
            },
            batches: results,
        })
    } catch (error) {
        console.error("Error in daily background processing:", error)
        return NextResponse.json(
            {
                success: false,
                error: error instanceof Error ? error.message : "Unknown error",
                timestamp: new Date().toISOString(),
            },
            { status: 500 }
        )
    }
}

// GET /api/cron/process-orders - Health check
export async function GET(request: NextRequest) {
    return NextResponse.json({
        status: "active",
        timestamp: new Date().toISOString(),
        message: "Background order processing cron job is active",
    })
}
