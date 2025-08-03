"use client"

import { Order } from "./MarginTradingInterface"

interface OrdersListProps {
    orders: Order[]
    onCancelOrder?: (orderId: string) => Promise<void>
}

export function OrdersList({ orders, onCancelOrder }: OrdersListProps) {
    const getStatusBadge = (status: Order["status"]) => {
        switch (status) {
            case "pending":
                return "badge-warning"
            case "filled":
                return "badge-success"
            case "cancelled":
                return "badge-error"
            default:
                return "badge-neutral"
        }
    }

    const formatTimeAgo = (date: Date) => {
        const now = new Date()
        const diffInMinutes = Math.floor((now.getTime() - date.getTime()) / (1000 * 60))

        if (diffInMinutes < 60) {
            return `${diffInMinutes}m ago`
        } else if (diffInMinutes < 1440) {
            const hours = Math.floor(diffInMinutes / 60)
            return `${hours}h ago`
        } else {
            const days = Math.floor(diffInMinutes / 1440)
            return `${days}d ago`
        }
    }

    const handleCancelOrder = async (orderId: string) => {
        if (onCancelOrder) {
            try {
                await onCancelOrder(orderId)
            } catch (error) {
                console.error("Error cancelling order:", error)
                alert("Failed to cancel order")
            }
        }
    }

    return (
        <div className="card bg-base-200 shadow-xl">
            <div className="card-body">
                <h2 className="card-title">Your Orders</h2>
                {orders.length === 0 ? (
                    <div className="text-center py-8">
                        <p className="text-gray-500">No orders found</p>
                    </div>
                ) : (
                    <div className="space-y-4">
                        {orders.map((order) => (
                            <div key={order.id} className="card bg-base-100 shadow">
                                <div className="card-body p-4">
                                    <div className="flex justify-between items-start">
                                        <div>
                                            <div className="flex items-center gap-2">
                                                <span className={`badge ${order.type === "long" ? "badge-success" : "badge-error"}`}>
                                                    {order.type.toUpperCase()}
                                                </span>
                                                <span className={`badge ${getStatusBadge(order.status)}`}>{order.status.toUpperCase()}</span>
                                            </div>
                                            <div className="text-sm text-gray-600 mt-2">
                                                <div>
                                                    Collateral: {order.collateralAmount} {order.collateralToken.symbol}
                                                </div>
                                                <div>
                                                    Debt: {order.debtAmount} {order.debtToken.symbol}
                                                </div>
                                                <div className="text-xs mt-1">{formatTimeAgo(order.createdAt)}</div>
                                            </div>
                                        </div>
                                    </div>
                                    <div className="card-actions justify-end mt-4">
                                        {order.status === "pending" && (
                                            <>
                                                <button className="btn btn-sm btn-outline">View</button>
                                                {onCancelOrder && (
                                                    <button className="btn btn-sm btn-error" onClick={() => handleCancelOrder(order.id)}>
                                                        Cancel
                                                    </button>
                                                )}
                                            </>
                                        )}
                                        {order.status === "filled" && <button className="btn btn-sm btn-outline">View Position</button>}
                                        {order.status === "cancelled" && <button className="btn btn-sm btn-outline">View Details</button>}
                                    </div>
                                </div>
                            </div>
                        ))}
                    </div>
                )}
            </div>
        </div>
    )
}
