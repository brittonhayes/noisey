const POLL_INTERVAL = 2000;

let state = null;
let debounceTimers = {};
let soundsCreated = false;
let currentVolLevel = 1;
let playing = false;
let activeSoundId = null;
let volumeDragging = false;

// ========================================
// API
// ========================================

async function api(method, path, body) {
    const opts = { method, headers: {} };
    if (body !== undefined) {
        opts.headers['Content-Type'] = 'application/json';
        opts.body = JSON.stringify(body);
    }
    try {
        const res = await fetch(path, opts);
        if (!res.ok) throw new Error('HTTP ' + res.status);
        setConnected(true);
        return await res.json();
    } catch (e) {
        setConnected(false);
        throw e;
    }
}

function setConnected(connected) {
    // connection state tracked internally, no visual indicator
}

// ========================================
// VOLUME — DOTS (passive) + MOON SWIPE (active)
// ========================================

const volumeDots = document.getElementById('volume-dots');
const volumeHint = document.getElementById('volume-hint');
const moonGlow = document.getElementById('moon-glow');
const moonContainer = document.getElementById('moon-container');

function setVolumeLevel(level) {
    level = Math.max(1, Math.min(10, level));
    currentVolLevel = level;
    const t = level / 10;

    // Update dot fills
    const dots = volumeDots.querySelectorAll('.vol-dot');
    dots.forEach((d) => {
        const dotLevel = parseInt(d.dataset.level);
        d.classList.toggle('filled', dotLevel <= level);
        d.classList.toggle('peak', dotLevel === level);
    });

    // Moon phase + glow
    updateMoonPhase(t);
    updateMoonGlow(t);

    // Stars — always faintly visible, brighter with volume
    for (let i = 0; i < stars.length; i++) {
        const s = stars[i];
        // Ambient baseline: all stars shimmer faintly even at zero volume
        const ambient = s.size >= 2 ? 0.15 : s.size >= 1.5 ? 0.1 : 0.06;
        const visibility = Math.max(0, (t - s.threshold * 0.6) / (1 - s.threshold * 0.6));
        const volumeBrightness = visibility * (s.size >= 2 ? 0.85 : s.size >= 1.5 ? 0.7 : 0.5);
        const brightness = Math.max(ambient, volumeBrightness);
        s.el.style.setProperty('--star-base', (brightness * 0.35).toFixed(3));
        s.el.style.setProperty('--star-peak', brightness.toFixed(3));
        s.el.style.opacity = 1;
    }
}

function updateMoonPhase(t) {
    if (window.drawMoonPhase) window.drawMoonPhase(t);
}

let glowBaseOpacity = 0;

function updateMoonGlow(t) {
    glowBaseOpacity = t * t * t * 0.35;
    if (!playing) {
        moonGlow.style.opacity = glowBaseOpacity.toFixed(3);
    }
    const scale = 1 + t * t * 0.2;
    moonGlow.style.transform = `scale(${scale.toFixed(2)})`;
}

// Onboarding hint — show once, dismiss on first moon touch
const onboardingHint = document.getElementById('onboarding-hint');
if (localStorage.getItem('noisey-onboarded')) {
    onboardingHint.style.display = 'none';
}

function dismissOnboarding() {
    if (onboardingHint.style.display !== 'none') {
        onboardingHint.style.display = 'none';
        localStorage.setItem('noisey-onboarded', '1');
    }
}

