(async () => {
    const sget = (key, def) =>
        browser.storage.session.get(key).then(r => r[key] ?? def).catch(() => def);
    const sset = obj => browser.storage.session.set(obj).catch(() => {});

    try {
        // Focus existing review tab if one is open
        const reviewTabId = await sget('reviewTabId', null);
        if (reviewTabId !== null) {
            try {
                await browser.tabs.update(reviewTabId, { active: true });
                window.close();
                return;
            } catch {} // tab was closed, fall through
        }

        // Gather all bookmarks
        const tree = await browser.bookmarks.getTree();
        const all = [];
        (function walk(nodes) {
            for (const n of nodes) {
                if (n.url) all.push(n);
                if (n.children) walk(n.children);
            }
        })(tree);

        // Filter out kept and already-reviewed this session
        const KEEP_MS = 30 * 24 * 60 * 60 * 1000;
        const now = Date.now();
        const { kept = {} } = await browser.storage.local.get('kept').catch(() => ({}));
        const reviewed = await sget('reviewed', []);
        const skip = new Set(reviewed);

        const pending = all.filter(b =>
            !skip.has(b.id) && !(kept[b.id] && now - kept[b.id] < KEEP_MS)
        );

        if (!pending.length) { window.close(); return; }

        await sset({ reviewed: [] });
        const tab = await browser.tabs.create({ url: pending[0].url });
        await sset({ reviewTabId: tab.id });

    } catch (e) {
        console.error('SafariCleaner:', e);
    }
    window.close();
})();
