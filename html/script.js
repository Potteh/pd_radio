(function () {
  const wrap        = document.getElementById('radio-wrap');
  const screen      = document.getElementById('screen');
  const chanNumber  = document.getElementById('chan-number');
  const chanName    = document.getElementById('chan-name');
  const chanFreq    = document.getElementById('chan-freq');
  const lockIcon    = document.getElementById('lock-icon');
  const signalBars  = document.getElementById('signal-bars');
  const batteryFill = document.getElementById('battery-fill');
  const txBar       = document.getElementById('tx-bar');
  const rxBar       = document.getElementById('rx-bar');
  const rxText      = document.getElementById('rx-text');
  const pttOnAudio  = new Audio('sounds/ptt_on.wav');
  const pttOffAudio = new Audio('sounds/ptt_off.wav');
  const receiving   = new Map();
  const micLed      = document.getElementById('mic-led');
  const btnGrid     = document.getElementById('btn-grid');
  const powerBtn    = document.getElementById('power-btn');
  const closeBtn    = document.getElementById('close-btn');

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

  function setChannelDisplay(c) {
    currentChannelId = c.id;
    chanNumber.textContent = 'CH ' + String(c.id).padStart(2, '0');
    chanName.textContent = c.name;
    chanFreq.textContent = c.freq + ' MHz';
    lockIcon.classList.toggle('active', !!c.encrypted);
    renderChannelButtons();
  }

  function setPowered(state) {
    powered = state;
    screen.classList.toggle('off', !state);
    signalBars.classList.toggle('active', state);
    if (!state) {
      txBar.classList.remove('on');
      micLed.classList.remove('live');
      rxBar.classList.remove('on');
      receiving.clear();
    }
  }

  window.addEventListener('message', (event) => {
    const data = event.data;
    switch (data.action) {
      case 'open':
        channels = data.channels || [];
        batteryFill.style.width = (data.battery ?? 100) + '%';
        setPowered(!!data.powered);
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
        rxText.textContent = names.length ? `RX: ${names[names.length - 1]}` : 'RECEIVING';
        break;
      }

      case 'setTransmitting':
        txBar.classList.toggle('on', !!data.state);
        micLed.classList.toggle('live', !!data.state);
        break;
    }
  });

  powerBtn.addEventListener('click', () => post('power'));
  closeBtn.addEventListener('click', () => post('close'));

  // Allow Esc to close, matching most FiveM HUD conventions
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') post('close');
  });
})();
