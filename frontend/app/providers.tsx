"use client"

import { RainbowKitProvider, getDefaultWallets } from "@rainbow-me/rainbowkit"
import "@rainbow-me/rainbowkit/styles.css"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { WagmiProvider, createConfig, http } from "wagmi"
import { arbitrum } from "wagmi/chains"

const { wallets } = getDefaultWallets({
    appName: "1Delta Margin Trading",
    projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID!,
})

const config = createConfig({
    chains: [arbitrum],
    transports: {
        [arbitrum.id]: http(),
    },
})

const queryClient = new QueryClient()

export function Providers({ children }: { children: React.ReactNode }) {
    return (
        <WagmiProvider config={config}>
            <QueryClientProvider client={queryClient}>
                <RainbowKitProvider>{children}</RainbowKitProvider>
            </QueryClientProvider>
        </WagmiProvider>
    )
}
