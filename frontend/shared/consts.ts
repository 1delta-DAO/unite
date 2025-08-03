export interface Token {
    address: string
    symbol: string
    decimals: number
    logoURI?: string
}

export const TOKENS: Token[] = [
    {
        address: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1", // WETH
        symbol: "WETH",
        decimals: 18,
    },
    {
        address: "0xaf88d065e77c8cc2239327c5edb3a432268e5831", // USDC
        symbol: "USDC",
        decimals: 6,
    },
    {
        address: "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9", // USDT
        symbol: "USD₮0",
        decimals: 6,
    },
    {
        address: "0x2f2a2543b76a4166549f7aab2e75bef0aefc5b0f", // WBTC
        symbol: "WBTC",
        decimals: 8,
    },
    {
        address: "0x912CE59144191C1204E64559FE8253a0e49E6548", // ARB
        symbol: "ARB",
        decimals: 18,
    },
    {
        address: "0x5979d7b546e38e414f7e9822514be443a4800529", // wstETH
        symbol: "wstETH",
        decimals: 18,
    },
    {
        address: "0xf97f4df75117a78c1a5a0dbb814af92458539fb4", // LINK
        symbol: "LINK",
        decimals: 18,
    },
    {
        address: "0x35751007a407ca6feffe80b3cb397736d2cf4dbe", // weETH
        symbol: "weETH",
        decimals: 18,
    },
    {
        address: "0xda10009cbd5d07dd0cecc66161fc93d7c9000da1", // DAI
        symbol: "DAI",
        decimals: 18,
    },
    {
        address: "0x7dff72693f6a4149b17e7c6314655f6a9f7c8b33", // GHO
        symbol: "GHO",
        decimals: 18,
    },
    {
        address: "0xff970a61a04b1ca14834a43f5de4533ebddb5cc8", // USDC.e
        symbol: "USDC.e",
        decimals: 6,
    },
]

export async function loadTokenData(): Promise<Token[]> {
    try {
        const response = await fetch("/42161.json")
        const data = await response.json()

        const tokenMap = new Map<string, Token>()

        TOKENS.forEach((token) => {
            tokenMap.set(token.address.toLowerCase(), token)
        })

        Object.values(data.list).forEach((tokenData: any) => {
            const address = tokenData.address.toLowerCase()
            if (tokenMap.has(address)) {
                const existingToken = tokenMap.get(address)!
                existingToken.logoURI = tokenData.logoURI
            }
        })

        return Array.from(tokenMap.values())
    } catch (error) {
        console.error("Failed to load token data:", error)
        return TOKENS
    }
}
