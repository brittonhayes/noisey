const API = '';
const POLL_INTERVAL = 2000;

const SOUND_ICONS = {
    'white-noise': '◻',
    'pink-noise': '◇',
    'brown-noise': '▤',
};
const DEFAULT_ICON_NOISE = '〰';
const DEFAULT_ICON_NATURE = '🌿';
const DEFAULT_ICON_CUSTOM = '♪';

function iconFor(sound) {
    if (SOUND_ICONS[sound.id]) return SOUND_ICONS[sound.id];
    if (sound.category === 'noise') return DEFAULT_ICON_NOISE;
    if (sound.category === 'nature') return DEFAULT_ICON_NATURE;
    return DEFAULT_ICON_CUSTOM;
}

let state = null;
let debounceTimers = {};

async function api(method, path, body) {
    const opts = { method, headers: {} };
    if (body !== undefined) {
        opts.headers['Content-Type'] = 'application/json';
        opts.body = JSON.stringify(body);
    }
    try {
        const res = await fetch(API + path, opts);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        setConnected(true);
        return await res.json();
    } catch (e) {
        setConnected(false);
        throw e;
    }
}

function setConnected(connected) {
    const dot = document.getElementById('connection-dot');
    dot.classList.toggle('disconnected', !connected);
    dot.title = connected ? 'Connected' : 'Disconnected';
}

function renderSounds(sounds) {
    const grid = document.getElementById('sounds-grid');
    const existing = grid.children.length > 0;

    if (!existing) {
        grid.innerHTML = '';
        sounds.forEach(sound => {
            grid.appendChild(createSoundCard(sound));
        });
    } else {
        sounds.forEach(sound => {
            updateSoundCard(sound);
        });
    }
}

function createSoundCard(sound) {
    const card = document.createElement('div');
    card.className = `sound-card${sound.active ? ' active' : ''}`;
    card.id = `card-${sound.id}`;
    card.innerHTML = `
        <div class="sound-card-header" data-id="${sound.id}">
            <div class="sound-info">
                <span class="sound-icon">${iconFor(sound)}</span>
                <div>
                    <div class="sound-name">${sound.name}</div>
                    <div class="sound-category">${sound.category}</div>
                </div>
            </div>
            <label class="toggle" onclick="event.stopPropagation()">
                <input type="checkbox" ${sound.active ? 'checked' : ''} data-id="${sound.id}">
                <span class="toggle-slider"></span>
            </label>
        </div>
        ${sound.active ? volumeSliderHTML(sound) : ''}
    `;

    // Toggle via header tap
    card.querySelector('.sound-card-header').addEventListener('click', (e) => {
        if (e.target.closest('.toggle')) return;
        toggleSound(sound.id);
    });

    // Toggle via checkbox
    card.querySelector('input[type="checkbox"]').addEventListener('change', () => {
        toggleSound(sound.id);
    });

    // Volume slider
    if (sound.active) {
        bindVolumeSlider(card, sound.id);
    }

    return card;
}

function volumeSliderHTML(sound) {
    const pct = Math.round(sound.volume * 100);
    return `
        <div class="sound-volume">
            <label>Vol</label>
            <input type="range" min="0" max="100" value="${pct}" data-volume-id="${sound.id}">
            <span class="volume-value">${pct}%</span>
        </div>
    `;
}

function updateSoundCard(sound) {
    const card = document.getElementById(`card-${sound.id}`);
    if (!card) return;

    const wasActive = card.classList.contains('active');
    card.classList.toggle('active', sound.active);

    const checkbox = card.querySelector('input[type="checkbox"]');
    if (checkbox) checkbox.checked = sound.active;

    const volumeSection = card.querySelector('.sound-volume');

    if (sound.active && !volumeSection) {
        const div = document.createElement('div');
        div.innerHTML = volumeSliderHTML(sound);
        card.appendChild(div.firstElementChild);
        bindVolumeSlider(card, sound.id);
    } else if (!sound.active && volumeSection) {
        volumeSection.remove();
    } else if (sound.active && volumeSection) {
        // Only update if user isn't actively dragging
        const slider = volumeSection.querySelector('input[type="range"]');
        if (slider && !slider.matches(':active')) {
            const pct = Math.round(sound.volume * 100);
            slider.value = pct;
            volumeSection.querySelector('.volume-value').textContent = `${pct}%`;
        }
    }
}

function bindVolumeSlider(card, id) {
    const slider = card.querySelector(`input[data-volume-id="${id}"]`);
    if (!slider) return;

    slider.addEventListener('input', (e) => {
        const pct = parseInt(e.target.value);
        const span = card.querySelector('.sound-volume .volume-value');
        if (span) span.textContent = `${pct}%`;

        clearTimeout(debounceTimers[id]);
        debounceTimers[id] = setTimeout(() => {
            api('POST', `/api/sounds/${id}/volume`, { volume: pct / 100 })
                .then(s => { state = s; })
                .catch(() => {});
        }, 100);
    });
}

async function toggleSound(id) {
    try {
        state = await api('POST', `/api/sounds/${id}/toggle`);
        renderSounds(state.sounds);
    } catch (e) {
        console.error('Toggle failed:', e);
    }
}

// Master volume
const masterSlider = document.getElementById('master-volume');
const masterValue = document.getElementById('master-volume-value');

masterSlider.addEventListener('input', (e) => {
    const pct = parseInt(e.target.value);
    masterValue.textContent = `${pct}%`;

    clearTimeout(debounceTimers['master']);
    debounceTimers['master'] = setTimeout(() => {
        api('POST', '/api/master-volume', { volume: pct / 100 })
            .then(s => { state = s; })
            .catch(() => {});
    }, 100);
});

// Timer
document.getElementById('timer-presets').addEventListener('click', (e) => {
    const btn = e.target.closest('button[data-minutes]');
    if (!btn) return;
    const minutes = parseInt(btn.dataset.minutes);
    setTimer(minutes);
});

async function setTimer(minutes) {
    try {
        state = await api('POST', '/api/sleep-timer', { minutes });
        renderTimer(state.sleep_timer);
        updateTimerButtons(minutes);
    } catch (e) {
        console.error('Timer failed:', e);
    }
}

function updateTimerButtons(activeMinutes) {
    document.querySelectorAll('#timer-presets button').forEach(btn => {
        const m = parseInt(btn.dataset.minutes);
        btn.classList.toggle('active', m === activeMinutes);
    });
}

function renderTimer(timer) {
    const el = document.getElementById('timer-status');
    if (!timer || timer.remaining_secs <= 0) {
        el.innerHTML = '';
        document.querySelectorAll('#timer-presets button').forEach(btn => {
            btn.classList.remove('active');
        });
        return;
    }

    const mins = Math.floor(timer.remaining_secs / 60);
    const secs = timer.remaining_secs % 60;
    const display = mins > 0
        ? `${mins}m ${String(secs).padStart(2, '0')}s`
        : `${secs}s`;

    el.innerHTML = `${display} remaining <button class="cancel-btn" onclick="setTimer(0)">cancel</button>`;
}

// Polling
async function poll() {
    try {
        state = await api('GET', '/api/status');
        renderSounds(state.sounds);
        renderTimer(state.sleep_timer);

        // Sync master volume if not being dragged
        if (!masterSlider.matches(':active')) {
            const pct = Math.round(state.master_volume * 100);
            masterSlider.value = pct;
            masterValue.textContent = `${pct}%`;
        }
    } catch (e) {
        console.error('Poll failed:', e);
    }
}

// Init
poll();
setInterval(poll, POLL_INTERVAL);
