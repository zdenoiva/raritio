// --- State Management ---
const DEFAULT_BINDER_NAME = 'Môj balík';
const BINDER_SORT_MODES = ['custom', 'name', 'rarity', 'price_desc', 'price_asc', 'recent', 'set'];
const BINDER_SORT_OPTIONS = [
    { value: 'custom', label: 'Vlastné', icon: '≡', description: 'Presne tak, ako si karty uložil.' },
    { value: 'name', label: 'Abecedne', icon: 'A', description: 'Podľa názvu karty od A po Z.' },
    { value: 'rarity', label: 'Podľa rarity', icon: '✦', description: 'Najvzácnejšie karty hore.' },
    { value: 'price_desc', label: 'Cena ↓', icon: '$↓', description: 'Najdrahšie karty hore.' },
    { value: 'price_asc', label: 'Cena ↑', icon: '$↑', description: 'Najlacnejšie karty hore.' },
    { value: 'recent', label: 'Najnovšie', icon: '◷', description: 'Naposledy pridané karty hore.' },
    { value: 'set', label: 'Podľa edície', icon: '▤', description: 'Edícia a číslo karty.' }
];

const DEFAULT_SETTINGS = {
    rarityFrames: true,
    gameBadges: true,
    foilBadges: true,
    glowEffect: true,
    holoEffect: true,
    priceCharting: true,
    autoBackup: true,
    glowThreshold: 20
};

function createDefaultState() {
    return {
        binders: [
            {
                id: 'binder_1',
                name: DEFAULT_BINDER_NAME,
                cards: [],
                priceHistory: [],
                sortMode: 'custom'
            }
        ],
        currentBinderId: 'binder_1',
        collectionHistory: [],
        settings: { ...DEFAULT_SETTINGS }
    };
}

let state = createDefaultState();
state.searchResults = [];
state.sharedBinders = [];
state.binderLikes = {};

const FALLBACK_IMAGE = "data:image/svg+xml;charset=UTF-8,%3Csvg xmlns='http://www.w3.org/2000/svg' width='150' height='210' viewBox='0 0 150 210'%3E%3Crect width='150' height='210' fill='%231e1e24'/%3E%3Ctext x='50%25' y='50%25' dominant-baseline='middle' text-anchor='middle' fill='%2394a3b8' font-family='sans-serif' font-size='12'%3ENo Image%3C/text%3E%3C/svg%3E";

// Where to return when the card modal is closed ('search' or null for binder)
let cardModalReturnTo = null;
// Card currently shown in the preview modal
let previewCardId = null;
let isScanning = false;
let stateHydrated = false;
let saveTimer = null;
let lastPriceRefresh = 0;
let priceSpinTimer = null;
let dataBusy = false;
let editingBinderId = null;
let binderActionsId = null;
let searchRequestId = 0;
let overviewBinderId = null;
let reorderMode = false;
let sharedSyncTimer = null;
let cardNodes = new Map();
let valueSnapshotTimer = null;
let autoBackupRequested = false;
const priceChartingRequests = new Set();
let holoTiltBound = false;
let holoTiltFrame = null;
let holoTiltBase = { beta: null, gamma: null };
let holoLastOrientation = { beta: 0, gamma: 0, known: false };
let lastBinderLikesAt = {};

// --- Helpers ---
function getCurrentBinder() {
    return state.binders.find(b => b.id === state.currentBinderId);
}

function escapeHtml(value) {
    return String(value ?? '').replace(/[&<>"']/g, char => ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#39;'
    }[char]));
}

const LANGUAGE_META = {
    en: { flag: '🇬🇧', label: 'Angličtina' },
    ja: { flag: '🇯🇵', label: 'Japončina' },
    'zh-cn': { flag: '🇨🇳', label: 'Čínština (zjednodušená)' },
    'zh-tw': { flag: '🇹🇼', label: 'Čínština (tradičná)' },
    ko: { flag: '🇰🇷', label: 'Kórejčina' }
};

function normalizeLanguage(value) {
    const lang = String(value || 'en').trim().toLowerCase().replace(/_/g, '-');
    if (!lang || lang === 'auto') return 'en';
    if (lang.startsWith('en')) return 'en';
    if (lang.startsWith('ja')) return 'ja';
    if (lang.startsWith('zh-hant') || lang === 'zh-tw') return 'zh-tw';
    if (lang.startsWith('zh')) return 'zh-cn';
    if (lang.startsWith('ko')) return 'ko';
    return lang;
}

function languageMeta(value) {
    const key = normalizeLanguage(value);
    return LANGUAGE_META[key] || { flag: '🌐', label: 'Neznámy jazyk' };
}

function languageFlag(value) {
    return languageMeta(value).flag;
}

function languageLabel(value) {
    return languageMeta(value).label;
}

function detectLanguage(text) {
    const value = String(text || '');
    if (/[\u3040-\u30ff]/.test(value)) return 'ja';
    if (/[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]/.test(value)) return 'zh-cn';
    return 'en';
}

function imageSource(uri) {
    const value = String(uri || '').trim();
    return value.length > 0 ? escapeHtml(value) : FALLBACK_IMAGE;
}

function normalizeRarity(value) {
    const text = String(value || '').trim();
    if (!text || /^(none|unknown|n\/a)$/i.test(text)) return 'Neznáma';
    return text;
}

function normalizeSettings(raw) {
    const safe = raw && typeof raw === 'object' ? raw : {};
    const settings = { ...DEFAULT_SETTINGS };
    Object.keys(DEFAULT_SETTINGS).forEach(key => {
        if (key === 'glowThreshold') {
            const value = Number(safe[key]);
            if (Number.isFinite(value) && value > 0) settings[key] = value;
        } else if (typeof safe[key] === 'boolean') {
            settings[key] = safe[key];
        }
    });
    return settings;
}

function normalizeHistory(value) {
    if (!Array.isArray(value)) return [];
    return value
        .filter(point => point && point.date && Number.isFinite(Number(point.price)))
        .map(point => ({
            date: String(point.date).slice(0, 10),
            price: Number(point.price),
            source: ['cardmarket', 'pricecharting', 'local'].includes(point.source)
                ? point.source
                : 'local'
        }))
        .filter(point => point.price > 0)
        .sort((a, b) => a.date.localeCompare(b.date))
        .slice(-60);
}

function cardKey(card) {
    return `${card.game || 'pokemon'}:${normalizeLanguage(card.language)}:${card.id}`;
}

function gameLabel(game) {
    return String(game || '').toLowerCase() === 'mtg' ? 'MTG' : 'Pokémon';
}

function gameClass(game) {
    return String(game || '').toLowerCase() === 'mtg' ? 'mtg' : 'pokemon';
}

function isMtgCard(card) {
    return String(card && card.game || '').toLowerCase() === 'mtg';
}

function rarityColor(rarity) {
    const value = String(rarity || '').toLowerCase();
    if (/secret|rainbow|hyper/.test(value)) return '#f472b6';
    if (/special illustration|illustration rare|alt art/.test(value)) return '#a78bfa';
    if (/ultra|gold|vmax|vstar|ex\b|gx\b/.test(value)) return '#f59e0b';
    if (/holo|foil/.test(value)) return '#8b5cf6';
    if (/promo/.test(value)) return '#ec4899';
    if (/rare/.test(value)) return '#3b82f6';
    if (/uncommon/.test(value)) return '#22c55e';
    if (/common/.test(value)) return '#94a3b8';
    return '#64748b';
}

const FINISH_ALIASES = {
    nonfoil: 'normal',
    holofoil: 'holo',
    'holo foil': 'holo',
    'reverse holofoil': 'reverse',
    'reverse holo': 'reverse',
    'reverse-holo': 'reverse',
    texture: 'textured',
    'textured foil': 'textured',
    'cosmos holo': 'cosmos',
    'cosmos foil': 'cosmos',
    'rainbow rare': 'rainbow',
    rainbowrare: 'rainbow',
    'rainbow foil': 'rainbow',
    'gold card': 'gold',
    goldcard: 'gold',
    'gold foil': 'gold',
    'first edition': 'firstEdition',
    '1st edition': 'firstEdition',
    firstedition: 'firstEdition',
    '1stedition': 'firstEdition'
};

function normalizeFinish(value) {
    const finish = String(value || '').toLowerCase().trim();
    if (!finish) return '';
    return FINISH_ALIASES[finish] || finish;
}

function finishList(card) {
    const raw = Array.isArray(card.finishes) ? card.finishes : [];
    const list = raw.map(normalizeFinish).filter(Boolean);
    const explicit = normalizeFinish(card.finish);
    if (list.length === 0 && explicit) list.push(explicit);
    if (list.length === 0 && card.foil) list.push('holo');
    return Array.from(new Set(list));
}

function primaryFinish(card) {
    const list = finishList(card);
    for (const preferred of ['rainbow', 'gold', 'cosmos', 'textured', 'etched', 'holo', 'foil', 'normal', 'reverse', 'firstEdition']) {
        if (list.includes(preferred)) return preferred;
    }
    return normalizeFinish(card.finish);
}

function finishLabel(card) {
    const finish = primaryFinish(card);
    if (!finish || finish === 'normal') return '';
    const labels = {
        firstEdition: '1st Edition',
        reverse: 'Reverse Holo',
        holo: 'Holo',
        foil: 'Foil',
        cosmos: 'Cosmos',
        textured: 'Texture',
        rainbow: 'Rainbow',
        gold: 'Gold',
        etched: 'Etched'
    };
    return labels[finish] || finish.charAt(0).toUpperCase() + finish.slice(1);
}

function finishClass(finish) {
    return String(finish || '')
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-+|-+$/g, '');
}

function isHighValue(card) {
    return (Number(card.currentPrice) || 0) >= Number(state.settings.glowThreshold || 20);
}

function cardHasHolo(card) {
    const finish = primaryFinish(card);
    return finish && finish !== 'normal' && finish !== 'firstEdition';
}

// --- Persistence ---
function serializableState() {
    return {
        binders: state.binders,
        currentBinderId: state.currentBinderId,
        collectionHistory: state.collectionHistory || [],
        settings: state.settings || { ...DEFAULT_SETTINGS }
    };
}

function saveState() {
    if (!stateHydrated || !window.flutterBridge) return;
    try {
        window.flutterBridge.postMessage('saveState:' + JSON.stringify(serializableState()));
        scheduleSharedSync();
    } catch (e) {
        console.error('saveState failed', e);
    }
}

function saveStateDebounced() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(saveState, 400);
}

function sharedBinderSnapshot(binder) {
    return {
        binderId: binder.id,
        name: binder.name,
        updatedAt: new Date().toISOString(),
        cards: binder.cards.map(card => {
            const imageUri = String(card.imageUri || '');
            return {
                id: String(card.id || ''),
                name: String(card.name || ''),
                set: String(card.set || ''),
                setId: String(card.setId || ''),
                game: String(card.game || 'pokemon'),
                language: normalizeLanguage(card.language),
                currentPrice: Number(card.currentPrice) || 0,
                rarity: String(card.rarity || ''),
                imageUri: imageUri.startsWith('data:') ? '' : imageUri,
                finish: String(card.finish || ''),
                finishes: Array.isArray(card.finishes) ? card.finishes : [],
                number: String(card.number || ''),
                artist: String(card.artist || ''),
                addedAt: String(card.addedAt || '')
            };
        })
    };
}

function scheduleSharedSync() {
    if (!stateHydrated || !window.flutterBridge) return;
    if (!state.binders.some(binder => binder.sharedId)) return;
    clearTimeout(sharedSyncTimer);
    sharedSyncTimer = setTimeout(syncSharedBinders, 1500);
}

function syncSharedBinders() {
    if (!stateHydrated || !window.flutterBridge) return;
    const binders = state.binders
        .filter(binder => binder.sharedId)
        .map(binder => ({
            id: binder.sharedId,
            localId: binder.id,
            name: binder.name,
            snapshot: sharedBinderSnapshot(binder),
            cardCount: binder.cards.length,
            totalValue: binder.cards.reduce((sum, card) => sum + (Number(card.currentPrice) || 0), 0)
        }));
    if (binders.length === 0) return;
    try {
        window.flutterBridge.postMessage('sharedSync:' + JSON.stringify({ binders }));
    } catch (e) {
        console.error('sharedSync failed', e);
    }
}

function openShared() {
    if (!window.flutterBridge) {
        showToast('Bridge nie je dostupný.');
        return;
    }
    updateNav('nav-shared');
    window.flutterBridge.postMessage('openShared:');
}

function shareBinderFromActions() {
    const binder = state.binders.find(item => item.id === binderActionsId);
    if (!binder) return;
    if (!window.flutterBridge) {
        showToast('Bridge nie je dostupný.');
        return;
    }
    const snapshot = sharedBinderSnapshot(binder);
    window.flutterBridge.postMessage('shareBinder:' + JSON.stringify({
        localId: binder.id,
        sharedId: binder.sharedId || '',
        token: binder.sharedToken || '',
        name: binder.name,
        snapshot,
        cardCount: binder.cards.length,
        totalValue: binder.cards.reduce((sum, card) => sum + (Number(card.currentPrice) || 0), 0)
    }));
}

function handleShareBinderResult(result) {
    if (!result || !result.localId) return;
    const binder = state.binders.find(item => item.id === result.localId);
    if (!binder) return;
    binder.sharedId = String(result.id || '');
    binder.sharedToken = String(result.token || '');
    saveState();
    renderBinderSelector();
    renderBinder();
    requestBinderLikes(true);
    if (document.getElementById('binder-modal').classList.contains('active')) {
        renderBinderPicker();
    }
    showToast('Balík je zdieľaný.');
}

function handleSharedStopped(sharedId) {
    if (!sharedId) return;
    let changed = false;
    state.binders.forEach(binder => {
        if (binder.sharedId === sharedId) {
            binder.sharedId = '';
            binder.sharedToken = '';
            changed = true;
        }
    });
    if (!changed) return;
    delete state.binderLikes[sharedId];
    delete lastBinderLikesAt[sharedId];
    saveState();
    renderBinderSelector();
    renderBinder();
    if (document.getElementById('binder-modal').classList.contains('active')) {
        renderBinderPicker();
    }
}

function handleSharedError(message) {
    showToast(String(message || 'Zdieľanie zlyhalo.'));
}

function requestBinderLikes(force = false) {
    const binder = getCurrentBinder();
    if (!binder || !binder.sharedId || !window.flutterBridge) return;
    const now = Date.now();
    if (!force && now - (lastBinderLikesAt[binder.sharedId] || 0) < 15000) return;
    lastBinderLikesAt[binder.sharedId] = now;
    try {
        window.flutterBridge.postMessage('sharedLikes:' + JSON.stringify({
            id: binder.sharedId
        }));
    } catch (_) {}
}

function handleBinderLikes(sharedId, likes) {
    if (!sharedId) return;
    state.binderLikes[sharedId] = likes && typeof likes === 'object' ? likes : {};
    const binder = getCurrentBinder();
    if (binder && binder.sharedId === sharedId) renderBinder();
}

function refreshSharedBinderSummaries() {
    if (!window.flutterBridge) return;
    try {
        window.flutterBridge.postMessage('refreshSharedBinders:');
    } catch (_) {}
}

function handleSharedBinderSummaries(list) {
    state.sharedBinders = Array.isArray(list) ? list : [];
    const modal = document.getElementById('binder-modal');
    if (modal && modal.classList.contains('active')) {
        renderSharedBinderPicker();
    }
}

