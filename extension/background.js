const KEEP_MS = 30 * 24 * 60 * 60 * 1000;

async function getAllBookmarks() {
    const tree = await browser.bookmarks.getTree();
    const results = [];
    (function flatten(nodes) {
        for (const node of nodes) {
            if (node.url) results.push({ id: node.id, title: node.title || node.url, url: node.url });
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

async function markSessionReviewed(id) {
    try {
        const { reviewed = [] } = await browser.storage.session.get('reviewed');
        if (!reviewed.includes(id)) {
            await browser.storage.session.set({ reviewed: [...reviewed, id] });
        }
    } catch {}
}

async function nextBookmark() {
    const [allBookmarks, kept, sessionReviewed] = await Promise.all([
        getAllBookmarks(),
        getKept(),
        getSessionReviewed()
    ]);
    const pending = allBookmarks.filter(b => !kept[b.id] && !sessionReviewed.has(b.id));
    return { bookmark: pending[0] ?? null, remaining: pending.length };
}

async function getReviewTabId() {
    try {
        const { reviewTabId = null } = await browser.storage.session.get('reviewTabId');
        return reviewTabId;
    } catch { return null; }
}

async function setReviewTabId(id) {
    try { await browser.storage.session.set({ reviewTabId: id }); } catch {}
}

// Toolbar button: open a review tab, or focus the existing one
async function handleToolbarClick() {
    const existing = await getReviewTabId();
    if (existing) {
        try {
            await browser.tabs.update(existing, { active: true });
            return;
        } catch {} // tab was closed; fall through
    }

    try { await browser.storage.session.set({ reviewed: [] }); } catch {}

    const { bookmark } = await nextBookmark();
    if (!bookmark) return;

    const tab = await browser.tabs.create({ url: bookmark.url });
    await setReviewTabId(tab.id);
}

// Inject content script when the review tab finishes loading
browser.tabs.onUpdated.addListener(async (tabId, changeInfo) => {
    if (changeInfo.status !== 'complete') return;
    const reviewTabId = await getReviewTabId();
    if (tabId !== reviewTabId) return;
    try {
        await browser.scripting.executeScript({ target: { tabId }, files: ['content.js'] });
    } catch {}
});

// Clean up when the review tab is closed
browser.tabs.onRemoved.addListener(async (tabId) => {
    const reviewTabId = await getReviewTabId();
    if (tabId === reviewTabId) await setReviewTabId(null);
});

async function advanceReview() {
    const { bookmark, remaining } = await nextBookmark();
    if (!bookmark) {
        await setReviewTabId(null);
        return { bookmark: null, remaining: 0 };
    }
    const tabId = await getReviewTabId();
    if (tabId) await browser.tabs.update(tabId, { url: bookmark.url });
    return { bookmark: null, remaining };
}

browser.runtime.onMessage.addListener(async ({ type, id }) => {
    if (type === 'TOOLBAR_CLICKED') {
        await handleToolbarClick();
        return { ok: true };
    }

    if (type === 'NEXT') return nextBookmark();

    if (type === 'KEEP') {
        const { kept = {} } = await browser.storage.local.get('kept');
        kept[id] = Date.now();
        await browser.storage.local.set({ kept });
        await markSessionReviewed(id);
        return advanceReview();
    }

    if (type === 'DELETE') {
        try { await browser.bookmarks.remove(id); } catch {}
        await markSessionReviewed(id);
        return advanceReview();
    }

    if (type === 'CLOSE_SESSION') {
        await setReviewTabId(null);
        return { ok: true };
    }
});
