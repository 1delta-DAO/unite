import type { Metadata } from "next"
import { Inter } from "next/font/google"
import "./globals.css"
import { Providers } from "./providers"

const inter = Inter({ subsets: ["latin"] })

export const metadata: Metadata = {
    title: "1Delta Unite",
    description: "Limit order margin trading",
}

export default function RootLayout({
    children,
}: Readonly<{
    children: React.ReactNode
}>) {
    return (
        <html lang="en" data-theme="dark">
            <body className={inter.className}>
                <Providers>{children}</Providers>
            </body>
        </html>
    )
}