function openSharedBinderFromPicker(sharedId) {
    if (!window.flutterBridge) {
        showToast('Bridge nie je dostupný.');
        return;
    }
    closeBinderPicker();
    window.flutterBridge.postMessage('openSharedBinder:' + JSON.stringify({
        id: String(sharedId || '')
    }));
}

function normalizeCard(card) {
    const price = Number(card.currentPrice ?? card.price ?? 0);
    const finishes = Array.isArray(card.finishes)
        ? card.finishes.map(finish => String(finish).toLowerCase()).filter(Boolean)
        : [];
    return {
        ...card,
        id: String(card.id || ''),
        name: String(card.name || ''),
        set: String(card.set || ''),
        game: String(card.game || 'pokemon'),
        language: normalizeLanguage(card.language),
        currentPrice: Number.isFinite(price) ? price : 0,
        imageUri: String(card.imageUri || ''),
        rarity: normalizeRarity(card.rarity),
        foil: card.foil === true || card.foil === 'true' || card.foil === 1 ||
            finishes.some(finish => finish !== 'normal'),
        finish: String(card.finish || '').toLowerCase(),
        finishes,
        number: String(card.number || ''),
        artist: String(card.artist || ''),
        addedAt: String(card.addedAt || ''),
        customImage: card.customImage === true || card.customImage === 'true',
        lastUpdated: String(card.lastUpdated || ''),
        source: String(card.source || 'tcgdex'),
        priceSource: String(card.priceSource || card.source || ''),
        priceCurrency: String(card.priceCurrency || 'USD'),
        priceChartingUrl: String(card.priceChartingUrl || ''),
        priceChartingUpdated: String(card.priceChartingUpdated || ''),
        priceChartingFull: card.priceChartingFull === true,
        gradePrices: Array.isArray(card.gradePrices)
            ? card.gradePrices
                .filter(grade => grade && grade.label && Number.isFinite(Number(grade.price)))
                .map(grade => ({
                    label: String(grade.label),
                    price: Number(grade.price)
                }))
            : [],
        priceHistory: normalizeHistory(card.priceHistory)
    };
}

function normalizeState(raw) {
    if (!raw || typeof raw !== 'object') return createDefaultState();

    const rawBinders = Array.isArray(raw.binders) ? raw.binders : [];
    const now = Date.now();
    const binders = rawBinders.map((binder, index) => {
        const safeBinder = binder && typeof binder === 'object' ? binder : {};
        const cards = Array.isArray(safeBinder.cards) ? safeBinder.cards : [];
        const validCards = cards.filter(card => card && card.id);
        return {
            id: String(safeBinder.id || `binder_${index + 1}`),
            name: String(safeBinder.name || `Balík ${index + 1}`),
            cards: validCards.map((card, cardIndex) => {
                const normalized = normalizeCard(card);
                if (!normalized.addedAt) {
                    // Older saved cards had no timestamp. Keep their current
                    // order as the "newest last" fallback.
                    normalized.addedAt = new Date(
                        now - (validCards.length - cardIndex) * 1000
                    ).toISOString();
                }
                return normalized;
            }),
            priceHistory: normalizeHistory(safeBinder.priceHistory),
            sortMode: BINDER_SORT_MODES.includes(safeBinder.sortMode)
                ? safeBinder.sortMode
                : 'custom',
            sharedId: String(safeBinder.sharedId || ''),
            sharedToken: String(safeBinder.sharedToken || '')
        };
    });

    if (binders.length === 0) {
        binders.push({
            id: 'binder_1',
            name: DEFAULT_BINDER_NAME,
            cards: [],
            priceHistory: [],
            sortMode: 'custom'
        });
    }

    let currentBinderId = raw.currentBinderId;
    if (!binders.some(binder => binder.id === currentBinderId)) {
        currentBinderId = binders[0].id;
    }

    return {
        binders,
        currentBinderId,
        collectionHistory: normalizeHistory(raw.collectionHistory),
        settings: normalizeSettings(raw.settings)
    };
}

function hydrateState(raw, restored = false) {
    state = normalizeState(raw);
    state.searchResults = [];
    state.sharedBinders = [];
    state.binderLikes = {};
    lastBinderLikesAt = {};
    previewCardId = null;
    cardModalReturnTo = null;
    dataBusy = false;
    stateHydrated = true;

    applySettings();
    ensureValueHistory();
    closeAllModals();
    renderBinderSelector();
    renderBinder();
    updateNav('nav-binder');

    // Persist the default state on first launch as well.
    saveState();
    requestAutomaticBackup();

    refreshAllPrices({ silent: true, force: restored });
    if (restored) showToast('Dáta boli obnovené.');
}

function requestAutomaticBackup() {
    if (autoBackupRequested) return;
    if (!stateHydrated || !window.flutterBridge || !state.settings.autoBackup) return;
    autoBackupRequested = true;
    const today = new Date().toISOString().slice(0, 10);
    let last = '';
    try {
        last = localStorage.getItem('raritio_last_auto_backup') || '';
    } catch (_) {}
    if (last === today) return;
    try {
        window.flutterBridge.postMessage('autoBackup:' + JSON.stringify(serializableState()));
        localStorage.setItem('raritio_last_auto_backup', today);
    } catch (_) {}
}

function applySettings() {
    const settings = state.settings || DEFAULT_SETTINGS;
    document.body.classList.toggle('hide-rarity', !settings.rarityFrames);
    document.body.classList.toggle('hide-game-badges', !settings.gameBadges);
    document.body.classList.toggle('hide-foil-badges', !settings.foilBadges);
    document.body.classList.toggle('hide-glow', !settings.glowEffect);
    document.body.classList.toggle('hide-holo', !settings.holoEffect);
}

// --- Rendering ---
function cardTileHtml(card, options = {}) {
    const price = Number(card.currentPrice) || 0;
    const color = rarityColor(card.rarity);
    const finishKey = primaryFinish(card);
    const finish = finishLabel(card);
    const glow = state.settings.glowEffect && isHighValue(card);
    const game = gameLabel(card.game);
    const gameClassValue = gameClass(card.game);
    const reorder = options.reorder === true;
    const index = Number(options.index) || 0;
    const total = Number(options.total) || 0;
    const cardId = escapeHtml(card.id);
    const binder = getCurrentBinder();
    const binderLike = binder && binder.sharedId
        ? (state.binderLikes[binder.sharedId] || {})[card.id]
        : null;

    return `
        <div class="card-item ${glow ? 'glow' : ''} game-${gameClassValue} ${reorder ? 'reorder-mode' : ''}"
             data-card-id="${cardId}"
             style="--rarity-color:${color}"
             title="${escapeHtml(card.rarity || '')}">
            <div class="card-badges">
                <div class="card-badges-left">
                    ${state.settings.gameBadges ? `<span class="badge-game ${gameClassValue}">${game}</span>` : ''}
                    ${card.customImage ? '<span class="badge-custom">Custom</span>' : ''}
                </div>
                ${state.settings.foilBadges && finish ? `<span class="badge-foil finish-${finishClass(finishKey)}"><span class="badge-spark">✦</span>${escapeHtml(finish)}</span>` : ''}
            </div>
            <div class="card-image-wrap">
                <img loading="lazy" decoding="async" referrerpolicy="no-referrer"
                     src="${imageSource(card.imageUri)}"
                     onerror="this.onerror=null;this.src=FALLBACK_IMAGE">
                ${binderLike && Number(binderLike.count) > 0 ? `
                    <div class="card-like-badge" title="Lajky od kamošov">
                        <span>♥</span>${Number(binderLike.count) || 0}
                    </div>
                ` : ''}
            </div>
            <div class="card-info">
                <div class="card-name">${escapeHtml(card.name)}</div>
                <div class="card-set">${escapeHtml(card.set)}</div>
                <div class="card-footer">
                    <div class="card-price" data-price-for="${cardId}">$${price.toFixed(2)}</div>
                    <span class="card-flag" title="${escapeHtml(languageLabel(card.language))}">${languageFlag(card.language)}</span>
                </div>
            </div>
            ${reorder ? `
                <div class="card-reorder">
                    <button onclick="event.stopPropagation();moveCardInBinder('${cardId}', -1)"
                            ${index <= 0 ? 'disabled' : ''}
                            title="Posunúť vyššie" aria-label="Posunúť vyššie">↑</button>
                    <button onclick="event.stopPropagation();moveCardInBinder('${cardId}', 1)"
                            ${index >= total - 1 ? 'disabled' : ''}
                            title="Posunúť nižšie" aria-label="Posunúť nižšie">↓</button>
                </div>
            ` : ''}
        </div>
    `;
}

function updateBinderTotal() {
    const binder = getCurrentBinder();
    const total = binder
        ? binder.cards.reduce((sum, card) => sum + (Number(card.currentPrice) || 0), 0)
        : 0;
    const totalElement = document.getElementById('total-value');
    if (totalElement) totalElement.innerText = `$${total.toFixed(2)}`;
}

function indexCardNodes() {
    cardNodes = new Map();
    const grid = document.getElementById('card-grid');
    if (!grid) return;
    grid.querySelectorAll('.card-item').forEach(node => {
        const id = node.dataset.cardId;
        if (!id) return;
        if (!cardNodes.has(id)) cardNodes.set(id, []);
        cardNodes.get(id).push(node);
    });
}

function raritySortRank(rarity) {
    const value = String(rarity || '').toLowerCase();
    if (/secret|rainbow|hyper/.test(value)) return 100;
    if (/special illustration|illustration rare|alt art/.test(value)) return 90;
    if (/ultra|gold|vmax|vstar|ex\b|gx\b/.test(value)) return 80;
    if (/holo|foil/.test(value)) return 70;
    if (/promo/.test(value)) return 60;
    if (/rare/.test(value)) return 50;
    if (/uncommon/.test(value)) return 40;
    if (/common/.test(value)) return 30;
    return 10;
}

function compareCardNames(a, b) {
    return String(a.name || '').localeCompare(String(b.name || ''), 'sk', {
        sensitivity: 'base',
        numeric: true
    });
}

function cardAddedTime(card) {
    const value = Date.parse(card.addedAt || '');
    return Number.isFinite(value) ? value : 0;
}

function sortedBinderCards(cards, mode) {
    const indexed = cards.map((card, index) => ({ card, index }));
    if (mode === 'custom' || !BINDER_SORT_MODES.includes(mode)) {
        return indexed.map(item => item.card);
    }

    indexed.sort((a, b) => {
        const cardA = a.card;
        const cardB = b.card;
        let result = 0;

        if (mode === 'name') {
            result = compareCardNames(cardA, cardB);
        } else if (mode === 'rarity') {
            result = raritySortRank(cardB.rarity) - raritySortRank(cardA.rarity) ||
                compareCardNames(cardA, cardB);
        } else if (mode === 'price_desc') {
            result = (Number(cardB.currentPrice) || 0) - (Number(cardA.currentPrice) || 0);
        } else if (mode === 'price_asc') {
            result = (Number(cardA.currentPrice) || 0) - (Number(cardB.currentPrice) || 0);
        } else if (mode === 'recent') {
            result = cardAddedTime(cardB) - cardAddedTime(cardA) || b.index - a.index;
        } else if (mode === 'set') {
            result = String(cardA.set || '').localeCompare(String(cardB.set || ''), 'sk', {
                sensitivity: 'base'
            }) || String(cardA.number || '').localeCompare(String(cardB.number || ''), 'sk', {
                numeric: true
            }) || compareCardNames(cardA, cardB);
        }

        return result || a.index - b.index;
    });

    return indexed.map(item => item.card);
}

function binderSortLabel(value) {
    const option = BINDER_SORT_OPTIONS.find(item => item.value === value);
    return option ? option.label : 'Vlastné';
}

function renderSortPicker() {
    const container = document.getElementById('sort-options');
    if (!container) return;
    const binder = getCurrentBinder();
    const current = binder && BINDER_SORT_MODES.includes(binder.sortMode)
        ? binder.sortMode
        : 'custom';

    container.innerHTML = BINDER_SORT_OPTIONS.map(option => `
        <button class="sort-option ${option.value === current ? 'active' : ''}"
                onclick="selectSortMode('${option.value}')">
            <span class="sort-option-icon" aria-hidden="true">${option.icon}</span>
            <span class="sort-option-copy">
                <strong>${option.label}</strong>
                <small>${option.description}</small>
            </span>
            <span class="sort-option-check" aria-hidden="true">✓</span>
        </button>
    `).join('');
}

function showSortPicker() {
    renderSortPicker();
    document.getElementById('sort-modal').classList.add('active');
}

function closeSortPicker(event) {
    if (event && event.target !== event.currentTarget) return;
    document.getElementById('sort-modal').classList.remove('active');
}

function selectSortMode(value) {
    setBinderSort(value);
    closeSortPicker();
}

function setBinderSort(value) {
    const binder = getCurrentBinder();
    if (!binder || !BINDER_SORT_MODES.includes(value)) return;
    binder.sortMode = value;
    if (value !== 'custom') reorderMode = false;
    saveState();
    renderBinder();
}

function toggleReorderMode() {
    const binder = getCurrentBinder();
    if (!binder || binder.sortMode !== 'custom' || binder.cards.length < 2) return;
    reorderMode = !reorderMode;
    renderBinder(true);
}

function moveCardInBinder(cardId, delta) {
    const binder = getCurrentBinder();
    if (!binder || binder.sortMode !== 'custom') return;
    const index = binder.cards.findIndex(card => card.id === cardId);
    const target = index + Number(delta);
    if (index < 0 || target < 0 || target >= binder.cards.length) return;

    const [card] = binder.cards.splice(index, 1);
    binder.cards.splice(target, 0, card);
    saveState();
    renderBinder(true);
}

function renderBinder(preserveScroll = false) {
    const binder = getCurrentBinder();
    if (!binder) return;

    const scrollY = preserveScroll ? window.scrollY : null;
    const restoreScroll = () => {
        if (preserveScroll) requestAnimationFrame(() => window.scrollTo(0, scrollY));
    };

    const binderName = document.getElementById('binder-name');
    if (binderName) binderName.innerText = binder.name;

    const sortMode = binder.sortMode || 'custom';
    const sortLabel = document.getElementById('binder-sort-label');
    if (sortLabel) sortLabel.innerText = binderSortLabel(sortMode);
    const sortIcon = document.querySelector('#binder-sort-button .sort-button-icon');
    if (sortIcon) {
        const option = BINDER_SORT_OPTIONS.find(item => item.value === sortMode);
        sortIcon.innerText = option ? option.icon : '↕';
    }

    const reorderButton = document.getElementById('reorder-toggle');
    if (reorderButton) {
        const canReorder = sortMode === 'custom' && binder.cards.length > 1;
        if (!canReorder) reorderMode = false;
        reorderButton.classList.toggle('hidden', !canReorder);
        reorderButton.classList.toggle('active', canReorder && reorderMode);
        reorderButton.innerText = reorderMode ? 'Hotovo' : 'Presúvať';
    }

    const grid = document.getElementById('card-grid');
    const emptyState = document.getElementById('empty-state');
    if (!grid || !emptyState) return;

    if (binder.cards.length === 0) {
        grid.innerHTML = '';
        grid.classList.add('hidden');
        emptyState.classList.remove('hidden');
        cardNodes = new Map();
        updateBinderTotal();
        requestBinderLikes();
        restoreScroll();
        return;
    }

    grid.classList.remove('hidden');
    emptyState.classList.add('hidden');

    const cards = sortedBinderCards(binder.cards, sortMode);
    // One innerHTML assignment is much cheaper than hundreds of appendChild
    // calls and keeps scrolling smooth in large binders.
    grid.innerHTML = cards.map((card, index) => cardTileHtml(card, {
        reorder: reorderMode && sortMode === 'custom',
        index,
        total: cards.length
    })).join('');
    indexCardNodes();
    updateBinderTotal();
    requestBinderLikes();
    restoreScroll();
}

