(async () => {
    try {
        await browser.runtime.sendMessage({ type: 'TOOLBAR_CLICKED' });
    } catch {}
    window.close();
})();
