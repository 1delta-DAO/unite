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

// MarginSettler ABI (simplified for filling)
const MARGIN_SETTLER_ABI = ["function flashLoanFill(address asset, uint256 amount, bytes calldata params) external"]

import { SwapService } from "@/services/swapService"

// Initialize swap service
const swapService = new SwapService()

// Create taker traits for the fill transaction
function createTakerTraits(extensionLength: number, swapDataLength: number): string {
    return swapService.createTakerTraits(extensionLength, swapDataLength)
}

// Create swap routing data using SwapService
function createSwapRouting(fromToken: string, toToken: string, amount: string, recipient: string): string {
    return swapService.createSwapRouting(fromToken, toToken, amount, recipient)
}

// POST /api/orders/[orderId]/fill - Fill an order
export async function POST(request: NextRequest, { params }: { params: Promise<{ orderId: string }> }) {
    try {
        const { orderId } = await params

        // Get order
        const order = (await kv.get(`order:${orderId}`)) as Order
        if (!order) {
            return NextResponse.json({ error: "Order not found" }, { status: 404 })
        }

        if (order.status !== "pending") {
            return NextResponse.json(
                {
                    error: `Order is not pending (current status: ${order.status})`,
                },
                { status: 400 }
            )
        }

        // Update status to filling
        const fillingOrder: Order = { ...order, status: "filling" }
        await kv.set(`order:${orderId}`, fillingOrder)
        await kv.srem("pending_orders", orderId)
        await kv.sadd("filling_orders", orderId)

        try {
            // Initialize provider and signer
            const rpcUrl = process.env.ARBITRUM_RPC_URL || "https://arb1.arbitrum.io/rpc"
            const privateKey = process.env.RELAYER_PRIVATE_KEY

            if (!privateKey) {
                throw new Error("RELAYER_PRIVATE_KEY not configured")
            }

            const provider = new ethers.JsonRpcProvider(rpcUrl)
            const signer = new ethers.Wallet(privateKey, provider)

            const marginSettlerAddress = process.env.MARGIN_SETTLER_ADDRESS || order.order.receiver
            const marginSettlerContract = new ethers.Contract(marginSettlerAddress, MARGIN_SETTLER_ABI, signer)

            // Create swap calldata for the fill
            const swapCalldata = createSwapRouting(
                order.order.takerAsset,
                order.order.makerAsset,
                order.order.takingAmount,
                await signer.getAddress()
            )

            // Create taker traits
            const takerTraits = createTakerTraits(order.extensionCalldata.length, swapCalldata.length)

            // Combine extension and swap data
            const combinedArgs = ethers.concat([order.extensionCalldata, swapCalldata])

            // Encode flash loan parameters
            const flashLoanParams = ethers.AbiCoder.defaultAbiCoder().encode(
                ["tuple(uint256,address,address,address,address,uint256,uint256,uint256)", "bytes", "uint256", "uint256", "bytes", "bytes"],
                [
                    [
                        order.order.salt,
                        order.order.maker,
                        order.order.receiver,
                        order.order.makerAsset,
                        order.order.takerAsset,
                        order.order.makingAmount,
                        order.order.takingAmount,
                        order.order.makerTraits,
                    ],
                    order.orderSignature,
                    order.order.takingAmount,
                    takerTraits,
                    combinedArgs,
                    order.extensionSignature,
                ]
            )

            // Prepend filler address to flash loan params
            const fillerAddress = await signer.getAddress()
            const finalParams = ethers.concat([fillerAddress, flashLoanParams])

            // Execute flash loan fill
            console.log(`Filling order ${orderId} with flash loan...`)
            const tx = await marginSettlerContract.flashLoanFill(
                order.order.makerAsset, // Asset to flash loan
                order.order.makingAmount, // Amount to flash loan
                finalParams,
                {
                    gasLimit: 1000000, // Set appropriate gas limit
                }
            )

            console.log(`Transaction sent: ${tx.hash}`)

            // Wait for confirmation
            const receipt = await tx.wait()
            console.log(`Transaction confirmed in block ${receipt.blockNumber}`)

            // Update order as filled
            const filledOrder: Order = {
                ...order,
                status: "filled",
                filledAt: Date.now(),
                txHash: tx.hash,
            }

            await kv.set(`order:${orderId}`, filledOrder)
            await kv.srem("filling_orders", orderId)
            await kv.sadd("filled_orders", orderId)

            return NextResponse.json({
                success: true,
                txHash: tx.hash,
                blockNumber: receipt.blockNumber,
                order: filledOrder,
            })
        } catch (fillError: any) {
            console.error(`Error filling order ${orderId}:`, fillError)

            // Update order as failed
            const failedOrder: Order = {
                ...order,
                status: "failed",
                errorMessage: fillError.message || "Unknown error during fill",
            }

            await kv.set(`order:${orderId}`, failedOrder)
            await kv.srem("filling_orders", orderId)
            await kv.sadd("failed_orders", orderId)

            return NextResponse.json(
                {
                    success: false,
                    error: fillError.message,
                    order: failedOrder,
                },
                { status: 500 }
            )
        }
    } catch (error) {
        console.error("Error in fill endpoint:", error)
        return NextResponse.json({ error: "Internal server error" }, { status: 500 })
    }
}