function renderBinderSelector() {
    const binder = getCurrentBinder();
    const label = document.getElementById('binder-picker-label');
    if (label) label.innerText = binder ? binder.name : 'Balíky';

    // Keep an open picker in sync when a binder is renamed or created.
    const picker = document.getElementById('binder-modal');
    if (picker && picker.classList.contains('active')) {
        renderBinderPicker();
    }
}

function cardCountLabel(count) {
    if (count === 1) return 'karta';
    if (count >= 2 && count <= 4) return 'karty';
    return 'kariet';
}

function renderBinderStack(binder) {
    const images = binder.cards
        .map(card => card.imageUri)
        .filter(uri => typeof uri === 'string' && uri.length > 0);

    if (images.length === 0) {
        return Array.from({ length: 3 }, () => '<span class="stack-placeholder"></span>').join('');
    }

    return Array.from({ length: 3 }, (_, index) => {
        const src = images[index % images.length];
        return `<img src="${escapeHtml(src)}" alt="" loading="lazy" onerror="this.onerror=null;this.src=FALLBACK_IMAGE">`;
    }).join('');
}

function renderBinderPicker() {
    const container = document.getElementById('binder-picker-content');
    if (!container) return;

    container.innerHTML = state.binders.map(binder => {
        const isCurrent = binder.id === state.currentBinderId;
        const count = binder.cards.length;
        const total = binder.cards.reduce((sum, card) => sum + (Number(card.currentPrice) || 0), 0);
        const binderId = escapeHtml(binder.id);

        return `
            <div class="binder-card ${isCurrent ? 'active' : ''}"
                 onclick="selectBinder('${binderId}')"
                 role="button"
                 tabindex="0"
                 onkeydown="if(event.key==='Enter'||event.key===' '){event.preventDefault();selectBinder('${binderId}');}">
                <div class="binder-card-top">
                    <div class="binder-card-name">${escapeHtml(binder.name)}</div>
                    <button class="binder-edit-btn"
                            onclick="event.stopPropagation();openRenameBinder('${binderId}')"
                            title="Premenovať balík"
                            aria-label="Premenovať balík">✎</button>
                </div>
                <div class="binder-card-meta">
                    <span>${count} ${cardCountLabel(count)}</span>
                    ${isCurrent ? '<span class="binder-current-badge">Aktuálny</span>' : ''}
                </div>
                <div class="binder-card-stack">${renderBinderStack(binder)}</div>
                <div class="binder-card-total">$${total.toFixed(2)}</div>
            </div>
        `;
    }).join('');

    renderSharedBinderPicker();
}

function renderSharedBinderPicker() {
    const section = document.getElementById('shared-binder-picker');
    const grid = document.getElementById('shared-binder-grid');
    if (!section || !grid) return;

    if (!Array.isArray(state.sharedBinders) || state.sharedBinders.length === 0) {
        section.classList.add('hidden');
        grid.innerHTML = '';
        return;
    }

    section.classList.remove('hidden');
    grid.innerHTML = state.sharedBinders.map(binder => {
        const images = Array.isArray(binder.coverImages)
            ? binder.coverImages.filter(Boolean).slice(0, 3)
            : [];
        const stack = images.length === 0
            ? Array.from({ length: 3 }, () => '<span class="stack-placeholder"></span>').join('')
            : Array.from({ length: 3 }, (_, index) => {
                const src = images[index % images.length];
                return `<img src="${escapeHtml(src)}" alt="" loading="lazy" onerror="this.onerror=null;this.src=FALLBACK_IMAGE">`;
            }).join('');
        const count = Number(binder.cardCount) || 0;
        const total = Number(binder.totalValue) || 0;
        const sharedId = escapeHtml(binder.id || '');
        return `
            <div class="binder-card shared-binder-card"
                 onclick="openSharedBinderFromPicker('${sharedId}')"
                 role="button"
                 tabindex="0"
                 onkeydown="if(event.key==='Enter'||event.key===' '){event.preventDefault();openSharedBinderFromPicker('${sharedId}');}">
                <div class="shared-owner-badge">Od ${escapeHtml(binder.ownerNickname || 'kamoša')}</div>
                <div class="binder-card-name">${escapeHtml(binder.name || 'Balík')}</div>
                <div class="binder-card-meta">
                    <span>${count} ${cardCountLabel(count)}</span>
                </div>
                <div class="binder-card-stack">${stack}</div>
                <div class="binder-card-total">$${total.toFixed(2)}</div>
            </div>
        `;
    }).join('');
}

function showBinderPicker() {
    renderBinderPicker();
    refreshSharedBinderSummaries();
    document.getElementById('binder-modal').classList.add('active');
}

function closeBinderPicker(event) {
    if (event && event.target !== event.currentTarget) return;
    document.getElementById('binder-modal').classList.remove('active');
}

function selectBinder(binderId) {
    const binder = state.binders.find(b => b.id === binderId);
    if (!binder) return;

    state.currentBinderId = binderId;
    reorderMode = false;
    saveState();
    closeBinderPicker();
    renderBinderSelector();
    renderBinder();
    updateNav('nav-binder');
}

function openCreateBinder() {
    editingBinderId = null;

    const title = document.getElementById('binder-name-title');
    const hint = document.getElementById('binder-name-hint');
    const input = document.getElementById('binder-name-input');

    if (title) title.innerText = 'Nový balík';
    if (hint) hint.innerText = 'Zadaj názov nového balíka.';
    if (input) input.value = '';

    document.getElementById('binder-name-modal').classList.add('active');
    setTimeout(() => {
        if (input) {
            input.focus();
            input.select();
        }
    }, 80);
}

function openRenameBinder(binderId) {
    const binder = state.binders.find(b => b.id === binderId);
    if (!binder) return;

    editingBinderId = binderId;

    const title = document.getElementById('binder-name-title');
    const hint = document.getElementById('binder-name-hint');
    const input = document.getElementById('binder-name-input');

    if (title) title.innerText = 'Premenovať balík';
    if (hint) hint.innerText = 'Zmeň názov balíka. Karty zostanú zachované.';
    if (input) input.value = binder.name;

    document.getElementById('binder-name-modal').classList.add('active');
    setTimeout(() => {
        if (input) {
            input.focus();
            input.select();
        }
    }, 80);
}

function renameCurrentBinder() {
    if (state.currentBinderId) openRenameBinder(state.currentBinderId);
}

function closeBinderNameModal(event) {
    if (event && event.target !== event.currentTarget) return;
    document.getElementById('binder-name-modal').classList.remove('active');
    editingBinderId = null;
}

function saveBinderName() {
    const input = document.getElementById('binder-name-input');
    const name = input ? input.value.trim() : '';
    if (!name) {
        showToast('Zadaj názov balíka.');
        if (input) input.focus();
        return;
    }

    const wasPickerOpen = document.getElementById('binder-modal').classList.contains('active');
    const binderId = editingBinderId;

    if (binderId) {
        const binder = state.binders.find(b => b.id === binderId);
        if (!binder) {
            closeBinderNameModal();
            return;
        }

        binder.name = name;
        closeBinderNameModal();
        saveState();
        renderBinderSelector();
        renderBinder();
        if (wasPickerOpen) renderBinderPicker();
        showToast(`Balík premenovaný na ${name}.`);
        return;
    }

    const newBinder = {
        id: 'binder_' + Date.now(),
        name,
        cards: [],
        priceHistory: [],
        sortMode: 'custom'
    };
    state.binders.push(newBinder);
    state.currentBinderId = newBinder.id;

    closeBinderNameModal();
    if (wasPickerOpen) closeBinderPicker();
    saveState();
    renderBinderSelector();
    renderBinder();
    updateNav('nav-binder');
    showToast(`Balík ${name} vytvorený.`);
}

// --- Binder management ---
function openBinderActions(binderId) {
    const binder = state.binders.find(item => item.id === binderId);
    if (!binder) return;
    binderActionsId = binderId;
    renderBinderActions();
    document.getElementById('binder-actions-modal').classList.add('active');
}

function closeBinderActions(event) {
    if (event && event.target !== event.currentTarget) return;
    document.getElementById('binder-actions-modal').classList.remove('active');
    binderActionsId = null;
}

function renderBinderActions() {
    const binder = state.binders.find(item => item.id === binderActionsId);
    const container = document.getElementById('binder-actions-content');
    if (!binder || !container) return;

    const pokemonCount = binder.cards.filter(card => gameClass(card.game) === 'pokemon').length;
    const mtgCount = binder.cards.filter(card => gameClass(card.game) === 'mtg').length;
    container.innerHTML = `
        <div class="binder-actions-summary">
            <div class="binder-actions-name">${escapeHtml(binder.name)}</div>
            <div class="binder-actions-meta">${binder.cards.length} ${cardCountLabel(binder.cards.length)} · ${pokemonCount} Pokémon · ${mtgCount} MTG</div>
        </div>
        <div class="settings-section">
            <div class="settings-section-title">Zdieľanie</div>
            <button class="action-row" onclick="shareBinderFromActions()">
                <span class="action-icon">↗</span>
                <span>
                    <strong>${binder.sharedId ? 'Spravovať zdieľanie' : 'Zdieľať balík'}</strong>
                    <small>${binder.sharedId ? 'QR kód, Android share alebo zrušenie zdieľania.' : 'Pošli balík kamošovi cez QR alebo Android share menu.'}</small>
                </span>
            </button>
        </div>
        <div class="settings-section">
            <div class="settings-section-title">Pridať z kolekcie</div>
            <button class="action-row" onclick="addAllCardsByGame('pokemon')">
                <span class="action-icon">＋</span>
                <span><strong>Pridať všetky Pokémon karty</strong><small>Skopíruje unikátne Pokémon karty z ostatných balíkov.</small></span>
            </button>
            <button class="action-row" onclick="addAllCardsByGame('mtg')">
                <span class="action-icon">＋</span>
                <span><strong>Pridať všetky MTG karty</strong><small>Skopíruje unikátne MTG karty z ostatných balíkov.</small></span>
            </button>
        </div>
        <div class="settings-section">
            <div class="settings-section-title">Presunúť podľa typu</div>
            <button class="action-row" onclick="moveCardsByGame('pokemon')">
                <span class="action-icon">↗</span>
                <span><strong>Presunúť Pokémon karty do nového balíka</strong><small>Vytvorí nový balík a presunie doň všetky Pokémon karty.</small></span>
            </button>
            <button class="action-row" onclick="moveCardsByGame('mtg')">
                <span class="action-icon">↗</span>
                <span><strong>Presunúť MTG karty do nového balíka</strong><small>Vytvorí nový balík a presunie doň všetky MTG karty.</small></span>
            </button>
        </div>
        <div class="settings-section danger-section">
            <div class="settings-section-title">Nebezpečné akcie</div>
            <button class="action-row danger" onclick="emptyBinder()">
                <span class="action-icon">⌫</span>
                <span><strong>Vyprázdniť balík</strong><small>Odstráni karty, ale balík zostane. Nevyužité údaje sa uvoľnia.</small></span>
            </button>
            <button class="action-row danger" onclick="deleteBinder()">
                <span class="action-icon">✕</span>
                <span><strong>Zmazať balík</strong><small>Odstráni balík aj jeho karty. Nevyužité údaje sa uvoľnia.</small></span>
            </button>
        </div>
    `;
}

function uniqueBinderName(base) {
    let name = base;
    let index = 2;
    while (state.binders.some(binder => binder.name === name)) {
        name = `${base} ${index}`;
        index += 1;
    }
    return name;
}

function addAllCardsByGame(game) {
    const binder = state.binders.find(item => item.id === binderActionsId);
    if (!binder) return;

    const existing = new Set(binder.cards.map(cardKey));
    const seen = new Set();
    let added = 0;

    state.binders.forEach(source => {
        if (source.id === binder.id) return;
        source.cards.forEach(card => {
            if (gameClass(card.game) !== game) return;
            const key = cardKey(card);
            if (existing.has(key) || seen.has(key)) return;
            seen.add(key);
            binder.cards.push({ ...card, addedAt: new Date().toISOString() });
            added += 1;
        });
    });

    if (added === 0) {
        showToast(game === 'mtg' ? 'V kolekcii nie sú ďalšie MTG karty.' : 'V kolekcii nie sú ďalšie Pokémon karty.');
        return;
    }

    saveState();
    renderBinderSelector();
    renderBinder();
    if (document.getElementById('binder-modal').classList.contains('active')) renderBinderPicker();
    closeBinderActions();
    showToast(`Pridaných ${added} kariet.`);
}

function moveCardsByGame(game) {
    const binder = state.binders.find(item => item.id === binderActionsId);
    if (!binder) return;

    const matching = binder.cards.filter(card => gameClass(card.game) === game);
    if (matching.length === 0) {
        showToast(game === 'mtg' ? 'V balíku nie sú MTG karty.' : 'V balíku nie sú Pokémon karty.');
        return;
    }

    const newBinder = {
        id: 'binder_' + Date.now(),
        name: uniqueBinderName(game === 'mtg' ? 'MTG karty' : 'Pokémon karty'),
        cards: matching.map(card => ({ ...card })),
        priceHistory: [],
        sortMode: 'custom'
    };
    binder.cards = binder.cards.filter(card => gameClass(card.game) !== game);
    state.binders.push(newBinder);
    state.currentBinderId = newBinder.id;

    cleanupOrphanData();
    saveState();
    renderBinderSelector();
    renderBinder();
    updateNav('nav-binder');
    closeBinderActions();
    showToast(`Vytvorený balík ${newBinder.name}.`);
}

function emptyBinder() {
    const binder = state.binders.find(item => item.id === binderActionsId);
    if (!binder) return;
    askConfirm(
        `Vyprázdniť balík „${binder.name}“? Balík zostane, odstránia sa z neho všetky karty.`,
        () => {
            binder.cards = [];
            binder.priceHistory = [];
            cleanupOrphanData();
            saveState();
            renderBinderSelector();
            renderBinder();
            closeBinderActions();
            showToast(`Balík ${binder.name} je prázdny.`);
        }
    );
}

function deleteBinder() {
    const binder = state.binders.find(item => item.id === binderActionsId);
    if (!binder) return;
    askConfirm(
        `Zmazať balík „${binder.name}“ aj s kartami? Táto akcia sa nedá vrátiť.`,
        () => {
            if (binder.sharedId && window.flutterBridge) {
                window.flutterBridge.postMessage('stopShared:' + JSON.stringify({ id: binder.sharedId }));
            }
            state.binders = state.binders.filter(item => item.id !== binder.id);
            if (state.binders.length === 0) {
                state.binders.push({
                    id: 'binder_1',
                    name: DEFAULT_BINDER_NAME,
                    cards: [],
                    priceHistory: [],
                    sortMode: 'custom'
                });
            }
            if (!state.binders.some(item => item.id === state.currentBinderId)) {
                state.currentBinderId = state.binders[0].id;
            }

            cleanupOrphanData();
            saveState();
            renderBinderSelector();
            renderBinder();
            updateNav('nav-binder');
            closeBinderActions();
            showToast(`Balík ${binder.name} bol zmazaný.`);
        }
    );
}