// Moon swipe volume control
(function bindMoonVolume() {
    let dragging = false;
    let startY = 0;
    let startLevel = 1;
    let hideHintTimer = null;

    function showHint(level) {
        volumeHint.textContent = level * 10;
        volumeHint.classList.add('visible');
        clearTimeout(hideHintTimer);
    }

    function hideHint() {
        clearTimeout(hideHintTimer);
        hideHintTimer = setTimeout(() => {
            volumeHint.classList.remove('visible');
        }, 1000);
    }

    function applyLevel(level) {
        setVolumeLevel(level);
        showHint(level);
        clearTimeout(debounceTimers['master']);
        debounceTimers['master'] = setTimeout(() => {
            api('POST', '/api/volume', { volume: level / 10 })
                .then(s => { state = s; })
                .catch(() => {});
        }, 150);
    }

    moonContainer.addEventListener('pointerdown', (e) => {
        dragging = true;
        volumeDragging = true;
        startY = e.clientY;
        startLevel = currentVolLevel;
        moonContainer.setPointerCapture(e.pointerId);
        moonContainer.classList.add('touching');
        volumeDots.classList.add('active');
        dismissOnboarding();
        showHint(currentVolLevel);
    });

    moonContainer.addEventListener('pointermove', (e) => {
        if (!dragging) return;
        e.preventDefault();
        // Drag up = increase volume, down = decrease
        const deltaY = startY - e.clientY;
        const deltaLevels = Math.round(deltaY / 15); // ~15px per level step
        const newLevel = Math.max(1, Math.min(10, startLevel + deltaLevels));
        applyLevel(newLevel);
    });

    moonContainer.addEventListener('pointerup', () => {
        dragging = false;
        volumeDragging = false;
        moonContainer.classList.remove('touching');
        volumeDots.classList.remove('active');
        hideHint();
    });

    moonContainer.addEventListener('pointercancel', () => {
        dragging = false;
        volumeDragging = false;
        moonContainer.classList.remove('touching');
        volumeDots.classList.remove('active');
        hideHint();
    });
})();

// Glow pulse when playing
let glowPulseRaf = null;

function startGlowPulse() {
    if (glowPulseRaf) return;
    function pulse() {
        const sin = Math.sin(Date.now() / 5000 * Math.PI * 2);
        const modulated = glowBaseOpacity * (1 + sin * 0.08);
        moonGlow.style.opacity = Math.max(0, modulated).toFixed(3);
        glowPulseRaf = requestAnimationFrame(pulse);
    }
    glowPulseRaf = requestAnimationFrame(pulse);
}

function stopGlowPulse() {
    if (glowPulseRaf) {
        cancelAnimationFrame(glowPulseRaf);
        glowPulseRaf = null;
    }
    moonGlow.style.opacity = glowBaseOpacity.toFixed(3);
}

// ========================================
// STARFIELD
// ========================================

const starfield = document.getElementById('starfield');
const stars = [];
const STAR_COUNT = 150;

(function createStars() {
    for (let i = 0; i < STAR_COUNT; i++) {
        const el = document.createElement('div');
        const r = Math.random();
        const size = r < 0.05 ? 2.5 : r < 0.2 ? 2 : r < 0.5 ? 1.5 : 1;
        const x = Math.random() * 100;
        const y = Math.random() * 100;
        const threshold = Math.random();
        const delay = Math.random() * 10;
        // All stars twinkle — varied speeds for organic feel
        const speed = 3 + Math.random() * 5; // 3–8s
        const driftTime = 15 + Math.random() * 25; // 15–40s
        const dx = (Math.random() - 0.5) * 3; // subtle drift ±1.5px
        const dy = (Math.random() - 0.5) * 3;
        el.className = 'star';
        el.style.width = size + 'px';
        el.style.height = size + 'px';
        el.style.left = x + '%';
        el.style.top = y + '%';
        el.style.animationDelay = delay + 's';
        el.style.setProperty('--star-base', '0');
        el.style.setProperty('--star-peak', '0');
        el.style.setProperty('--star-speed', speed + 's');
        el.style.setProperty('--star-drift', driftTime + 's');
        el.style.setProperty('--star-dx', dx + 'px');
        el.style.setProperty('--star-dy', dy + 'px');
        starfield.appendChild(el);
        stars.push({ el, threshold, size });
    }
})();

setVolumeLevel(1);

// ========================================
// PLAY / PAUSE
// ========================================

const playBtn = document.getElementById('play-btn');
const playIcon = document.getElementById('play-icon');
const pauseIcon = document.getElementById('pause-icon');

