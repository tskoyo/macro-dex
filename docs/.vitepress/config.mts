import { defineConfig } from "vitepress";

export default defineConfig({
    //   title: "Farmer's Market",
    title: "Macro DEX",
    description: "Sell tokens at a fixed price. No admin, no fees, no surprises.",
    base: "/macro-dex/",
    cleanUrls: true,
    lastUpdated: true,
    themeConfig: {
        nav: [
            { text: "Guide", link: "/guide/what-is-it" },
            { text: "Integration", link: "/integration/overview" },
            { text: "Reference", link: "/reference/contracts" },
        ],
        sidebar: [
            {
                text: "Guide",
                items: [
                    { text: "What is it?", link: "/guide/what-is-it" },
                    { text: "How it works", link: "/guide/how-it-works" },
                    { text: "Why it's safe", link: "/guide/safety" },
                    { text: "Glossary", link: "/guide/glossary" },
                ],
            },
            {
                text: "Frontend integration",
                items: [
                    { text: "Overview", link: "/integration/overview" },
                    { text: "Reading orders", link: "/integration/reading" },
                    { text: "Placing an order", link: "/integration/placing" },
                    { text: "Buying an order", link: "/integration/buying" },
                    { text: "Reclaiming an order", link: "/integration/reclaiming" },
                    { text: "Handling errors", link: "/integration/errors" },
                    { text: "Local setup", link: "/integration/local-setup" },
                ],
            },
            {
                text: "Reference",
                items: [{ text: "Contracts", link: "/reference/contracts" }],
            },
        ],
        search: { provider: "local" },
        socialLinks: [{ icon: "github", link: "https://github.com/tskoyo/macro-dex" }],
        editLink: {
            pattern: "https://github.com/tskoyo/macro-dex/edit/main/docs/:path",
        },
    },
});