let confirmAction = null;

function askConfirm(message, action) {
    confirmAction = action;
    const messageNode = document.getElementById('confirm-message');
    if (messageNode) messageNode.innerText = message;
    document.getElementById('confirm-modal').classList.add('active');
}

function closeConfirm(event) {
    if (event && event.target !== event.currentTarget) return;
    document.getElementById('confirm-modal').classList.remove('active');
    confirmAction = null;
}

function runConfirmAction() {
    const action = confirmAction;
    confirmAction = null;
    document.getElementById('confirm-modal').classList.remove('active');
    if (action) action();
}

function cleanupOrphanData() {
    const referenced = new Set();
    state.binders.forEach(binder => binder.cards.forEach(card => referenced.add(cardKey(card))));

    // Search results are only a temporary preview. When the search sheet is
    // closed, drop anything that no binder references so its card JSON can be
    // garbage-collected.
    const searchOpen = document.getElementById('search-modal')?.classList.contains('active');
    if (!searchOpen) {
        state.searchResults = (state.searchResults || []).filter(card =>
            referenced.has(cardKey(card)) || previewCardId === card.id
        );
    }

    if (state.cardCache && typeof state.cardCache === 'object') {
        Object.keys(state.cardCache).forEach(key => {
            if (!referenced.has(key)) delete state.cardCache[key];
        });
    }
}

// --- Price history ---
function formatChartMoney(value) {
    return '$' + Number(value).toFixed(2);
}

function formatChartDate(timestamp) {
    const date = new Date(timestamp);
    return `${date.getDate()}. ${date.getMonth() + 1}.`;
}

function dayCountLabel(days) {
    if (days <= 0) return 'dnes';
    if (days === 1) return '1 deň';
    if (days >= 2 && days <= 4) return `${days} dni`;
    return `${days} dní`;
}

function recordPriceSnapshot(card, price) {
    const value = Number(price);
    if (!card || !Number.isFinite(value) || value <= 0) return;

    const now = new Date();
    const today = now.toISOString().slice(0, 10);
    if (!Array.isArray(card.priceHistory)) card.priceHistory = [];

    const existing = card.priceHistory.find(point => point && point.date === today);
    if (existing) {
        existing.price = value;
        existing.source = 'local';
    } else {
        card.priceHistory.push({ date: today, price: value, source: 'local' });
    }

    const cutoff = new Date(now.getTime() - 31 * 86400000).toISOString().slice(0, 10);
    card.priceHistory = card.priceHistory
        .filter(point => point && point.date >= cutoff && Number.isFinite(Number(point.price)))
        .map(point => ({
            date: String(point.date),
            price: Number(point.price),
            source: point.source === 'cardmarket' ? 'cardmarket' : 'local'
        }))
        .sort((a, b) => a.date.localeCompare(b.date))
        .slice(-40);
}

function renderPriceHistory(card) {
    if (!card) return '';

    if (card.detailsLoaded === false) {
        return `
            <div class="price-history">
                <div class="price-history-header">
                    <div class="price-history-title">Vývoj ceny</div>
                </div>
                <div class="price-history-empty">Načítavam históriu ceny...</div>
            </div>
        `;
    }

    const currentPrice = Number(card.currentPrice ?? card.price ?? 0);
    let points = Array.isArray(card.priceHistory)
        ? card.priceHistory
            .map(point => ({
                t: Date.parse(String(point.date) + 'T00:00:00'),
                p: Number(point.price),
                source: point.source === 'cardmarket' ? 'cardmarket' : 'local'
            }))
            .filter(point => Number.isFinite(point.t) && Number.isFinite(point.p) && point.p > 0)
            .sort((a, b) => a.t - b.t)
        : [];

    if (points.length === 0 && currentPrice > 0) {
        points = [{ t: Date.now(), p: currentPrice, source: 'local' }];
    }

    if (points.length === 0) {
        const languageNote = normalizeLanguage(card.language) !== 'en'
            ? '<div class="price-history-note">Pre japonské a čínske karty TCGdex cenu zatiaľ neposkytuje.</div>'
            : '';
        return `
            <div class="price-history">
                <div class="price-history-header">
                    <div class="price-history-title">Vývoj ceny</div>
                </div>
                <div class="price-history-empty">História ceny zatiaľ nie je dostupná.</div>
                ${languageNote}
            </div>
        `;
    }

    const hasCardmarket = points.some(point => point.source === 'cardmarket');
    const prices = points.map(point => point.p);
    let minPrice = Math.min(...prices);
    let maxPrice = Math.max(...prices);
    if (minPrice === maxPrice) {
        const padding = Math.max(minPrice * 0.1, 0.01);
        minPrice = Math.max(0, minPrice - padding);
        maxPrice += padding;
    } else {
        const padding = (maxPrice - minPrice) * 0.15;
        minPrice = Math.max(0, minPrice - padding);
        maxPrice += padding;
    }

    let minTime = points[0].t;
    let maxTime = points[points.length - 1].t;
    if (minTime === maxTime) {
        minTime -= 86400000;
        maxTime += 86400000;
    }

    const width = 320;
    const height = 150;
    const left = 44;
    const right = 10;
    const top = 14;
    const bottom = 26;
    const plotWidth = width - left - right;
    const plotHeight = height - top - bottom;

    const xFor = time => left + ((time - minTime) / (maxTime - minTime)) * plotWidth;
    const yFor = price => top + (1 - (price - minPrice) / (maxPrice - minPrice)) * plotHeight;

    const linePoints = points.map((point, index) => {
        const x = xFor(point.t).toFixed(1);
        const y = yFor(point.p).toFixed(1);
        return `${index === 0 ? 'M' : 'L'} ${x} ${y}`;
    }).join(' ');
    const areaPoints = `${linePoints} L ${xFor(points[points.length - 1].t).toFixed(1)} ${height - bottom} L ${xFor(points[0].t).toFixed(1)} ${height - bottom} Z`;

    const gridLines = [0, 0.5, 1].map(ratio => {
        const y = (top + ratio * plotHeight).toFixed(1);
        return `<line x1="${left}" y1="${y}" x2="${width - right}" y2="${y}" stroke="rgba(148,163,184,0.14)" stroke-width="1"/>`;
    }).join('');

    const dots = points.map((point, index) => {
        const show = points.length <= 12 || index === 0 || index === points.length - 1;
        if (!show) return '';
        const x = xFor(point.t).toFixed(1);
        const y = yFor(point.p).toFixed(1);
        return `<circle cx="${x}" cy="${y}" r="3" fill="#10b981" stroke="#16161a" stroke-width="1.5"><title>${formatChartDate(point.t)}: ${formatChartMoney(point.p)}</title></circle>`;
    }).join('');

    const firstLabel = formatChartDate(points[0].t);
    const lastLabel = formatChartDate(points[points.length - 1].t);
    const spanDays = Math.round((maxTime - minTime) / 86400000);
    const midLabel = spanDays >= 10
        ? `<text x="${(left + plotWidth / 2).toFixed(1)}" y="${height - 8}" text-anchor="middle" fill="#94a3b8" font-size="8">${formatChartDate((minTime + maxTime) / 2)}</text>`
        : '';
    const xLabels = points.length >= 2
        ? `<text x="${left}" y="${height - 8}" text-anchor="start" fill="#94a3b8" font-size="8">${firstLabel}</text>
           <text x="${width - right}" y="${height - 8}" text-anchor="end" fill="#94a3b8" font-size="8">${lastLabel}</text>
           ${midLabel}`
        : `<text x="${(width / 2).toFixed(1)}" y="${height - 8}" text-anchor="middle" fill="#94a3b8" font-size="8">Dnes</text>`;

    const firstPrice = points[0].p;
    const lastPrice = points[points.length - 1].p;
    const change = firstPrice > 0 ? ((lastPrice - firstPrice) / firstPrice) * 100 : 0;
    const hasChange = points.length >= 2;
    const changeClass = change >= 0 ? 'up' : 'down';
    const changeText = `${change >= 0 ? '▲' : '▼'} ${Math.abs(change).toFixed(1)} %`;

    const subtitle = points.length === 1
        ? 'Prvé meranie'
        : `${dayCountLabel(spanDays)} · ${hasCardmarket ? 'Cardmarket trend' : 'Lokálne merania'}`;

    const note = points.length === 1
        ? 'Graf sa doplní pri ďalšej aktualizácii ceny.'
        : (hasCardmarket
            ? 'Staršie body sú 30/7/1-dňové priemery Cardmarketu, novšie sa ukladajú pri aktualizácii cien.'
            : 'Graf sa dopĺňa pri každej aktualizácii ceny.');

    const singleLine = points.length === 1
        ? `<line x1="${left}" y1="${yFor(points[0].p).toFixed(1)}" x2="${width - right}" y2="${yFor(points[0].p).toFixed(1)}" stroke="#10b981" stroke-width="2" stroke-dasharray="5 5" opacity="0.55"/>`
        : '';

    return `
        <div class="price-history">
            <div class="price-history-header">
                <div>
                    <div class="price-history-title">Vývoj ceny</div>
                    <div class="price-history-subtitle">${subtitle}</div>
                </div>
                ${hasChange ? `<div class="price-history-change ${changeClass}">${changeText}</div>` : ''}
            </div>
            <svg class="price-chart" viewBox="0 0 ${width} ${height}" role="img" aria-label="Vývoj ceny karty">
                <defs>
                    <linearGradient id="priceChartGradient" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stop-color="#10b981" stop-opacity="0.3"/>
                        <stop offset="100%" stop-color="#10b981" stop-opacity="0"/>
                    </linearGradient>
                </defs>
                ${gridLines}
                <text x="2" y="${top + 4}" fill="#94a3b8" font-size="8">${formatChartMoney(maxPrice)}</text>
                <text x="2" y="${height - bottom + 4}" fill="#94a3b8" font-size="8">${formatChartMoney(minPrice)}</text>
                ${singleLine}
                ${points.length >= 2 ? `<path d="${areaPoints}" fill="url(#priceChartGradient)"/>` : ''}
                ${points.length >= 2 ? `<path d="${linePoints}" fill="none" stroke="#10b981" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>` : ''}
                ${dots}
                ${xLabels}
            </svg>
            <div class="price-history-note">${note}</div>
        </div>
    `;
}

function historyFromEntries(entries) {
    const dates = new Set();
    entries.forEach(({ card }) => {
        (card.priceHistory || []).forEach(point => dates.add(point.date));
    });
    const today = new Date().toISOString().slice(0, 10);
    dates.add(today);

    const sortedDates = Array.from(dates).sort().slice(-60);
    const points = [];

    sortedDates.forEach(date => {
        let total = 0;
        entries.forEach(({ card }) => {
            const history = (card.priceHistory || []).slice().sort((a, b) => a.date.localeCompare(b.date));
            let price = 0;
            for (const point of history) {
                if (point.date <= date) price = point.price;
                else break;
            }
            if (price <= 0 && history.length > 0) price = history[0].price;
            if (price <= 0) price = Number(card.currentPrice) || 0;
            total += price;
        });
        if (total > 0) points.push({ date, price: total, source: 'local' });
    });

    return points;
}

function mergeHistory(existing, computed) {
    const byDate = new Map();
    (computed || []).forEach(point => byDate.set(point.date, point));
    (existing || []).forEach(point => byDate.set(point.date, point));
    return Array.from(byDate.values())
        .sort((a, b) => a.date.localeCompare(b.date))
        .slice(-60);
}

function ensureValueHistory() {
    state.binders.forEach(binder => {
        const entries = binder.cards.map(card => ({ binder, card }));
        binder.priceHistory = mergeHistory(
            binder.priceHistory,
            historyFromEntries(entries)
        );
    });

    const allEntries = [];
    state.binders.forEach(binder => {
        binder.cards.forEach(card => allEntries.push({ binder, card }));
    });
    state.collectionHistory = mergeHistory(
        state.collectionHistory,
        historyFromEntries(allEntries)
    );
}

function recordValueSnapshot(history, value) {
    const price = Number(value) || 0;
    if (!Array.isArray(history) || price <= 0) return;
    const today = new Date().toISOString().slice(0, 10);
    const existing = history.find(point => point.date === today);
    if (existing) {
        existing.price = price;
    } else {
        history.push({ date: today, price, source: 'local' });
    }
    history.sort((a, b) => a.date.localeCompare(b.date));
    if (history.length > 60) history.splice(0, history.length - 60);
}

function recordValueSnapshots() {
    let collectionTotal = 0;
    state.binders.forEach(binder => {
        const total = binder.cards.reduce(
            (sum, card) => sum + (Number(card.currentPrice) || 0),
            0
        );
        recordValueSnapshot(binder.priceHistory, total);
        collectionTotal += total;
    });
    recordValueSnapshot(state.collectionHistory, collectionTotal);
}

function recordValueSnapshotsDebounced() {
    clearTimeout(valueSnapshotTimer);
    valueSnapshotTimer = setTimeout(() => {
        recordValueSnapshots();
        saveStateDebounced();
    }, 1200);
}

