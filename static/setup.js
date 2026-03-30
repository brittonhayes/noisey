(function () {
    'use strict';

    const $ = (sel) => document.querySelector(sel);
    const scanSection = $('#scan-section');
    const connectSection = $('#connect-section');
    const successSection = $('#success-section');
    const networkList = $('#network-list');
    const statusBanner = $('#status-banner');
    const statusText = $('#status-text');
    const refreshBtn = $('#refresh-btn');
    const connectForm = $('#connect-form');
    const backBtn = $('#back-btn');
    const connectBtn = $('#connect-btn');
    const selectedSsidEl = $('#selected-ssid');
    const passwordInput = $('#password');
    const deviceIpEl = $('#device-ip');

    let selectedSsid = '';

    function showStatus(message, type) {
        statusText.textContent = message;
        statusBanner.className = 'status-banner ' + type;
    }

    function hideStatus() {
        statusBanner.className = 'status-banner hidden';
    }

    function signalBars(signal) {
        const level = signal > 75 ? 4 : signal > 50 ? 3 : signal > 25 ? 2 : 1;
        let html = '<div class="signal-bars">';
        for (let i = 1; i <= 4; i++) {
            html += '<div class="signal-bar' + (i <= level ? ' active' : '') + '"></div>';
        }
        html += '</div>';
        return html;
    }

    function renderNetworks(networks) {
        if (networks.length === 0) {
            networkList.innerHTML = '<div class="loading">No networks found. Try refreshing.</div>';
            return;
        }

        networkList.innerHTML = networks.map(function (net) {
            const lock = net.security !== '--' && net.security !== ''
                ? '<svg class="lock-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>'
                : '';
            return '<button class="network-item" data-ssid="' + net.ssid.replace(/"/g, '&quot;') + '">'
                + '<span class="network-name">' + net.ssid.replace(/</g, '&lt;') + '</span>'
                + '<span class="network-meta">' + signalBars(net.signal) + lock + '</span>'
                + '</button>';
        }).join('');

        networkList.querySelectorAll('.network-item').forEach(function (item) {
            item.addEventListener('click', function () {
                selectedSsid = this.dataset.ssid;
                selectedSsidEl.textContent = selectedSsid;
                scanSection.classList.add('hidden');
                connectSection.classList.remove('hidden');
                hideStatus();
                passwordInput.value = '';
                passwordInput.focus();
            });
        });
    }

    async function scanNetworks() {
        networkList.innerHTML = '<div class="loading">Scanning for networks...</div>';
        refreshBtn.classList.add('spinning');

        try {
            const res = await fetch('/api/wifi/scan');
            if (!res.ok) throw new Error('Scan failed');
            const networks = await res.json();
            renderNetworks(networks);
        } catch (e) {
            networkList.innerHTML = '<div class="loading">Scan failed. Try again.</div>';
        } finally {
            refreshBtn.classList.remove('spinning');
        }
    }

    refreshBtn.addEventListener('click', scanNetworks);

    backBtn.addEventListener('click', function () {
        connectSection.classList.add('hidden');
        scanSection.classList.remove('hidden');
        hideStatus();
    });

    connectForm.addEventListener('submit', async function (e) {
        e.preventDefault();

        const password = passwordInput.value;
        connectBtn.disabled = true;
        connectBtn.textContent = 'Connecting...';
        showStatus('Connecting to ' + selectedSsid + '...', 'connecting');

        try {
            const res = await fetch('/api/wifi/connect', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ ssid: selectedSsid, password: password }),
            });

            const data = await res.json();

            if (data.state === 'connected') {
                connectSection.classList.add('hidden');
                successSection.classList.remove('hidden');
                deviceIpEl.textContent = data.ip || 'your-device-ip';
                showStatus('Connected successfully!', 'success');
            } else {
                const reason = data.reason || 'Connection failed. Check your password and try again.';
                showStatus(reason, 'error');
            }
        } catch (e) {
            // Connection may drop when hotspot goes down — that can mean success
            showStatus('Connection may have succeeded. Check your router for the device.', 'connecting');
            // Poll status after a delay
            setTimeout(pollStatus, 5000);
        } finally {
            connectBtn.disabled = false;
            connectBtn.textContent = 'Connect';
        }
    });

    async function pollStatus() {
        try {
            const res = await fetch('/api/wifi/status');
            const data = await res.json();
            if (data.state === 'connected') {
                connectSection.classList.add('hidden');
                successSection.classList.remove('hidden');
                deviceIpEl.textContent = data.ip || 'your-device-ip';
                showStatus('Connected successfully!', 'success');
            }
        } catch (e) {
            // Device may be on a different network now
        }
    }

    // Initial scan
    scanNetworks();
})();
