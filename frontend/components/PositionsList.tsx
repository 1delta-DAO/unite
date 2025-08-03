"use client"

import { Position } from "./MarginTradingInterface"

interface PositionsListProps {
    positions: Position[]
    onClosePosition?: (positionId: string) => Promise<void>
}

export function PositionsList({ positions, onClosePosition }: PositionsListProps) {
    const getHealthFactorColor = (healthFactor: string) => {
        const hf = parseFloat(healthFactor)
        if (hf < 1.2) return "text-error"
        if (hf < 1.5) return "text-warning"
        return "text-success"
    }

    const handleClosePosition = async (positionId: string) => {
        if (onClosePosition) {
            try {
                await onClosePosition(positionId)
            } catch (error) {
                console.error("Error closing position:", error)
                alert("Failed to close position")
            }
        }
    }

    return (
        <div className="card bg-base-200 shadow-xl">
            <div className="card-body">
                <h2 className="card-title">Your Positions</h2>
                {positions.length === 0 ? (
                    <div className="text-center py-8">
                        <p className="text-gray-500">No positions found</p>
                    </div>
                ) : (
                    <div className="space-y-4">
                        {positions.map((position) => (
                            <div key={position.id} className="card bg-base-100 shadow">
                                <div className="card-body p-4">
                                    <div className="flex justify-between items-start">
                                        <div>
                                            <div className="flex items-center gap-2">
                                                <span className={`badge ${position.type === "long" ? "badge-success" : "badge-error"}`}>
                                                    {position.type.toUpperCase()}
                                                </span>
                                                <span className="font-medium">
                                                    {position.collateralToken.symbol}/{position.debtToken.symbol}
                                                </span>
                                            </div>
                                            <div className="text-sm text-gray-600 mt-2">
                                                <div>
                                                    Collateral: {position.collateralAmount} {position.collateralToken.symbol}
                                                </div>
                                                <div>
                                                    Debt: {position.debtAmount} {position.debtToken.symbol}
                                                </div>
                                            </div>
                                        </div>
                                        <div className="text-right">
                                            <div className={`font-bold ${getHealthFactorColor(position.healthFactor)}`}>
                                                HF: {position.healthFactor}
                                            </div>
                                            <div className="text-xs text-gray-500">LT: {position.liquidationThreshold}</div>
                                        </div>
                                    </div>
                                    <div className="card-actions justify-end mt-4">
                                        <button className="btn btn-sm btn-outline">View Details</button>
                                        {onClosePosition && (
                                            <button className="btn btn-sm btn-error" onClick={() => handleClosePosition(position.id)}>
                                                Close
                                            </button>
                                        )}
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