function updatePlayState(isPlaying) {
    playing = isPlaying;
    playBtn.classList.toggle('playing', playing);
    playIcon.style.display = playing ? 'none' : 'block';
    pauseIcon.style.display = playing ? 'block' : 'none';

    if (playing) {
        startGlowPulse();
    } else {
        stopGlowPulse();
    }
}

playBtn.addEventListener('click', async () => {
    if (playing && activeSoundId) {
        // Pause: toggle off the active sound
        try {
            state = await api('POST', '/api/sounds/' + activeSoundId + '/toggle');
            renderSounds(state.sounds);
        } catch (e) { console.error('Pause failed:', e); }
    } else {
        // Play: if we have an activeSoundId, toggle it on; otherwise pick default
        const soundId = activeSoundId || getDefaultSoundId();
        if (soundId) {
            try {
                state = await api('POST', '/api/sounds/' + soundId + '/toggle');
                renderSounds(state.sounds);
            } catch (e) { console.error('Play failed:', e); }
        }
    }
});

function getDefaultSoundId() {
    if (!state || !state.sounds) return null;
    // Prefer "Ocean Surf" or first sound
    const ocean = state.sounds.find(s => s.name.toLowerCase().includes('ocean'));
    return ocean ? ocean.id : state.sounds[0].id;
}

// ========================================
// SOUNDS — PILL GRID (in drawer)
// ========================================

function renderSounds(sounds) {
    const container = document.getElementById('sounds-grid');

    // Determine active sound
    const activeSound = sounds.find(s => s.active);
    const isPlaying = !!activeSound;
    updatePlayState(isPlaying);

    if (activeSound) {
        activeSoundId = activeSound.id;
    }

    if (!soundsCreated) {
        container.innerHTML = '';
        sounds.forEach(sound => {
            const pill = document.createElement('button');
            pill.className = 'sound-pill' + (sound.active ? ' active' : '');
            pill.id = 'pill-' + sound.id;
            pill.type = 'button';
            pill.textContent = sound.name;
            pill.addEventListener('click', () => toggleSound(sound.id));
            container.appendChild(pill);
        });
        soundsCreated = true;
    } else {
        sounds.forEach(sound => {
            const pill = document.getElementById('pill-' + sound.id);
            if (pill) pill.classList.toggle('active', sound.active);
        });
    }
}

async function toggleSound(id) {
    try {
        state = await api('POST', '/api/sounds/' + id + '/toggle');
        activeSoundId = id;
        renderSounds(state.sounds);
    } catch (e) {
        console.error('Toggle failed:', e);
    }
}

// ========================================
// DRAWER
// ========================================

const drawer = document.getElementById('drawer');
const backdrop = document.getElementById('drawer-backdrop');
const soundsBtn = document.getElementById('sounds-btn');
const doneBtn = document.getElementById('drawer-done');

function openDrawer() {
    drawer.classList.add('open');
    backdrop.classList.add('open');
}

function closeDrawer() {
    drawer.classList.remove('open');
    backdrop.classList.remove('open');
}

soundsBtn.addEventListener('click', openDrawer);
doneBtn.addEventListener('click', closeDrawer);
backdrop.addEventListener('click', closeDrawer);

// ========================================
// TIMER
// ========================================

document.getElementById('timer-presets').addEventListener('click', (e) => {
    const btn = e.target.closest('button[data-minutes]');
    if (!btn) return;
    setTimer(parseInt(btn.dataset.minutes));
});

async function setTimer(minutes) {
    try {
        state = await api('POST', '/api/sleep-timer', { minutes: minutes });
        renderTimer(state.sleep_timer);
        updateTimerButtons(minutes);
    } catch (e) {
        console.error('Timer failed:', e);
    }
}

function updateTimerButtons(activeMinutes) {
    document.querySelectorAll('#timer-presets button').forEach(btn => {
        btn.classList.toggle('active', parseInt(btn.dataset.minutes) === activeMinutes);
    });
}

