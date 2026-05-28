(function () {
    if (document.getElementById('swipe-host')) return;

    const host = document.createElement('div');
    host.id = 'swipe-host';
    host.style.cssText = 'position:fixed;top:0;left:0;right:0;height:44px;z-index:2147483647;';
    document.body.appendChild(host);

    const shadow = host.attachShadow({ mode: 'open' });
    shadow.innerHTML = `
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
#bar {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 0 14px;
    height: 44px;
    background: rgba(30, 30, 32, 0.96);
    backdrop-filter: saturate(180%) blur(20px);
    -webkit-backdrop-filter: saturate(180%) blur(20px);
    border-bottom: 0.5px solid rgba(255,255,255,0.12);
    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
    color: rgba(255,255,255,0.88);
    font-size: 13px;
}
.icon { flex-shrink: 0; }
.name {
    flex: 1;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    font-weight: 500;
    transition: opacity 0.12s;
}
.name.fade { opacity: 0; }
.count { font-size: 11px; color: rgba(255,255,255,0.38); flex-shrink: 0; white-space: nowrap; }
button {
    flex-shrink: 0;
    border: none;
    border-radius: 7px;
    padding: 0 14px;
    height: 28px;
    font-family: inherit;
    font-size: 13px;
    font-weight: 600;
    cursor: pointer;
    color: white;
    transition: filter 0.1s;
}
button:hover { filter: brightness(1.15); }
button:active { filter: brightness(0.85); }
#btn-keep   { background: #34C759; }
#btn-delete { background: #FF3B30; }
#btn-close  { background: rgba(255,255,255,0.12); color: rgba(255,255,255,0.55); padding: 0 10px; font-size: 17px; font-weight: 300; }
#done { flex: 1; text-align: center; color: rgba(255,255,255,0.4); font-size: 12px; }
</style>
<div id="bar">
    <svg class="icon" width="11" height="13" viewBox="0 0 11 13" fill="rgba(255,255,255,0.6)">
        <path d="M0.5 0.5h10v11.5l-5-2.8-5 2.8V0.5z"/>
    </svg>
    <span class="name" id="name">Loading…</span>
    <span class="count" id="count"></span>
    <button id="btn-keep">Keep</button>
    <button id="btn-delete">Delete</button>
    <button id="btn-close">✕</button>
</div>`;

    const bar     = shadow.getElementById('bar');
    const nameEl  = shadow.getElementById('name');
    const countEl = shadow.getElementById('count');

    const pageStyle = document.createElement('style');
    document.head.appendChild(pageStyle);

    let current = null;

    function hide() {
        host.style.display = 'none';
        pageStyle.textContent = '';
    }

    function update({ bookmark, remaining }) {
        if (!bookmark) { hide(); return; }

        nameEl.classList.add('fade');
        requestAnimationFrame(() => {
            current = bookmark;
            nameEl.textContent = bookmark.title;
            countEl.textContent = remaining === 1 ? '1 left' : `${remaining} left`;
            host.style.display = '';
            pageStyle.textContent = 'html{margin-top:44px!important}';
            nameEl.classList.remove('fade');
        });
    }

    function msg(type) {
        browser.runtime.sendMessage({ type, id: current?.id })
            .then(update)
            .catch(hide);
    }

    shadow.getElementById('btn-keep').onclick   = () => current && msg('KEEP');
    shadow.getElementById('btn-delete').onclick = () => current && msg('DELETE');
    shadow.getElementById('btn-close').onclick  = () => {
        hide();
        browser.runtime.sendMessage({ type: 'CLOSE_SESSION' }).catch(() => {});
    };

    browser.runtime.sendMessage({ type: 'NEXT' }).then(update).catch(hide);
})();
