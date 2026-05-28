const KEEP_MS = 30 * 24 * 60 * 60 * 1000;

async function getAllBookmarks() {
    const tree = await browser.bookmarks.getTree();
    const results = [];
    (function flatten(nodes) {
        for (const node of nodes) {
            if (node.url) results.push({ id: node.id, title: node.title || node.url });
            if (node.children) flatten(node.children);
        }
    })(tree);
    return results;
}

async function getKept() {
    const { kept = {} } = await browser.storage.local.get('kept');
    const now = Date.now();
    let changed = false;
    for (const id of Object.keys(kept)) {
        if (now - kept[id] >= KEEP_MS) { delete kept[id]; changed = true; }
    }
    if (changed) await browser.storage.local.set({ kept });
    return kept;
}

async function getSessionReviewed() {
    try {
        const { reviewed = [] } = await browser.storage.session.get('reviewed');
        return new Set(reviewed);
    } catch { return new Set(); }
}

async function getSessionClosed() {
    try {
        const { closed = false } = await browser.storage.session.get('closed');
        return closed;
    } catch { return false; }
}

async function markSessionReviewed(id) {
    try {
        const { reviewed = [] } = await browser.storage.session.get('reviewed');
        if (!reviewed.includes(id)) {
            await browser.storage.session.set({ reviewed: [...reviewed, id] });
        }
    } catch {}
}

async function nextBookmark() {
    if (await getSessionClosed()) return { bookmark: null, remaining: 0 };

    const [allBookmarks, kept, sessionReviewed] = await Promise.all([
        getAllBookmarks(),
        getKept(),
        getSessionReviewed()
    ]);
    const pending = allBookmarks.filter(b => !kept[b.id] && !sessionReviewed.has(b.id));
    return { bookmark: pending[0] ?? null, remaining: pending.length };
}

browser.runtime.onMessage.addListener(async ({ type, id }) => {
    if (type === 'NEXT') return nextBookmark();

    if (type === 'KEEP') {
        const { kept = {} } = await browser.storage.local.get('kept');
        kept[id] = Date.now();
        await browser.storage.local.set({ kept });
        await markSessionReviewed(id);
        return nextBookmark();
    }

    if (type === 'DELETE') {
        try { await browser.bookmarks.remove(id); } catch {}
        await markSessionReviewed(id);
        return nextBookmark();
    }

    if (type === 'CLOSE_SESSION') {
        try { await browser.storage.session.set({ closed: true }); } catch {}
        return { ok: true };
    }
});