function renderTimer(timer) {
    const drawerStatus = document.getElementById('timer-status');

    if (!timer || timer.remaining_secs <= 0) {
        drawerStatus.innerHTML = '';
        document.querySelectorAll('#timer-presets button').forEach(btn => {
            btn.classList.remove('active');
        });
        updateMainStatus();
        return;
    }

    const mins = Math.floor(timer.remaining_secs / 60);
    const secs = timer.remaining_secs % 60;
    const display = mins > 0
        ? mins + 'm ' + String(secs).padStart(2, '0') + 's'
        : secs + 's';

    drawerStatus.innerHTML = display + ' <button class="cancel-btn" type="button" onclick="setTimer(0)">cancel</button>';
    updateMainStatus();
}

// ========================================
// SCHEDULE
// ========================================

const scheduleToggle = document.getElementById('schedule-toggle');
const scheduleStart = document.getElementById('schedule-start');
const scheduleStop = document.getElementById('schedule-stop');
const scheduleStatus = document.getElementById('schedule-status');

let scheduleEnabled = false;

scheduleToggle.addEventListener('click', () => {
    scheduleEnabled = !scheduleEnabled;
    saveSchedule();
});

scheduleStart.addEventListener('change', () => { if (scheduleEnabled) saveSchedule(); });
scheduleStop.addEventListener('change', () => { if (scheduleEnabled) saveSchedule(); });

async function saveSchedule() {
    try {
        const activeSound = state && state.sounds && state.sounds.find(s => s.active);
        const soundId = activeSound ? activeSound.id : (state && state.sounds && state.sounds[0] ? state.sounds[0].id : '');

        state = await api('POST', '/api/schedule', {
            start_time: scheduleStart.value,
            stop_time: scheduleStop.value,
            sound_id: soundId,
            enabled: scheduleEnabled
        });
        renderSchedule(state.schedule);
    } catch (e) {
        console.error('Schedule save failed:', e);
    }
}

function renderSchedule(schedule) {
    if (schedule) {
        scheduleStart.value = schedule.start_time;
        scheduleStop.value = schedule.stop_time;
        scheduleEnabled = schedule.enabled;
    }
    scheduleToggle.classList.toggle('on', scheduleEnabled);

    if (scheduleEnabled) {
        const now = new Date();
        const nowMins = now.getHours() * 60 + now.getMinutes();
        const [sh, sm] = scheduleStart.value.split(':').map(Number);
        const [eh, em] = scheduleStop.value.split(':').map(Number);
        const startMins = sh * 60 + sm;
        const stopMins = eh * 60 + em;

        let inWindow;
        if (startMins <= stopMins) {
            inWindow = nowMins >= startMins && nowMins < stopMins;
        } else {
            inWindow = nowMins >= startMins || nowMins < stopMins;
        }
        scheduleStatus.innerHTML = '';
    } else {
        scheduleStatus.innerHTML = '';
    }

    updateMainStatus();
}

// ========================================
// MAIN SCREEN STATUS LINE
// ========================================

function updateMainStatus() {
    const el = document.getElementById('status-line');
    const parts = [];

    // Timer
    if (state && state.sleep_timer && state.sleep_timer.remaining_secs > 0) {
        const mins = Math.floor(state.sleep_timer.remaining_secs / 60);
        const secs = state.sleep_timer.remaining_secs % 60;
        const display = mins > 0
            ? mins + 'm ' + String(secs).padStart(2, '0') + 's'
            : secs + 's';
        parts.push('sleep ' + display + ' <button class="cancel-btn" type="button" onclick="setTimer(0)">cancel</button>');
    }


    el.innerHTML = parts.join(' · ');
}

// ========================================
// POLLING
// ========================================

async function poll() {
    try {
        state = await api('GET', '/api/status');
        renderSounds(state.sounds);
        renderTimer(state.sleep_timer);

        document.getElementById('sim-badge').hidden = !state.simulate;

        if (!volumeDragging) {
            const masterPct = Math.max(1, Math.round(state.master_volume * 100));
            const level = Math.max(1, Math.round(masterPct / 10));
            setVolumeLevel(level);
        }

        renderSchedule(state.schedule);
    } catch (e) {
        console.error('Poll failed:', e);
    }
}

poll();
setInterval(poll, POLL_INTERVAL);
