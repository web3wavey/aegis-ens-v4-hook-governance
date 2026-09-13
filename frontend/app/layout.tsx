import "./globals.css";

export const metadata = {
  title: "Aegis — ENSv2 × Uniswap v4",
  description: "Live ENSv2 governance for a Uniswap v4 pool",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