function renderValueChart(points, { title, subtitle = '', emptyText = 'História hodnoty sa dopĺňa pri aktualizácii cien.', color = '#3b82f6', chartId = 'valueChart' } = {}) {
    const clean = (points || [])
        .map(point => ({
            t: Date.parse(String(point.date) + 'T00:00:00'),
            p: Number(point.price),
            date: point.date
        }))
        .filter(point => Number.isFinite(point.t) && Number.isFinite(point.p) && point.p > 0)
        .sort((a, b) => a.t - b.t);

    if (clean.length === 0) {
        return `
            <div class="value-chart-card">
                <div class="value-chart-head">
                    <div class="value-chart-title">${escapeHtml(title)}</div>
                </div>
                <div class="value-chart-empty">${escapeHtml(emptyText)}</div>
            </div>
        `;
    }

    const width = 320;
    const height = 132;
    const left = 42;
    const right = 10;
    const top = 12;
    const bottom = 24;
    const plotWidth = width - left - right;
    const plotHeight = height - top - bottom;

    let minPrice = Math.min(...clean.map(point => point.p));
    let maxPrice = Math.max(...clean.map(point => point.p));
    if (minPrice === maxPrice) {
        const padding = Math.max(minPrice * 0.08, 0.01);
        minPrice = Math.max(0, minPrice - padding);
        maxPrice += padding;
    } else {
        const padding = (maxPrice - minPrice) * 0.12;
        minPrice = Math.max(0, minPrice - padding);
        maxPrice += padding;
    }

    let minTime = clean[0].t;
    let maxTime = clean[clean.length - 1].t;
    if (minTime === maxTime) {
        minTime -= 86400000;
        maxTime += 86400000;
    }

    const xFor = time => left + ((time - minTime) / (maxTime - minTime)) * plotWidth;
    const yFor = price => top + (1 - (price - minPrice) / (maxPrice - minPrice)) * plotHeight;

    const linePoints = clean.map((point, index) =>
        `${index === 0 ? 'M' : 'L'} ${xFor(point.t).toFixed(1)} ${yFor(point.p).toFixed(1)}`
    ).join(' ');
    const areaPoints = `${linePoints} L ${xFor(clean[clean.length - 1].t).toFixed(1)} ${height - bottom} L ${xFor(clean[0].t).toFixed(1)} ${height - bottom} Z`;

    const gridLines = [0, 0.5, 1].map(ratio => {
        const y = (top + ratio * plotHeight).toFixed(1);
        return `<line x1="${left}" y1="${y}" x2="${width - right}" y2="${y}" stroke="rgba(148,163,184,0.14)" stroke-width="1"/>`;
    }).join('');

    const dots = clean.map((point, index) => {
        if (clean.length > 12 && index !== 0 && index !== clean.length - 1) return '';
        return `<circle cx="${xFor(point.t).toFixed(1)}" cy="${yFor(point.p).toFixed(1)}" r="2.6" fill="${color}" stroke="#16161a" stroke-width="1.4"><title>${formatChartDate(point.t)}: ${formatChartMoney(point.p)}</title></circle>`;
    }).join('');

    const spanDays = Math.round((maxTime - minTime) / 86400000);
    const first = clean[0].p;
    const last = clean[clean.length - 1].p;
    const change = first > 0 ? ((last - first) / first) * 100 : 0;
    const changeClass = change >= 0 ? 'up' : 'down';
    const changeText = `${change >= 0 ? '▲' : '▼'} ${Math.abs(change).toFixed(1)} %`;
    const changeHtml = clean.length >= 2
        ? `<div class="value-chart-change ${changeClass}">${changeText}</div>`
        : '';
    const subtitleText = subtitle || (clean.length === 1
        ? 'Prvé meranie'
        : `${dayCountLabel(spanDays)} · lokálne merania`);

    const singleLine = clean.length === 1
        ? `<line x1="${left}" y1="${yFor(clean[0].p).toFixed(1)}" x2="${width - right}" y2="${yFor(clean[0].p).toFixed(1)}" stroke="${color}" stroke-width="2" stroke-dasharray="5 5" opacity="0.55"/>`
        : '';

    return `
        <div class="value-chart-card">
            <div class="value-chart-head">
                <div>
                    <div class="value-chart-title">${escapeHtml(title)}</div>
                    <div class="value-chart-subtitle">${escapeHtml(subtitleText)}</div>
                </div>
                ${changeHtml}
            </div>
            <svg class="value-chart" viewBox="0 0 ${width} ${height}" role="img" aria-label="${escapeHtml(title)}">
                <defs>
                    <linearGradient id="${chartId}" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stop-color="${color}" stop-opacity="0.3"/>
                        <stop offset="100%" stop-color="${color}" stop-opacity="0"/>
                    </linearGradient>
                </defs>
                ${gridLines}
                <text x="2" y="${top + 4}" fill="#94a3b8" font-size="8">${formatChartMoney(maxPrice)}</text>
                <text x="2" y="${height - bottom + 4}" fill="#94a3b8" font-size="8">${formatChartMoney(minPrice)}</text>
                ${singleLine}
                ${clean.length >= 2 ? `<path d="${areaPoints}" fill="url(#${chartId})"/>` : ''}
                ${clean.length >= 2 ? `<path d="${linePoints}" fill="none" stroke="${color}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>` : ''}
                ${dots}
                <text x="${left}" y="${height - 8}" text-anchor="start" fill="#94a3b8" font-size="8">${formatChartDate(clean[0].t)}</text>
                <text x="${width - right}" y="${height - 8}" text-anchor="end" fill="#94a3b8" font-size="8">${formatChartDate(clean[clean.length - 1].t)}</text>
            </svg>
        </div>
    `;
}

function openCardModal() {
    const modal = document.getElementById('card-modal');
    if (!modal) return;

    const wasActive = modal.classList.contains('active');
    const content = modal.querySelector('.modal-content');
    if (content) content.scrollTop = 0;
    modal.classList.add('active');
    if (!wasActive) beginHoloTilt();

    // Some WebViews apply layout after the modal becomes visible.
    requestAnimationFrame(() => {
        if (content) content.scrollTop = 0;
    });
}

function cardVisualHtml(card) {
    const finish = primaryFinish(card);
    const holo = state.settings.holoEffect && cardHasHolo(card);
    const glow = state.settings.glowEffect && isHighValue(card);
    const classes = [
        'holo-card',
        holo ? 'holo' : '',
        holo && finish ? finish : '',
        glow ? 'glow' : ''
    ].filter(Boolean).join(' ');

    return `
        <div class="detail-visual">
            <div class="${classes}" data-holo-card>
                <div class="holo-card-inner">
                    <img src="${imageSource(card.imageUri)}"
                         referrerpolicy="no-referrer"
                         onerror="this.onerror=null;this.src=FALLBACK_IMAGE;showReloadImageButton()">
                    <div class="holo-shine"></div>
                    <div class="holo-grain"></div>
                </div>
            </div>
            ${glow ? '<div class="glow-caption">High value</div>' : ''}
            ${card.customImage ? '<div class="detail-custom-badge">Custom</div>' : ''}
        </div>
    `;
}

function showReloadImageButton() {
    const button = document.getElementById('reload-image-btn');
    if (button) button.classList.remove('hidden');
}

function hasCardImage(card) {
    return Boolean(card && card.imageUri && card.imageUri !== FALLBACK_IMAGE);
}

function findCardForImage(cardId) {
    const binder = getCurrentBinder();
    let card = binder ? binder.cards.find(item => item.id === cardId) : null;
    if (card) return card;
    card = state.searchResults.find(item => item.id === cardId);
    if (card) return card;
    for (const other of state.binders) {
        const found = other.cards.find(item => item.id === cardId);
        if (found) return found;
    }
    return null;
}

function renderDetailImageActions(card) {
    const hasImage = hasCardImage(card);
    const customLabel = card.customImage ? 'Odfotiť znova' : 'Odfotiť vlastnú kartu';
    return `
        <div class="detail-image-actions">
            <button id="reload-image-btn"
                    class="btn-secondary reload-image-btn ${hasImage ? 'hidden' : ''}"
                    onclick="reloadCardImage('${escapeHtml(card.id)}')">Obnoviť obrázok</button>
            ${(!hasImage || card.customImage) ? `
                <button id="custom-image-btn"
                        class="btn-secondary reload-image-btn custom-image-btn"
                        onclick="captureCustomCardImage('${escapeHtml(card.id)}')">${customLabel}</button>
            ` : ''}
        </div>
    `;
}

function updateCardEverywhere(cardId, updater) {
    let updated = false;
    const apply = card => {
        if (card && card.id === cardId) {
            updater(card);
            updated = true;
        }
    };
    state.searchResults.forEach(apply);
    state.binders.forEach(binder => binder.cards.forEach(apply));
    return updated;
}

function refreshOpenCardDetail(cardId) {
    if (previewCardId !== cardId) return;
    const modal = document.getElementById('card-modal');
    if (!modal || !modal.classList.contains('active')) return;
    if (cardModalReturnTo === 'search') {
        const preview = state.searchResults.find(card => card.id === cardId);
        if (preview) renderPreview(preview);
    } else {
        showCardDetails(cardId, true);
    }
}

function captureCustomCardImage(cardId) {
    const card = findCardForImage(cardId);
    if (!card) return;
    if (!window.flutterBridge) {
        showToast('Bridge nie je dostupný.');
        return;
    }

    const button = document.getElementById('custom-image-btn');
    if (button) {
        button.disabled = true;
        button.innerText = 'Otváram kameru...';
    }

    window.flutterBridge.postMessage('captureCardPhoto:' + JSON.stringify({
        id: card.id,
        game: card.game,
        language: normalizeLanguage(card.language)
    }));
}

function handleCustomCardImageProcessing(cardId) {
    const button = document.getElementById('custom-image-btn');
    if (button) {
        button.disabled = true;
        button.innerText = 'Upravujem fotku...';
    }
}

function handleCustomCardImage(cardId, dataUri) {
    const image = String(dataUri || '');
    if (!image.startsWith('data:image/')) {
        handleCustomCardImageError(cardId);
        return;
    }

    const updated = updateCardEverywhere(cardId, card => {
        card.imageUri = image;
        card.customImage = true;
    });
    if (!updated) return;

    saveState();
    renderBinder();
    refreshOpenCardDetail(cardId);
    showToast('Vlastná fotka karty bola uložená.');
}

function handleCustomCardImageCancelled(cardId) {
    refreshOpenCardDetail(cardId);
}

function handleCustomCardImageError(cardId) {
    refreshOpenCardDetail(cardId);
    showToast('Fotku sa nepodarilo upraviť. Skús to znova.');
}

function reloadCardImage(cardId) {
    const card = findCardForImage(cardId);
    if (!card) return;
    if (!window.flutterBridge) {
        showToast('Bridge nie je dostupný.');
        return;
    }

    const button = document.getElementById('reload-image-btn');
    if (button) {
        button.disabled = true;
        button.innerText = 'Načítavam obrázok...';
    }

    window.flutterBridge.postMessage('reloadCardImage:' + JSON.stringify({
        id: card.id,
        name: card.name,
        set: card.set,
        number: card.number,
        game: card.game,
        language: normalizeLanguage(card.language)
    }));
}

function handleCardImageReload(cardId, imageUri) {
    const nextImage = String(imageUri || '');
    let updated = false;

    state.searchResults.forEach(card => {
        if (card.id === cardId) {
            card.imageUri = nextImage;
            card.customImage = false;
            updated = true;
        }
    });
    state.binders.forEach(binder => {
        binder.cards.forEach(card => {
            if (card.id === cardId) {
                card.imageUri = nextImage;
                card.customImage = false;
                updated = true;
            }
        });
    });
    if (!updated) return;

    saveState();
    renderBinder();

    if (previewCardId === cardId) {
        const modal = document.getElementById('card-modal');
        if (modal && modal.classList.contains('active')) {
            if (cardModalReturnTo === 'search') {
                const preview = state.searchResults.find(card => card.id === cardId);
                if (preview) renderPreview(preview);
            } else {
                showCardDetails(cardId, true);
            }
        }
    }
    showToast('Obrázok karty bol obnovený.');
}

function handleCardImageReloadError(cardId) {
    const button = document.getElementById('reload-image-btn');
    if (button) {
        button.disabled = false;
        button.innerText = 'Obnoviť obrázok';
        button.classList.remove('hidden');
    }
    showToast('Obrázok karty sa nepodarilo načítať.');
}

function renderGradePrices(card) {
    if (!state.settings.priceCharting || isMtgCard(card)) return '';

    const grades = Array.isArray(card.gradePrices) ? card.gradePrices : [];
    const loading = priceChartingRequests.has(card.id);
    const sourceLink = card.priceChartingUrl
        ? `<a class="grade-link" href="${escapeHtml(card.priceChartingUrl)}" target="_blank" rel="noopener">PriceCharting ↗</a>`
        : '';

    if (grades.length === 0) {
        if (loading) {
            return `
                <div class="grade-prices">
                    <div class="grade-prices-head">
                        <div class="grade-title">Pricecharting ceny</div>
                        ${sourceLink}
                    </div>
                    <div class="grade-loading">Načítavam ceny z PriceCharting...</div>
                </div>
            `;
        }
        if (card.priceChartingError) {
            return `
                <div class="grade-prices">
                    <div class="grade-prices-head">
                        <div class="grade-title">Pricecharting ceny</div>
                        ${sourceLink}
                    </div>
                    <div class="grade-loading">Ceny z PriceCharting sa nepodarilo načítať.</div>
                    <button class="grade-load-btn" onclick="requestPriceChartingForCurrent()">Skúsiť znova</button>
                </div>
            `;
        }
        return `
            <div class="grade-prices">
                <div class="grade-prices-head">
                    <div class="grade-title">Pricecharting ceny</div>
                    ${sourceLink}
                </div>
                <button class="grade-load-btn" onclick="requestPriceChartingForCurrent()">Načítať ceny</button>
            </div>
        `;
    }

    return `
        <div class="grade-prices">
            <div class="grade-prices-head">
                <div>
                    <div class="grade-title">Pricecharting ceny</div>
                    <div class="grade-subtitle">všetky dostupné grade</div>
                </div>
                ${sourceLink}
            </div>
            <div class="grade-grid">
                ${grades.map(grade => `
                    <div class="grade-row">
                        <span class="grade-label">${escapeHtml(grade.label)}</span>
                        <span class="grade-value">${formatChartMoney(grade.price)}</span>
                    </div>
                `).join('')}
            </div>
            <div class="grade-note">Zdroj: PriceCharting. Zobrazené sú všetky dostupné grade. Ceny sú v USD a môžu sa líšiť podľa stavu karty.</div>
        </div>
    `;
}

function mergeCardPriceHistory(card, points) {
    if (!Array.isArray(points) || points.length === 0) return;
    const byDate = new Map();
    (card.priceHistory || []).forEach(point => byDate.set(point.date, point));
    points.forEach(point => {
        if (!point || !point.date || !Number.isFinite(Number(point.price))) return;
        if (byDate.has(point.date)) return;
        byDate.set(point.date, {
            date: String(point.date),
            price: Number(point.price),
            source: 'pricecharting'
        });
    });
    card.priceHistory = Array.from(byDate.values())
        .sort((a, b) => a.date.localeCompare(b.date))
        .slice(-60);
}

function requestPriceCharting(card) {
    // MTG cards have no PriceCharting grade table, so don't even search for it.
    if (!card || isMtgCard(card) || !state.settings.priceCharting || !window.flutterBridge) return;
    // Older saved cards may only contain a subset of the grade table. Fetch
    // once more so every available grade is shown.
    if (Array.isArray(card.gradePrices) && card.gradePrices.length > 0 && card.priceChartingFull) return;
    if (card.priceChartingError) return;
    if (priceChartingRequests.has(card.id)) return;

    priceChartingRequests.add(card.id);
    window.flutterBridge.postMessage('fetchPriceCharting:' + JSON.stringify({
        id: card.id,
        name: card.name,
        set: card.set,
        number: card.number,
        game: card.game,
        language: normalizeLanguage(card.language),
        priceChartingUrl: card.priceChartingUrl || ''
    }));
}

function requestPriceChartingForCurrent() {
    if (!previewCardId) return;
    let card = state.searchResults.find(item => item.id === previewCardId);
    if (!card) {
        const binder = getCurrentBinder();
        card = binder ? binder.cards.find(item => item.id === previewCardId) : null;
    }
    if (!card) return;
    card.priceChartingError = false;
    card.priceChartingFull = false;
    requestPriceCharting(card);
    if (previewCardId) {
        const cardModal = document.getElementById('card-modal');
        if (cardModal && cardModal.classList.contains('active')) {
            if (cardModalReturnTo === 'search') {
                renderPreview(card);
            } else {
                showCardDetails(previewCardId, true);
            }
        }
    }
}

function handlePriceCharting(cardId, data, language = null, game = null) {
    priceChartingRequests.delete(cardId);
    if (!data || typeof data !== 'object') return;

    const wantedLanguage = language ? normalizeLanguage(language) : null;
    const wantedGame = game ? String(game).toLowerCase() : null;
    let updatedCard = null;
    const updateCard = card => {
        if (!card || card.id !== cardId) return;
        if (wantedLanguage && normalizeLanguage(card.language) !== wantedLanguage) return;
        if (wantedGame && String(card.game || 'pokemon').toLowerCase() !== wantedGame) return;
        const isMtg = isMtgCard(card) || wantedGame === 'mtg';
        // MTG has no grade table. A PriceCharting fallback may still supply a
        // base price, but its grades are intentionally ignored.
        const grades = isMtg ? [] : (Array.isArray(data.gradePrices) ? data.gradePrices : []);
        const fallbackPrice = Number(data.price) || 0;
        card.gradePrices = grades;
        card.priceChartingFull = !isMtg && (grades.length > 0 || fallbackPrice > 0);
        card.priceChartingUrl = String(data.url || card.priceChartingUrl || '');
        card.priceChartingUpdated = String(data.updated || new Date().toISOString());
        card.priceChartingError = !isMtg && grades.length === 0 && fallbackPrice <= 0;


        const currentPrice = Number(card.currentPrice) || 0;
        const source = String(card.priceSource || '').toLowerCase();
        // Cardmarket/TCGdex is the base price. PriceCharting is only a fallback
        // when no base price exists, so never replace it here.
        const hasBasePrice = currentPrice > 0 && source !== 'pricecharting';
        if (fallbackPrice > 0 && !hasBasePrice) {
            card.currentPrice = fallbackPrice;
            card.priceSource = 'pricecharting';
            card.lastUpdated = new Date().toISOString();
            recordPriceSnapshot(card, fallbackPrice);
        }
        mergeCardPriceHistory(card, data.priceHistory);
        updatedCard = card;
    };

    state.binders.forEach(binder => binder.cards.forEach(updateCard));
    state.searchResults.forEach(updateCard);

    if (!updatedCard) return;

    ensureValueHistory();
    recordValueSnapshotsDebounced();
    saveStateDebounced();

    const nodes = cardNodes.get(cardId) || [];
    nodes.forEach(node => {
        const priceNode = node.querySelector('.card-price');
        if (priceNode) priceNode.innerText = `$${(Number(updatedCard.currentPrice) || 0).toFixed(2)}`;
        node.classList.toggle('glow', state.settings.glowEffect && isHighValue(updatedCard));
    });
    updateBinderTotal();

    const activeBinder = getCurrentBinder();
    if (activeBinder && (activeBinder.sortMode === 'price_desc' || activeBinder.sortMode === 'price_asc')) {
        renderBinder(true);
    }

    if (previewCardId === cardId) {
        if (cardModalReturnTo === 'search') {
            const card = state.searchResults.find(item => item.id === cardId);
            if (card) renderPreview(card);
        } else {
            showCardDetails(cardId, true);
        }
    }

    if (document.getElementById('overview-modal').classList.contains('active')) {
        renderOverview();
    }
}

function handlePriceChartingError(cardId, language = null, game = null) {
    priceChartingRequests.delete(cardId);
    const wantedLanguage = language ? normalizeLanguage(language) : null;
    const wantedGame = game ? String(game).toLowerCase() : null;
    const matches = card =>
        card && card.id === cardId &&
        (!wantedLanguage || normalizeLanguage(card.language) === wantedLanguage) &&
        (!wantedGame || String(card.game || 'pokemon').toLowerCase() === wantedGame);
    let failed = null;
    state.binders.forEach(binder => binder.cards.forEach(card => {
        if (matches(card)) {
            card.priceChartingError = true;
            failed = card;
        }
    }));
    state.searchResults.forEach(card => {
        if (matches(card)) {
            card.priceChartingError = true;
            failed = card;
        }
    });
    if (failed && previewCardId === cardId) {
        if (cardModalReturnTo === 'search') {
            const card = state.searchResults.find(item => item.id === cardId);
            if (card) renderPreview(card);
        } else {
            showCardDetails(cardId, true);
        }
    }
}

function applyHoloTilt(rotateX, rotateY, shineX, shineY) {
    const card = document.querySelector('#card-detail-content .holo-card');
    if (!card) return;
    card.style.setProperty('--rx', `${rotateX.toFixed(2)}deg`);
    card.style.setProperty('--ry', `${rotateY.toFixed(2)}deg`);
    card.style.setProperty('--mx', `${shineX.toFixed(1)}%`);
    card.style.setProperty('--my', `${shineY.toFixed(1)}%`);
}

function beginHoloTilt() {
    // Use the phone's orientation at the moment the detail opens as the
    // neutral position. This keeps the card centered instead of starting at
    // maximum tilt when the phone is already held at an angle.
    holoTiltBase = {
        beta: holoLastOrientation.known ? holoLastOrientation.beta : null,
        gamma: holoLastOrientation.known ? holoLastOrientation.gamma : null
    };
    applyHoloTilt(0, 0, 50, 50);
}

function resetHoloTilt() {
    applyHoloTilt(0, 0, 50, 50);
}

function attachHoloTilt() {
    if (!holoTiltBound) {
        holoTiltBound = true;
        window.addEventListener('deviceorientation', event => {
            const beta = Number(event.beta) || 0;
            const gamma = Number(event.gamma) || 0;
            holoLastOrientation = { beta, gamma, known: true };

            if (!state.settings.holoEffect) return;
            const modal = document.getElementById('card-modal');
            if (!modal || !modal.classList.contains('active')) return;

            if (holoTiltBase.beta === null || holoTiltBase.gamma === null) {
                holoTiltBase = { beta, gamma };
            }

            const relativeBeta = beta - holoTiltBase.beta;
            const relativeGamma = gamma - holoTiltBase.gamma;
            // The card follows the phone in the opposite direction to the
            // previous version. The highlight keeps its original response.
            const rotateX = Math.max(-18, Math.min(18, relativeBeta / 4.5));
            const rotateY = Math.max(-20, Math.min(20, -relativeGamma / 4.2));
            const shineX = Math.max(0, Math.min(100, 50 + relativeGamma * 2.2));
            const shineY = Math.max(0, Math.min(100, 50 + relativeBeta * 1.8));
            if (holoTiltFrame) cancelAnimationFrame(holoTiltFrame);
            holoTiltFrame = requestAnimationFrame(() => applyHoloTilt(rotateX, rotateY, shineX, shineY));
        }, true);
    }

    const card = document.querySelector('#card-detail-content .holo-card');
    if (!card) return;

    card.addEventListener('pointermove', event => {
        if (!state.settings.holoEffect) return;
        const rect = card.getBoundingClientRect();
        if (rect.width === 0 || rect.height === 0) return;
        const x = Math.max(0, Math.min(1, (event.clientX - rect.left) / rect.width));
        const y = Math.max(0, Math.min(1, (event.clientY - rect.top) / rect.height));
        const rotateY = (x - 0.5) * 30;
        const rotateX = (0.5 - y) * 26;
        applyHoloTilt(rotateX, rotateY, x * 100, y * 100);
    });
    card.addEventListener('pointerleave', resetHoloTilt);
}

// --- Card Details ---
function showCardDetails(cardId, preserveScroll = false) {
    const binder = getCurrentBinder();
    if (!binder) return;

    const card = binder.cards.find(c => c.id === cardId);
    if (!card) return;

    const modal = document.getElementById('card-modal');
    const modalContent = modal ? modal.querySelector('.modal-content') : null;
    const wasActive = modal ? modal.classList.contains('active') : false;
    const previousScroll = preserveScroll && wasActive && modalContent
        ? modalContent.scrollTop
        : 0;

    if (!isMtgCard(card) && state.settings.priceCharting &&
        (!Array.isArray(card.gradePrices) || card.gradePrices.length === 0 || !card.priceChartingFull)) {
        requestPriceCharting(card);
    }

    const content = document.getElementById('card-detail-content');
    content.innerHTML = `
        ${cardVisualHtml(card)}
        ${renderDetailImageActions(card)}
        <div class="detail-heading">
            <div class="detail-name">${escapeHtml(card.name)}</div>
            <div class="detail-set">${escapeHtml(card.set || '-')}</div>
        </div>
        <div class="detail-grid">
            <div class="detail-card"><span class="detail-card-label">Jazyk</span><span class="detail-card-value">${languageFlag(card.language)} ${escapeHtml(languageLabel(card.language))}</span></div>
            <div class="detail-card"><span class="detail-card-label">Edícia</span><span class="detail-card-value">${escapeHtml(card.set || '-')}</span></div>
            <div class="detail-card"><span class="detail-card-label">Rarita</span><span class="detail-card-value">${escapeHtml(card.rarity || '-')}</span></div>
            <div class="detail-card"><span class="detail-card-label">Prevedenie</span><span class="detail-card-value">${escapeHtml(finishLabel(card) || 'Normal')}</span></div>
            <div class="detail-card"><span class="detail-card-label">Číslo</span><span class="detail-card-value">${escapeHtml(card.number || '-')}</span></div>
            <div class="detail-card"><span class="detail-card-label">Autor</span><span class="detail-card-value">${escapeHtml(card.artist || '-')}</span></div>
            <div class="detail-card"><span class="detail-card-label">Cena</span><span class="detail-card-value price" id="detail-price">$${(Number(card.currentPrice) || 0).toFixed(2)}</span></div>
            <div class="detail-card"><span class="detail-card-label">Zdroj ceny</span><span class="detail-card-value">${escapeHtml(priceSourceLabel(card))}</span></div>
        </div>
        <div id="grade-prices-container">${renderGradePrices(card)}</div>
        <div id="price-history-container">${renderPriceHistory(card)}</div>
        <div class="binder-picker">
            <div class="binder-picker-title">Zaradenie do balíkov</div>
            ${renderMembershipCheckboxes(card)}
        </div>
        <button class="btn-danger" onclick="removeCardFromBinder('${card.id}')">Odstrániť z tohto balíka</button>
    `;

    cardModalReturnTo = null;
    previewCardId = card.id;

    if (preserveScroll && wasActive) {
        // Re-rendering after a binder checkbox change should not throw the
        // user back to the top; opening a different card still starts at 0.
        if (modalContent) modalContent.scrollTop = previousScroll;
        requestAnimationFrame(() => {
            if (modalContent) modalContent.scrollTop = previousScroll;
            attachHoloTilt();
        });
    } else {
        openCardModal();
        requestAnimationFrame(attachHoloTilt);
    }
}

function priceSourceLabel(card) {
    const source = String(card.priceSource || card.source || '').toLowerCase();
    if (source === 'pricecharting') return 'PriceCharting';
    if (source === 'cardmarket') return 'Cardmarket';
    if (source === 'tcgplayer') return 'TCGPlayer';
    if (source === 'scryfall') return 'Scryfall';
    if (source === 'tcgdex') return 'TCGdex';
    return source ? source : '-';
}

function renderMembershipCheckboxes(card) {
    return state.binders.map(binder => {
        const has = binder.cards.some(c => c.id === card.id);
        return `
            <label class="binder-check">
                <input type="checkbox" class="binder-membership-check" data-binder-id="${binder.id}" ${has ? 'checked' : ''} onchange="toggleCardInBinder('${card.id}', '${binder.id}', this.checked)">
                ${escapeHtml(binder.name)}
            </label>
        `;
    }).join('');
}

function removeCardFromBinder(cardId) {
    const binder = getCurrentBinder();
    if (!binder) return;

    binder.cards = binder.cards.filter(c => c.id !== cardId);
    cleanupOrphanData();
    saveState();
    renderBinderSelector();
    renderBinder();
    closeCardModal();
    showToast(`Odstránené z balíka ${binder.name}.`);
}

function toggleCardInBinder(cardId, binderId, checked) {
    const currentBinder = getCurrentBinder();
    const sourceCard =
        (currentBinder && currentBinder.cards.find(c => c.id === cardId)) ||
        state.binders.flatMap(b => b.cards).find(c => c.id === cardId);

    if (!sourceCard) return;

    const binder = state.binders.find(b => b.id === binderId);
    if (!binder) return;

    if (checked) {
        if (!binder.cards.some(c => c.id === cardId)) {
            binder.cards.push({ ...sourceCard, addedAt: new Date().toISOString() });
        }
    } else {
        binder.cards = binder.cards.filter(c => c.id !== cardId);
    }

    saveState();
    renderBinderSelector();
    renderBinder();

    const activeBinder = getCurrentBinder();
    if (!activeBinder || !activeBinder.cards.some(c => c.id === cardId)) {
        closeCardModal();
    } else {
        showCardDetails(cardId, true);
    }
}

// --- Search ---
function updateSearchClearVisibility() {
    const input = document.getElementById('search-input');
    const button = document.getElementById('search-clear');
    if (!input || !button) return;
    button.classList.toggle('hidden', input.value.trim().length === 0);
}

function clearSearchInput() {
    const input = document.getElementById('search-input');
    if (!input) return;
    input.value = '';
    searchRequestId += 1;
    updateSearchClearVisibility();
    const results = document.getElementById('search-results');
    if (results) results.innerHTML = '';
    input.focus();
}

function showSearch({ focus = true } = {}) {
    document.getElementById('search-modal').classList.add('active');
    updateSearchClearVisibility();
    const input = document.getElementById('search-input');
    if (input) {
        if (focus) {
            setTimeout(() => {
                const modal = document.getElementById('search-modal');
                if (modal && modal.classList.contains('active')) input.focus();
            }, 60);
        } else {
            // Scanning opens the result list without summoning the keyboard.
            input.blur();
            setTimeout(() => input.blur(), 60);
        }
    }
    updateNav('nav-search');
}

function performSearch(fromScan = false, language = null) {
    const query = document.getElementById('search-input').value.trim();
    if (!query) return;

    const requested = language && language !== 'auto'
        ? language
        : detectLanguage(query);
    const resolvedLanguage = normalizeLanguage(requested);

    const resultsContainer = document.getElementById('search-results');
    resultsContainer.innerHTML = '<p style="color:var(--text-muted); text-align:center; padding:20px;">Hľadám...</p>';

    if (window.flutterBridge) {
        searchRequestId += 1;
        window.flutterBridge.postMessage('searchCards:' + JSON.stringify({
            query,
            ocr: fromScan === true,
            requestId: searchRequestId,
            language: resolvedLanguage
        }));
    } else {
        resultsContainer.innerHTML = '<p style="color:var(--danger); text-align:center;">Bridge neaktívny.</p>';
    }
}

function handleSearchResults(results, usedQuery, requestId) {
    if (typeof requestId === 'number' && requestId !== searchRequestId) {
        // A newer search has already started; ignore this late response.
        return;
    }

    if (!Array.isArray(results)) results = [];
    state.searchResults = results.map(card => normalizeCard({
        ...card,
        language: normalizeLanguage(card.language || detectLanguage(card.name || ''))
    }));
    results = state.searchResults;

    const input = document.getElementById('search-input');
    if (input && typeof usedQuery === 'string' && usedQuery.trim().length > 0) {
        const corrected = usedQuery.trim();
        if (corrected !== input.value.trim()) {
            input.value = corrected;
            if (results.length > 0) {
                showToast(`Text upravený na „${corrected}“.`);
            }
        }
    }
    updateSearchClearVisibility();

    const container = document.getElementById('search-results');
    container.innerHTML = '';

    if (results.length === 0) {
        container.innerHTML = '<p style="color:var(--text-muted); text-align:center; padding:20px;">Žiadne výsledky.</p>';
        return;
    }

    results.forEach(card => {
        const div = document.createElement('div');
        div.className = 'search-result-item';
        div.dataset.cardId = card.id;
        div.onclick = () => showSearchPreview(card.id);

        const subtitle = [card.set, card.number ? '#' + card.number : '']
            .filter(Boolean)
            .join(' • ');
        const priceLine = card.detailsLoaded
            ? `<p class="search-result-price" style="color:var(--success); font-weight:bold;">$${(Number(card.currentPrice ?? card.price) || 0).toFixed(2)}</p>`
            : '';
        const addButton = card.detailsLoaded
            ? `<button class="add-btn" onclick="event.stopPropagation(); showSearchPreview('${card.id}')">Pridať</button>`
            : `<span style="font-size:0.7rem;color:var(--text-muted);">detail →</span>`;

        div.innerHTML = `
            <img loading="lazy" src="${imageSource(card.imageUri)}" onerror="this.onerror=null;this.src=FALLBACK_IMAGE">
            <div class="search-result-info">
                <h4>${escapeHtml(card.name)} <span class="search-result-flag" title="${escapeHtml(languageLabel(card.language))}">${languageFlag(card.language)}</span></h4>
                <p>${escapeHtml(subtitle)}</p>
                ${priceLine}
            </div>
            ${addButton}
        `;
        container.appendChild(div);
    });
}

function renderAddBinderCheckboxes(card) {
    return state.binders.map(binder => {
        const already = binder.cards.some(c => c.id === card.id);
        const checked = already || binder.id === state.currentBinderId;
        return `
            <label class="binder-check ${already ? 'disabled' : ''}">
                <input type="checkbox" class="binder-add-check" data-binder-id="${binder.id}" ${checked ? 'checked' : ''} ${already ? 'disabled' : ''}>
                ${escapeHtml(binder.name)}${already ? ' (už je)' : ''}
            </label>
        `;
    }).join('');
}

function renderPreview(card) {
    const content = document.getElementById('card-detail-content');
    const priceText = card.detailsLoaded
        ? `$${(Number(card.price ?? card.currentPrice) || 0).toFixed(2)}`
        : 'Načítavam...';

    if (!isMtgCard(card) && card.detailsLoaded && state.settings.priceCharting &&
        (!Array.isArray(card.gradePrices) || card.gradePrices.length === 0 || !card.priceChartingFull)) {
        requestPriceCharting(card);
    }

    const allAlready = state.binders.every(binder => binder.cards.some(c => c.id === card.id));
    const addButton = card.detailsLoaded
        ? (allAlready
            ? `<button class="btn-primary" disabled style="opacity:0.5;">Karta je už vo všetkých balíkoch</button>`
            : `<button class="btn-primary" onclick="addCardToSelectedBinders('${card.id}')">Pridať do vybraných balíkov</button>`)
        : `<button class="btn-primary" disabled style="opacity:0.5;">Načítavam detaily...</button>`;

    content.innerHTML = `
        ${cardVisualHtml(card)}
        ${renderDetailImageActions(card)}
        <div class="detail-heading">
            <div class="detail-name">${escapeHtml(card.name)}</div>
            <div class="detail-set">${escapeHtml(card.set || '-')}</div>
        </div>
        <div class="detail-grid">
            <div class="detail-card"><span class="detail-card-label">Jazyk</span><span class="detail-card-value">${languageFlag(card.language)} ${escapeHtml(languageLabel(card.language))}</span></div>
            <div class="detail-card"><span class="detail-card-label">Edícia</span><span class="detail-card-value">${escapeHtml(card.set || '-')}</span></div>
            <div class="detail-card"><span class="detail-card-label">Rarita</span><span class="detail-card-value">${escapeHtml(card.rarity || '-')}</span></div>
            <div class="detail-card"><span class="detail-card-label">Prevedenie</span><span class="detail-card-value">${escapeHtml(finishLabel(card) || 'Normal')}</span></div>
            <div class="detail-card"><span class="detail-card-label">Číslo</span><span class="detail-card-value">${escapeHtml(card.number || '-')}</span></div>
            <div class="detail-card"><span class="detail-card-label">Autor</span><span class="detail-card-value">${escapeHtml(card.artist || '-')}</span></div>
            <div class="detail-card"><span class="detail-card-label">Cena</span><span class="detail-card-value price" id="detail-price">${priceText}</span></div>
            <div class="detail-card"><span class="detail-card-label">Zdroj ceny</span><span class="detail-card-value">${escapeHtml(priceSourceLabel(card))}</span></div>
        </div>
        <div id="grade-prices-container">${renderGradePrices(card)}</div>
        <div id="price-history-container">${renderPriceHistory(card)}</div>
        <div class="binder-picker">
            <div class="binder-picker-title">Pridať do balíkov</div>
            ${renderAddBinderCheckboxes(card)}
            ${addButton}
        </div>
    `;
    requestAnimationFrame(attachHoloTilt);
}

function showSearchPreview(cardId) {
    const card = state.searchResults.find(c => c.id === cardId);
    if (!card) return;

    previewCardId = cardId;
    cardModalReturnTo = 'search';
    renderPreview(card);

    const searchInput = document.getElementById('search-input');
    if (searchInput) searchInput.blur();
    document.getElementById('search-modal').classList.remove('active');
    openCardModal();

    // Pokemon summaries come without prices/details: fetch them now.
    if (!card.detailsLoaded) {
        if (window.flutterBridge) {
            window.flutterBridge.postMessage('cardDetails:' + JSON.stringify({
                game: card.game,
                id: card.id,
                language: normalizeLanguage(card.language)
            }));
        } else {
            handleCardDetailsError(card.id);
        }
    } else {
        requestPriceCharting(card);
    }
}

function mergeCardFields(base, update) {
    const merged = { ...(base || {}), ...(update || {}) };
    ['imageUri', 'set', 'setId', 'rarity', 'artist', 'number', 'finish'].forEach(field => {
        const value = update ? update[field] : '';
        if ((value === undefined || value === null || String(value).trim() === '') &&
            base && base[field] !== undefined && base[field] !== null) {
            merged[field] = base[field];
        }
    });
    if (!Array.isArray(merged.finishes) || merged.finishes.length === 0) {
        merged.finishes = base && Array.isArray(base.finishes) ? base.finishes : [];
    }
    if (merged.foil === undefined) merged.foil = base ? base.foil : false;
    if (base && base.customImage === true) {
        merged.imageUri = base.imageUri;
        merged.customImage = true;
    }
    return normalizeCard(merged);
}

function handleCardDetails(details) {
    const normalized = normalizeCard(details);
    const index = state.searchResults.findIndex(c => c.id === normalized.id);
    let card = normalized;
    if (index >= 0) {
        card = mergeCardFields(state.searchResults[index], normalized);
        state.searchResults[index] = card;
    }
    if (previewCardId === normalized.id) {
        renderPreview(card);
    }
    handleSearchResults(state.searchResults);
    if (card.detailsLoaded) requestPriceCharting(card);
}

function handleCardDetailsError(cardId) {
    showToast('Nepodarilo sa načítať detaily karty.');
    const index = state.searchResults.findIndex(c => c.id === cardId);
    if (index >= 0) {
        state.searchResults[index] = { ...state.searchResults[index], detailsLoaded: true };
        if (previewCardId === cardId) {
            renderPreview(state.searchResults[index]);
        }
        handleSearchResults(state.searchResults);
    }
}

function addCardToSelectedBinders(cardId) {
    const card = state.searchResults.find(c => c.id === cardId);
    if (!card) return;

    if (!card.detailsLoaded) {
        showToast('Počkaj, načítavam detaily karty...');
        return;
    }

    const selectedIds = Array.from(
        document.querySelectorAll('#card-detail-content .binder-add-check:checked:not(:disabled)')
    ).map(input => input.dataset.binderId);

    if (selectedIds.length === 0) {
        showToast('Vyber aspoň jeden balík.');
        return;
    }

    const newCard = {
        ...card,
        currentPrice: Number(card.price ?? card.currentPrice) || 0,
        language: normalizeLanguage(card.language),
        addedAt: new Date().toISOString(),
        lastUpdated: new Date().toISOString(),
        source: card.source || 'tcgdex'
    };
    recordPriceSnapshot(newCard, newCard.currentPrice);

    let added = 0;
    selectedIds.forEach(binderId => {
        const binder = state.binders.find(b => b.id === binderId);
        if (binder && !binder.cards.some(c => c.id === card.id)) {
            binder.cards.push({ ...newCard });
            added++;
        }
    });

    if (added === 0) {
        showToast('Karta už je vo vybraných balíkoch.');
        return;
    }

    saveState();
    renderBinderSelector();
    renderBinder();

    // Remove from search results so the user does not add it twice.
    state.searchResults = state.searchResults.filter(c => c.id !== cardId);
    handleSearchResults(state.searchResults);

    document.getElementById('card-modal').classList.remove('active');
    if (cardModalReturnTo === 'search') {
        document.getElementById('search-modal').classList.add('active');
    }
    previewCardId = null;
    cardModalReturnTo = null;

    showToast(`Karta pridaná do ${added} ${added === 1 ? 'balíka' : 'balíkov'}.`);
}

// --- Scanning ---
function scanCard() {
    if (isScanning) return;
    isScanning = true;
    updateNav('nav-scan');
    if (window.flutterBridge) {
        showToast('Skenujem kartu...');
        window.flutterBridge.postMessage('scanCard:');
    } else {
        alert('Bridge neaktívny.');
        isScanning = false;
    }
}

let toastTimer = null;

function showToast(msg) {
    const toast = document.getElementById('toast');
    if (toast) {
        toast.innerText = msg;
        toast.style.display = 'block';
        clearTimeout(toastTimer);
        toastTimer = setTimeout(() => { toast.style.display = 'none'; }, 3000);
    } else {
        alert(msg);
    }
}

function showError(msg) {
    isScanning = false;
    showToast(msg);
}

function handleScanResult(result) {
    isScanning = false;

    let text = '';
    let language = 'en';
    if (typeof result === 'string') {
        text = result;
        language = detectLanguage(text);
    } else if (result && typeof result === 'object') {
        text = String(result.text || '');
        language = normalizeLanguage(result.language || detectLanguage(text));
    }

    const query = text.split('\n')[0].trim();
    if (!query) {
        showError("Nepodarilo sa rozpoznať žiadny text.");
        return;
    }

    // The OCR language is only a hint; the actual script in the query wins.
    const detected = detectLanguage(query);
    if (detected === 'en') {
        language = 'en';
    } else if (detected === 'ja') {
        language = 'ja';
    } else if (language === 'en' || !language) {
        language = detected;
    }

    document.getElementById('search-input').value = query;
    updateSearchClearVisibility();
    showSearch({ focus: false });
    performSearch(true, language);
}

// --- Price Verification ---
function refreshAllPrices({ silent = false, force = false } = {}) {
    if (!window.flutterBridge) return false;

    const now = Date.now();
    if (!force && now - lastPriceRefresh < 30000) return false;
    lastPriceRefresh = now;

    const uniqueCards = new Map();
    state.binders.forEach(binder => {
        binder.cards.forEach(card => {
            if (!card || !card.id) return;
            const key = cardKey(card);
            if (!uniqueCards.has(key)) {
                uniqueCards.set(key, card);
            }
        });
    });

    if (uniqueCards.size === 0) {
        if (!silent) showToast('Žiadne karty na aktualizáciu.');
        return false;
    }

    if (!silent) showToast('Aktualizujem ceny...');

    uniqueCards.forEach(card => {
        window.flutterBridge.postMessage('fetchPrice:' + JSON.stringify({
            id: card.id,
            game: card.game,
            name: card.name,
            set: card.set || '',
            number: card.number || '',
            source: card.source || 'tcgdex',
            language: normalizeLanguage(card.language),
            priceChartingUrl: card.priceChartingUrl || ''
        }));
    });
    return true;
}

function manualRefreshPrices() {
    const button = document.getElementById('refresh-prices-btn');
    if (button) button.classList.add('spinning');

    const started = refreshAllPrices({ silent: false, force: true });
    if (!started) {
        if (button) button.classList.remove('spinning');
        return;
    }

    clearTimeout(priceSpinTimer);
    priceSpinTimer = setTimeout(() => {
        if (button) button.classList.remove('spinning');
    }, 15000);
}

function updatePriceInUI(cardId, price, language = null, game = null) {
    const wantedLanguage = language ? normalizeLanguage(language) : null;
    const wantedGame = game ? String(game).toLowerCase() : null;
    let updated = false;
    let updatedCard = null;

    state.binders.forEach(binder => {
        binder.cards.forEach(card => {
            if (card.id === cardId &&
                (!wantedLanguage || normalizeLanguage(card.language) === wantedLanguage) &&
                (!wantedGame || String(card.game || 'pokemon').toLowerCase() === wantedGame)) {
                card.currentPrice = price;
                card.lastUpdated = new Date().toISOString();
                if (!card.priceSource || card.priceSource === 'tcgdex' || card.priceSource === 'pricecharting') {
                    card.priceSource = String(card.game || '').toLowerCase() === 'mtg'
                        ? 'scryfall'
                        : 'cardmarket';
                }
                recordPriceSnapshot(card, price);
                updatedCard = card;
                updated = true;
            }
        });
    });

    if (!updated) return;

    recordValueSnapshotsDebounced();
    saveStateDebounced();

    // Update only the tiles that show this card instead of rebuilding the
    // whole grid. This is the main reason scrolling stays smooth while prices
    // are arriving.
    (cardNodes.get(cardId) || []).forEach(node => {
        const priceNode = node.querySelector('.card-price');
        if (priceNode) priceNode.innerText = `$${Number(price).toFixed(2)}`;
        node.classList.toggle('glow', state.settings.glowEffect && isHighValue(updatedCard));
    });
    updateBinderTotal();

    if (document.getElementById('binder-modal').classList.contains('active')) {
        renderBinderPicker();
    }

    // Keep an open overview in sync as prices arrive.
    const overviewModal = document.getElementById('overview-modal');
    if (overviewModal && overviewModal.classList.contains('active')) {
        renderOverview();
    }

    // Keep an open detail modal in sync without restarting its animation.
    const cardModal = document.getElementById('card-modal');
    if (cardModal.classList.contains('active') && previewCardId === cardId) {
        const priceElement = document.getElementById('detail-price');
        if (priceElement) {
            priceElement.innerText = `$${Number(price).toFixed(2)}`;
        }

        let chartCard = updatedCard;
        if (cardModalReturnTo === 'search') {
            const index = state.searchResults.findIndex(c => c.id === cardId);
            if (index >= 0) {
                state.searchResults[index].price = price;
                state.searchResults[index].currentPrice = price;
                state.searchResults[index].detailsLoaded = true;
                if (updatedCard && Array.isArray(updatedCard.priceHistory)) {
                    state.searchResults[index].priceHistory = updatedCard.priceHistory;
                }
                chartCard = state.searchResults[index];
                updateSearchResultPrice(cardId, price);
            }
        }

        const chartContainer = document.getElementById('price-history-container');
        if (chartContainer && chartCard) {
            chartContainer.innerHTML = renderPriceHistory(chartCard);
        }
    }
}

function updateSearchResultPrice(cardId, price) {
    const results = document.querySelectorAll('.search-result-item');
    results.forEach(item => {
        if (item.dataset.cardId !== cardId) return;
        const priceNode = item.querySelector('.search-result-price');
        if (priceNode) priceNode.innerText = `$${Number(price).toFixed(2)}`;
    });
}

function onPriceRefreshFinished(success = 0, failed = 0) {
    const button = document.getElementById('refresh-prices-btn');
    if (button) button.classList.remove('spinning');
    clearTimeout(priceSpinTimer);

    const binder = getCurrentBinder();
    if (binder && (binder.sortMode === 'price_desc' || binder.sortMode === 'price_asc')) {
        renderBinder(true);
    }

    if (failed === 0) {
        showToast('Ceny aktualizované.');
    } else if (success === 0) {
        showToast('Ceny sa nepodarilo aktualizovať.');
    } else {
        showToast(`Ceny aktualizované (${success}), ${failed} sa nenašlo.`);
    }
}

// --- Overview ---
function showOverview(binderId = null) {
    overviewBinderId = binderId;
    renderOverview();
    document.getElementById('overview-modal').classList.add('active');
    updateNav('nav-overview');
}

function closeOverview(event) {
    if (event && event.target !== event.currentTarget) return;
    document.getElementById('overview-modal').classList.remove('active');
    overviewBinderId = null;
    updateNav('nav-binder');
}

function selectOverviewBinder(binderId) {
    overviewBinderId = binderId || null;
    renderOverview();
}

function openOverviewCard(binderId, cardId) {
    const binder = state.binders.find(b => b.id === binderId);
    if (!binder || !binder.cards.some(c => c.id === cardId)) return;

    state.currentBinderId = binderId;
    saveState();
    closeOverview();
    renderBinderSelector();
    renderBinder();
    showCardDetails(cardId);
}

function renderOverviewTabs() {
    const tabs = [
        `<button class="overview-tab ${overviewBinderId === null ? 'active' : ''}"
                 onclick="selectOverviewBinder(null)">Celá zbierka</button>`
    ];
    state.binders.forEach(binder => {
        tabs.push(`
            <button class="overview-tab ${overviewBinderId === binder.id ? 'active' : ''}"
                    onclick="selectOverviewBinder('${escapeHtml(binder.id)}')">
                ${escapeHtml(binder.name)}
            </button>
        `);
    });
    return `<div class="overview-tabs">${tabs.join('')}</div>`;
}

function renderTopCards(entries) {
    const top = entries
        .filter(entry => (Number(entry.card.currentPrice) || 0) > 0)
        .sort((a, b) =>
            (Number(b.card.currentPrice) || 0) - (Number(a.card.currentPrice) || 0)
        )
        .slice(0, 3);

    if (top.length === 0) {
        return `<div class="overview-empty-small">Zatiaľ nie sú dostupné ceny kariet.</div>`;
    }

    return `
        <div class="overview-top-list">
            ${top.map((entry, index) => {
                const price = Number(entry.card.currentPrice) || 0;
                const finish = finishLabel(entry.card);
                return `
                    <button class="overview-top-row"
                            onclick="openOverviewCard('${escapeHtml(entry.binder.id)}', '${escapeHtml(entry.card.id)}')">
                        <span class="overview-rank">${index + 1}</span>
                        <img src="${imageSource(entry.card.imageUri)}" alt=""
                             loading="lazy" decoding="async" referrerpolicy="no-referrer"
                             onerror="this.onerror=null;this.src=FALLBACK_IMAGE">
                        <span class="overview-top-main">
                            <span class="overview-top-name">${escapeHtml(entry.card.name)}</span>
                            <span class="overview-top-sub">${escapeHtml(entry.card.set || '')} ${languageFlag(entry.card.language)}${finish ? ' · ' + escapeHtml(finish) : ''}</span>
                        </span>
                        <span class="overview-top-price">$${price.toFixed(2)}</span>
                    </button>
                `;
            }).join('')}
        </div>
    `;
}

function renderOverview() {
    const container = document.getElementById('overview-content');
    if (!container) return;

    ensureValueHistory();
    if (overviewBinderId && !state.binders.some(binder => binder.id === overviewBinderId)) {
        overviewBinderId = null;
    }

    const selectedBinder = overviewBinderId
        ? state.binders.find(binder => binder.id === overviewBinderId)
        : null;
    const overviewTitle = document.getElementById('overview-title');
    if (overviewTitle) {
        overviewTitle.innerText = selectedBinder ? 'Prehľad balíka' : 'Prehľad zbierky';
    }

    const allEntries = [];
    state.binders.forEach(binder => {
        binder.cards.forEach(card => allEntries.push({ binder, card }));
    });

    const entries = selectedBinder
        ? selectedBinder.cards.map(card => ({ binder: selectedBinder, card }))
        : allEntries;

    const collectionValue = allEntries.reduce(
        (sum, { card }) => sum + (Number(card.currentPrice) || 0),
        0
    );

    if (!selectedBinder && allEntries.length === 0) {
        container.innerHTML = `
            ${renderOverviewTabs()}
            <div class="overview-empty">
                Zbierka je zatiaľ prázdna.<br>
                Pridaj karty cez Hľadať alebo Skenovať.
            </div>
        `;
        return;
    }

    const totalCards = entries.length;
    const uniqueCards = new Set(entries.map(({ card }) => cardKey(card))).size;
    const totalValue = entries.reduce(
        (sum, { card }) => sum + (Number(card.currentPrice) || 0),
        0
    );
    const share = collectionValue > 0 ? (totalValue / collectionValue) * 100 : 0;

    const binderRows = selectedBinder ? '' : state.binders.map(binder => {
        const count = binder.cards.length;
        const value = binder.cards.reduce(
            (sum, card) => sum + (Number(card.currentPrice) || 0),
            0
        );
        const binderShare = collectionValue > 0 ? (value / collectionValue) * 100 : 0;
        return `
            <button class="overview-row overview-binder-row"
                    onclick="selectOverviewBinder('${escapeHtml(binder.id)}')">
                <div class="overview-row-main">
                    <div class="overview-row-name">${escapeHtml(binder.name)}</div>
                    <div class="overview-row-sub">${count} ${cardCountLabel(count)}</div>
                    <div class="overview-bar"><div class="overview-bar-fill" style="width:${binderShare.toFixed(1)}%"></div></div>
                </div>
                <div class="overview-row-value">
                    $${value.toFixed(2)}
                    <span class="overview-chevron">›</span>
                </div>
            </button>
        `;
    }).join('');

    const languageCounts = new Map();
    entries.forEach(({ card }) => {
        const language = normalizeLanguage(card.language);
        languageCounts.set(language, (languageCounts.get(language) || 0) + 1);
    });
    const languageRows = Array.from(languageCounts.entries())
        .sort((a, b) => b[1] - a[1])
        .map(([language, count]) => {
            const meta = languageMeta(language);
            const languageShare = totalCards > 0 ? (count / totalCards) * 100 : 0;
            return `
                <div class="overview-row">
                    <span class="overview-language-flag">${meta.flag}</span>
                    <div class="overview-row-main">
                        <div class="overview-row-name">${escapeHtml(meta.label)}</div>
                        <div class="overview-bar"><div class="overview-bar-fill" style="width:${languageShare.toFixed(1)}%"></div></div>
                    </div>
                    <div class="overview-row-value" style="color:var(--text)">${count}</div>
                </div>
            `;
        }).join('');

    const chartPoints = selectedBinder
        ? selectedBinder.priceHistory
        : state.collectionHistory;
    const chartTitle = selectedBinder ? 'Hodnota balíka' : 'Hodnota zbierky';
    const chartSubtitle = selectedBinder
        ? `${selectedBinder.name} · ${totalCards} ${cardCountLabel(totalCards)}`
        : `${state.binders.length} balíkov · ${totalCards} ${cardCountLabel(totalCards)}`;
    const chart = renderValueChart(chartPoints, {
        title: chartTitle,
        subtitle: chartSubtitle,
        color: selectedBinder ? '#3b82f6' : '#10b981',
        chartId: selectedBinder ? 'binderValueChart' : 'collectionValueChart'
    });

    const emptyBinderHtml = selectedBinder && entries.length === 0
        ? `<div class="overview-empty-small">Tento balík je prázdny.</div>`
        : '';

    container.innerHTML = `
        ${renderOverviewTabs()}
        <div class="overview-stats">
            <div class="overview-stat">
                <div class="overview-stat-label">Karty</div>
                <div class="overview-stat-value">${totalCards}</div>
                <div class="overview-stat-sub">${uniqueCards} unikátnych</div>
            </div>
            <div class="overview-stat">
                <div class="overview-stat-label">Hodnota</div>
                <div class="overview-stat-value success">$${totalValue.toFixed(2)}</div>
                <div class="overview-stat-sub">${selectedBinder ? `${share.toFixed(1)} % zbierky` : 'celá zbierka'}</div>
            </div>
            <div class="overview-stat">
                <div class="overview-stat-label">Balíky</div>
                <div class="overview-stat-value">${selectedBinder ? 1 : state.binders.length}</div>
                <div class="overview-stat-sub">${selectedBinder ? escapeHtml(selectedBinder.name) : 'kolekcia'}</div>
            </div>
        </div>
        ${chart}
        ${emptyBinderHtml}
        ${binderRows ? `
            <div class="overview-section">
                <div class="overview-section-title">Balíky</div>
                ${binderRows}
            </div>
        ` : ''}
        <div class="overview-section">
            <div class="overview-section-title">${selectedBinder ? 'Top 3 v balíku' : 'Top 3 najhodnotnejšie karty'}</div>
            ${renderTopCards(entries)}
        </div>
        <div class="overview-section">
            <div class="overview-section-title">Jazyky</div>
            ${languageRows || '<div class="overview-empty-small">Žiadne karty.</div>'}
        </div>
    `;
}

// --- Settings / Data / Backup ---
function showDataModal() {
    // Opening settings from the binder picker/actions must not leave those
    // overlays visible behind the settings sheet.
    ['binder-modal', 'binder-actions-modal', 'binder-name-modal'].forEach(id => {
        const element = document.getElementById(id);
        if (element) element.classList.remove('active');
    });
    editingBinderId = null;
    binderActionsId = null;

    dataBusy = false;
    setDataStatus('');
    syncSettingsUI();
    document.getElementById('data-modal').classList.add('active');
}

function closeDataModal(event) {
    if (event && event.target !== event.currentTarget) return;
    document.getElementById('data-modal').classList.remove('active');
}

const RARITY_LEGEND = [
    { label: 'Rainbow / Secret / Hyper Rare', value: 'secret rainbow hyper' },
    { label: 'Special Illustration / Alt Art', value: 'special illustration alt art' },
    { label: 'Ultra / Gold / VMAX / VSTAR / ex / GX', value: 'ultra gold vmax vstar ex gx' },
    { label: 'Holo / Foil', value: 'holo foil' },
    { label: 'Promo', value: 'promo' },
    { label: 'Rare', value: 'rare' },
    { label: 'Uncommon', value: 'uncommon' },
    { label: 'Common', value: 'common' },
    { label: 'Neznáma', value: 'unknown' }
];

function showRarityLegend() {
    const container = document.getElementById('rarity-legend-content');
    if (container) {
        container.innerHTML = RARITY_LEGEND.map(item => `
            <div class="rarity-legend-item">
                <span class="rarity-swatch" style="background:${rarityColor(item.value)}"></span>
                <span class="rarity-legend-label">${escapeHtml(item.label)}</span>
            </div>
        `).join('');
    }
    const modal = document.getElementById('rarity-legend-modal');
    if (modal) modal.classList.add('active');
}

function closeRarityLegend(event) {
    if (event && event.target !== event.currentTarget) return;
    const modal = document.getElementById('rarity-legend-modal');
    if (modal) modal.classList.remove('active');
}

function setAppVersion(version) {
    const node = document.getElementById('app-version');
    if (!node) return;
    node.innerText = String(version || '').trim();
}

function syncSettingsUI() {
    const settings = state.settings || DEFAULT_SETTINGS;
    document.querySelectorAll('[data-setting]').forEach(input => {
        const key = input.dataset.setting;
        if (key === 'glowThreshold') {
            input.value = String(settings.glowThreshold || 20);
        } else if (input.type === 'checkbox') {
            input.checked = settings[key] !== false;
        }
    });
}

function toggleSetting(key, checked) {
    if (!(key in DEFAULT_SETTINGS)) return;
    state.settings[key] = !!checked;
    saveState();
    applySettings();
    renderBinder();
    if (key === 'autoBackup' && checked) requestAutomaticBackup();
    if (previewCardId) {
        const cardModal = document.getElementById('card-modal');
        if (cardModal && cardModal.classList.contains('active')) {
            if (cardModalReturnTo === 'search') {
                const card = state.searchResults.find(item => item.id === previewCardId);
                if (card) renderPreview(card);
            } else {
                showCardDetails(previewCardId, true);
            }
        }
    }
    if (document.getElementById('overview-modal').classList.contains('active')) {
        renderOverview();
    }
}

function setGlowThreshold(value) {
    const threshold = Number(value);
    if (!Number.isFinite(threshold) || threshold <= 0) return;
    state.settings.glowThreshold = threshold;
    saveStateDebounced();
    renderBinder();
}

function setDataStatus(message) {
    const status = document.getElementById('data-status');
    if (status) status.innerText = message;
}

function checkForUpdates() {
    if (!window.flutterBridge) {
        showToast('Bridge nie je dostupný.');
        return;
    }
    window.flutterBridge.postMessage('checkUpdates:');
}

function backupData() {
    if (dataBusy) return;
    if (!window.flutterBridge) {
        setDataStatus('Bridge nie je dostupný.');
        return;
    }
    dataBusy = true;
    setDataStatus('Pripravujem zálohu...');
    window.flutterBridge.postMessage('backupState:' + JSON.stringify(serializableState()));
}

function restoreData() {
    if (dataBusy) return;
    if (!window.flutterBridge) {
        setDataStatus('Bridge nie je dostupný.');
        return;
    }
    dataBusy = true;
    setDataStatus('Vyber súbor so zálohou...');
    window.flutterBridge.postMessage('restoreState:');
}

function onBackupResult(success, message) {
    dataBusy = false;
    setDataStatus(message);
    // The status under the backup button already shows the success message.
    if (!success) showToast(message);
}

function onRestoreResult(success, message) {
    dataBusy = false;
    setDataStatus(message);
    showToast(message);
}

// --- UI Helpers ---
function updateNav(activeId) {
    document.querySelectorAll('.nav-btn').forEach(btn => btn.classList.remove('active'));
    const active = document.getElementById(activeId);
    if (active) active.classList.add('active');
}

function closeModal(event) {
    if (event && event.target !== event.currentTarget) return;
    document.getElementById('search-modal').classList.remove('active');
    const input = document.getElementById('search-input');
    if (input) input.blur();
    updateNav('nav-binder');
}

function closeCardModal(event) {
    if (event && event.target !== event.currentTarget) return;
    document.getElementById('card-modal').classList.remove('active');
    previewCardId = null;
    resetHoloTilt();

    // Returning from a search preview goes back to the search results.
    if (cardModalReturnTo === 'search') {
        document.getElementById('search-modal').classList.add('active');
    }
    cardModalReturnTo = null;
}

function closeAllModals() {
    ['search-modal', 'card-modal', 'data-modal', 'binder-modal', 'binder-name-modal', 'binder-actions-modal', 'sort-modal', 'confirm-modal', 'overview-modal', 'rarity-legend-modal'].forEach(id => {
        const element = document.getElementById(id);
        if (element) element.classList.remove('active');
    });
    const input = document.getElementById('search-input');
    if (input) input.blur();
    editingBinderId = null;
    binderActionsId = null;
    confirmAction = null;
}

function showBinder() {
    const openModal = document.querySelector('.modal-overlay.active');

    updateNav('nav-binder');
    renderBinder();

    // The bottom "Balíky" tab opens the same binder picker as the selector at
    // the top whenever binders exist and no other modal is in the way.
    if (!openModal && state.binders.length > 0) {
        showBinderPicker();
    }
}

// --- Initialization ---
function init() {
    renderBinderSelector();
    renderBinder();
    updateSearchClearVisibility();

    const grid = document.getElementById('card-grid');
    if (grid) {
        grid.addEventListener('click', event => {
            if (event.target.closest('.card-reorder')) return;
            const item = event.target.closest('.card-item');
            if (!item || !grid.contains(item)) return;
            showCardDetails(item.dataset.cardId);
        });
    }

    setInterval(() => {
        const binder = getCurrentBinder();
        if (binder && binder.sharedId) requestBinderLikes(true);
    }, 30000);
}

init();

