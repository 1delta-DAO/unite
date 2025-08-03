"use client"

import { Position } from "./MarginTradingInterface"

interface PositionCardProps {
    position: Position
    onClose?: () => void
    onViewDetails?: () => void
}

export function PositionCard({ position, onClose, onViewDetails }: PositionCardProps) {
    const getHealthFactorColor = (healthFactor: string) => {
        const hf = parseFloat(healthFactor)
        if (hf < 1.2) return "text-error"
        if (hf < 1.5) return "text-warning"
        return "text-success"
    }

    return (
        <div className="card bg-base-100 shadow-xl">
            <div className="card-body">
                <div className="flex justify-between items-start">
                    <div>
                        <div className="flex items-center gap-2 mb-2">
                            <span className={`badge ${position.type === "long" ? "badge-success" : "badge-error"}`}>
                                {position.type.toUpperCase()}
                            </span>
                            <span className="font-bold text-lg">
                                {position.collateralToken.symbol}/{position.debtToken.symbol}
                            </span>
                        </div>

                        <div className="grid grid-cols-2 gap-4 mt-4">
                            <div>
                                <h3 className="font-semibold text-sm text-gray-600">Collateral</h3>
                                <p className="text-lg font-bold">
                                    {position.collateralAmount} {position.collateralToken.symbol}
                                </p>
                            </div>
                            <div>
                                <h3 className="font-semibold text-sm text-gray-600">Debt</h3>
                                <p className="text-lg font-bold">
                                    {position.debtAmount} {position.debtToken.symbol}
                                </p>
                            </div>
                        </div>

                        <div className="grid grid-cols-2 gap-4 mt-4">
                            <div>
                                <h3 className="font-semibold text-sm text-gray-600">Health Factor</h3>
                                <p className={`text-lg font-bold ${getHealthFactorColor(position.healthFactor)}`}>{position.healthFactor}</p>
                            </div>
                            <div>
                                <h3 className="font-semibold text-sm text-gray-600">Liquidation Threshold</h3>
                                <p className="text-lg font-bold">{position.liquidationThreshold}</p>
                            </div>
                        </div>
                    </div>
                </div>

                <div className="card-actions justify-end mt-6">
                    {onViewDetails && (
                        <button className="btn btn-outline" onClick={onViewDetails}>
                            View Details
                        </button>
                    )}
                    {onClose && (
                        <button className="btn btn-error" onClick={onClose}>
                            Close Position
                        </button>
                    )}
                </div>
            </div>
        </div>
    )
}
