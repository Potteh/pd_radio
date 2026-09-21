(function () {
  const wrap        = document.getElementById('radio-wrap');
  const screen      = document.getElementById('screen');
  const chanNumber  = document.getElementById('chan-number');
  const chanName    = document.getElementById('chan-name');
  const chanFreq    = document.getElementById('chan-freq');
  const lockIcon    = document.getElementById('lock-icon');
  const signalBars  = document.getElementById('signal-bars');
  const connStatus  = document.getElementById('conn-status');
  const batteryFill = document.getElementById('battery-fill');
  const txBar       = document.getElementById('tx-bar');
  const txText      = document.getElementById('tx-text');
  const rxBar       = document.getElementById('rx-bar');
  const rxText      = document.getElementById('rx-text');
  const pttOnAudio  = new Audio('sounds/ptt_on.wav');
  const pttOffAudio = new Audio('sounds/ptt_off.wav');
  const receiving   = new Map();
  const micLed      = document.getElementById('mic-led');
  const btnGrid     = document.getElementById('btn-grid');
  const powerBtn    = document.getElementById('power-btn');
  const closeBtn    = document.getElementById('close-btn');
  const emergencyBtn = document.getElementById('emergency-btn');
  const panicAlert = document.getElementById('panic-alert');
  const panicName = document.getElementById('panic-name');
  let panicTimer = null;

  let channels = [];
  let currentChannelId = null;
  let powered = false;

  function post(endpoint, data) {
    fetch(`https://${GetParentResourceName()}/${endpoint}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data || {})
    }).catch(() => {});
  }

  function renderChannelButtons() {
    btnGrid.innerHTML = '';
    channels.forEach((c) => {
      const btn = document.createElement('div');
      btn.className = 'chan-btn' + (c.encrypted ? ' locked' : '') + (c.id === currentChannelId ? ' selected' : '');
      btn.innerHTML = `<span class="n">${c.id}</span><span>${c.name}</span>`;
      btn.addEventListener('click', () => {
        if (!powered) return;
        post('selectChannel', { id: c.id });
      });
      btnGrid.appendChild(btn);
    });
  }

  function updateConnectionStatus() {
    const connected = powered && currentChannelId !== null;
    connStatus.classList.toggle('connected', connected);
    connStatus.classList.toggle('offline', !connected);
    connStatus.querySelector('span').textContent = connected ? 'CONNECTED' : 'OFFLINE';
    signalBars.classList.toggle('active', connected);
  }

  function setChannelDisplay(c) {
    currentChannelId = c.id;
    chanNumber.textContent = 'CH ' + String(c.id).padStart(2, '0');
    chanName.textContent = c.name;
    chanFreq.textContent = c.freq + ' MHz';
    lockIcon.classList.toggle('active', !!c.encrypted);
    renderChannelButtons();
    updateConnectionStatus();
  }

  function setPowered(state) {
    powered = state;
    screen.classList.toggle('off', !state);
    updateConnectionStatus();
    if (!state) {
      txBar.classList.remove('on');
      micLed.classList.remove('live');
      rxBar.classList.remove('on');
      receiving.clear();
      currentChannelId = null;
      chanNumber.textContent = '--';
      chanName.textContent = 'NO CHANNEL';
      chanFreq.textContent = '000.000 MHz';
    }
    updateConnectionStatus();
  }

  window.addEventListener('message', (event) => {
    const data = event.data;
    switch (data.action) {
      case 'open':
        channels = data.channels || [];
        batteryFill.style.width = (data.battery ?? 100) + '%';
        setPowered(!!data.powered);
        if (data.currentChannel != null) {
          const active = channels.find((c) => Number(c.id) === Number(data.currentChannel));
          if (active) setChannelDisplay(active);
        }
        renderChannelButtons();
        wrap.classList.remove('hidden');
        break;

      case 'close':
        wrap.classList.add('hidden');
        break;

      case 'powerState':
        setPowered(!!data.state);
        break;

      case 'setChannel':
        setChannelDisplay(data);
        break;

      case 'setBattery':
        batteryFill.style.width = Math.max(0, Math.min(100, data.value)) + '%';
        batteryFill.style.background = data.value <= 15 ? '#ff4d3d' : '';
        break;


      case 'playPTTSound': {
        const audio = data.sound === 'on' ? pttOnAudio : pttOffAudio;
        audio.volume = Math.max(0, Math.min(1, Number(data.volume ?? 0.55)));
        audio.currentTime = 0;
        audio.play().catch(() => {});
        break;
      }

      case 'clearReceiving':
        receiving.clear();
        rxBar.classList.remove('on');
        rxText.textContent = 'RECEIVING';
        break;

      case 'setReceiving': {
        const id = String(data.serverId);
        if (data.state) receiving.set(id, data.name || `UNIT ${id}`);
        else receiving.delete(id);
        const names = Array.from(receiving.values());
        rxBar.classList.toggle('on', names.length > 0);
        if (!names.length) {
          rxText.textContent = 'RX';
        } else if (names.length === 1) {
          rxText.textContent = `RX  ${names[0]}`;
        } else {
          rxText.textContent = `RX ${names.length}  ${names.join(' • ')}`;
        }
        break;
      }

      case 'panicAlert':
        if (panicTimer) clearTimeout(panicTimer);
        panicName.textContent = data.name || 'UNIT';
        panicAlert.classList.add('on');
        panicTimer = setTimeout(() => panicAlert.classList.remove('on'), Number(data.duration || 8000));
        break;

      case 'setTransmitting':
        txBar.classList.toggle('on', !!data.state);
        micLed.classList.toggle('live', !!data.state);
        txText.textContent = data.state && data.name ? `TX  ${data.name}` : 'TX';
        break;
    }
  });

  emergencyBtn.addEventListener('click', () => post('panic'));
  powerBtn.addEventListener('click', () => post('power'));
  closeBtn.addEventListener('click', () => post('close'));

  // Allow Esc to close, matching most FiveM HUD conventions
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') post('close');
  });
})();
