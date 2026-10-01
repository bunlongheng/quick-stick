import type { NextConfig } from "next";
import { networkInterfaces } from "node:os";

// The dev server refuses its own assets to any origin it was not told about,
// so a phone on the LAN got a page with no script and no notes. Every
// address this machine answers on is a fine origin.
const lanHosts = Object.values(networkInterfaces())
    .flat()
    .filter((n) => n && n.family === "IPv4" && !n.internal)
    .map((n) => n!.address);

const nextConfig: NextConfig = {
    devIndicators: false,
    allowedDevOrigins: [...lanHosts, "*.local"],
};

export default nextConfig;
