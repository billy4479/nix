import asyncio

from playwright.async_api import async_playwright


async def main():
    # Starting Playwright exercises the Node driver and its RPC transport,
    # without downloading or launching a browser.
    async with async_playwright() as playwright:
        assert playwright.firefox.name == "firefox"


asyncio.run(main())
