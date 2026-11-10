// Crazy Legs Mundell Rampage — landing page behaviour. Plain script, no build.
(() => {
  'use strict';

  const REPO = 'treymun/crazy-legs-mundell-rampage';
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));

  /** Storage that never throws (private windows, blocked site data). */
  const keep = (area) => ({
    get(key) { try { return window[area].getItem(key); } catch { return null; } },
    set(key, value) { try { window[area].setItem(key, value); } catch { /* not kept */ } },
    drop(key) { try { window[area].removeItem(key); } catch { /* nothing to drop */ } },
  });
  const saved = keep('localStorage');
  const visit = keep('sessionStorage');

  /** el('p', {class: 'x'}, 'text', child) */
  function el(tag, attrs = {}, ...children) {
    const node = document.createElement(tag);
    for (const [name, value] of Object.entries(attrs)) {
      if (name === 'class') node.className = value;
      else if (name === 'text') node.textContent = value;
      else node.setAttribute(name, value);
    }
    for (const child of children) node.append(child);
    return node;
  }

  // ------------------------------------------------------------------ CRT
  const crtButton = $('#crt-toggle');
  function setCrt(on) {
    document.body.classList.toggle('crt-off', !on);
    crtButton.textContent = on ? '[CRT: ON]' : '[CRT: OFF]';
    crtButton.setAttribute('aria-pressed', String(on));
  }
  setCrt(saved.get('clm-crt') !== 'off');
  crtButton.addEventListener('click', () => {
    const on = document.body.classList.contains('crt-off');
    setCrt(on);
    saved.set('clm-crt', on ? 'on' : 'off');
  });

  // --------------------------------------------------------- browser build
  // The game uses threads, which a browser only allows on a cross-origin
  // isolated page. GitHub Pages cannot send the two headers that grant it, so
  // sw.js adds them; a page only becomes isolated on the load after the
  // worker takes over, hence the single reload when Play is first pressed.
  const screen = $('#screen');
  const playButton = $('#play-button');
  const playNote = $('#play-note');
  const fullscreenButton = $('#fullscreen-button');
  const canIsolate = 'serviceWorker' in navigator && window.isSecureContext;
  const worker = canIsolate
    ? navigator.serviceWorker.register('sw.js').then(() => navigator.serviceWorker.ready).catch(() => null)
    : Promise.resolve(null);

  function mountGame() {
    if ($('iframe', screen)) return;
    const frame = el('iframe', {
      src: 'play/index.html',
      title: 'Crazy Legs Mundell Rampage, browser build',
      allow: 'cross-origin-isolated; fullscreen; gamepad; autoplay',
    });
    frame.addEventListener('load', () => frame.focus());
    $('#screen-card').remove();
    $('.screen-still', screen).remove();
    screen.append(frame);
    fullscreenButton.disabled = false;
  }

  function cannotPlayHere() {
    playNote.textContent = 'This browser would not hand over the shared memory the game needs '
      + 'on this page. Try "Open in its own tab", or take one of the downloads.';
  }

  function startGame() {
    if (window.crossOriginIsolated) {
      visit.drop('clm-isolating');
      mountGame();
    } else if (canIsolate && visit.get('clm-isolating') !== 'tried') {
      playButton.disabled = true;
      playNote.textContent = 'Warming up the tubes…';
      visit.set('clm-isolating', 'tried');
      visit.set('clm-autoplay', 'yes');
      worker.then((ready) => (ready ? window.location.reload() : cannotPlayHere()));
    } else {
      cannotPlayHere();
    }
  }

  playButton.addEventListener('click', startGame);
  $$('[data-play]').forEach((link) => link.addEventListener('click', startGame));
  fullscreenButton.addEventListener('click', () => {
    if (screen.requestFullscreen) screen.requestFullscreen().catch(() => {});
  });
  if (visit.get('clm-autoplay')) {
    // Back from the one reload: pick up where the click left off.
    visit.drop('clm-autoplay');
    $('#play').scrollIntoView();
    startGame();
  }

  // ------------------------------------------------------ release details
  fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
    headers: { Accept: 'application/vnd.github+json' },
  }).then((reply) => (reply.ok ? reply.json() : Promise.reject(new Error(reply.status))))
    .then((release) => {
      const sizes = new Map(release.assets.map((asset) => [asset.name, asset.size]));
      $$('[data-asset]').forEach((link) => {
        const size = sizes.get(link.dataset.asset);
        $('[data-size]', link).textContent = size
          ? `${Math.round(size / 1048576)} MB` : 'not in the latest release';
      });
      const day = new Date(release.published_at).toLocaleDateString(undefined,
        { year: 'numeric', month: 'long', day: 'numeric' });
      const line = $('#release-line');
      line.textContent = '';
      line.append('Latest release: ', el('b', { text: release.tag_name }),
        `, published ${day}. Built from the source by GitHub Actions.`);
    }).catch(() => { /* the static labels stand */ });

  fetch('version.txt').then((reply) => (reply.ok ? reply.text() : ''))
    .then((text) => {
      const version = text.trim();
      if (/^[\w.\-]{1,24}$/.test(version)) $('#version').textContent = `· page build ${version}`;
    }).catch(() => {});

  // -------------------------------------------------------------- armory
  // Numbers are the game's own (godot/src/weapons.gd): damage per shot, the
  // delay between shots, reload time and magazine size.
  const WEAPONS = [
    { id: 'crowbar', name: 'Rusted Crowbar', key: '1', damage: 44, hit: '44', fire: .33, reload: 0, mag: 0,
      text: 'Came with the truck. Opens crates, doors and negotiations. Hits harder on a moonshine sprint.' },
    { id: 'revolver', name: '.38 Special', key: '2', damage: 34, hit: '34', fire: .34, reload: .88, mag: 6,
      text: 'Six polite suggestions. Daddy called it the tie-breaker; it has never lost a vote.' },
    { id: 'shotgun', name: 'Sawed-Off', key: '3', damage: 120, hit: '10 × 12', fire: .55, reload: 1.10, mag: 2,
      text: 'Shortened for indoor use. Alt fire empties both barrels and most of the room.' },
    { id: 'crossbow', name: 'Dynamite Crossbow', key: '4', damage: 160, hit: '160 blast', fire: .62, reload: .68, mag: 1,
      text: 'A deer bow with a stick of dynamite where the sense should be. Opens the doors keys will not.' },
    { id: 'rifle', name: 'Ranch Rifle', key: '5', damage: 21, hit: '21', fire: .125, reload: 1.30, mag: 18,
      text: 'Eight rounds a second until it runs hot and starts aiming for itself. Feather it.' },
    { id: 'ripsaw', name: 'Rip Saw', key: '6', damage: 54, hit: '54 blade', fire: .32, reload: .58, mag: 1,
      text: 'Throws a saw blade that bounces three times and remembers who threw it. Alt fire grinds up close for free.' },
    { id: 'armgun', name: 'Alien Arm Gun', key: '7', damage: 50, hit: '50', fire: .34, reload: .88, mag: 6,
      text: 'Not yours. Still warm. The former owner is not asking for it back.' },
    { id: 'tnt', name: 'Dynamite', key: '8', damage: 160, hit: '160 blast', fire: .46, reload: 0, mag: 0,
      text: 'Hold fire to light it, let go to throw it. The fuse is 2.65 seconds whether or not you are counting.' },
    { id: 'slingblade', name: 'Sling Blade', key: '9', damage: 58, hit: '58', fire: .49, reload: 0, mag: 0,
      text: 'Some folks call it a kaiser blade. Longer reach than the crowbar and a worse attitude.' },
    { id: 'bottle_launcher', name: 'Bottle Rocket Launcher', key: '0', damage: 120, hit: '120 blast', fire: .65, reload: .79, mag: 1,
      text: 'Fourth of July, shoulder-fired. Whistles on the way so they know it is coming.' },
    { id: 'bowling_ball', name: 'Bowling Ball', key: '−', damage: 108, hit: '108', fire: .70, reload: .72, mag: 1,
      text: 'League night at the county lanes ended early. Rolls flat, stops for nobody twice.' },
    { id: 'powder_keg', name: 'Powder Keg', key: '=', damage: 240, hit: '240 blast', fire: .80, reload: .95, mag: 1,
      text: 'The biggest bang in the county, lobbed underhand. Stand somewhere else.' },
    { id: 'cow_launcher', name: 'Cow Launcher', key: '\\', damage: 150, hit: '150 blast', fire: .95, reload: 1.10, mag: 1,
      text: 'She moos on the way out. Nobody has asked the cow.' },
    { id: 'teat_gun', name: 'Teat Gun', key: '`', damage: 10, hit: '10', fire: .095, reload: 1.25, mag: 30,
      text: 'Thirty rounds of fresh whole milk at ten and a half a second. Does a body bad.' },
  ];
  const frames = window.CLM_FRAMES || {};
  const pegboard = $('#pegboard');
  const TOP = { damage: 240, rate: 10.6, reload: 1.4, mag: 30 };

  function dress(sprite, id, maxWidth, maxHeight) {
    const strip = frames[id];
    if (!strip) return;
    let scale = Math.min(maxWidth / strip.w, maxHeight / strip.h);
    if (scale >= 1) scale = Math.floor(scale);            // whole pixels when growing
    const width = Math.round(strip.w * scale);
    const height = Math.round(strip.h * scale);
    sprite.style.width = `${width}px`;
    sprite.style.height = `${height}px`;
    sprite.style.backgroundImage = `url(img/weapons/${id}.png)`;
    sprite.style.backgroundSize = `${width * strip.frames}px ${height}px`;
    sprite.style.setProperty('--shift', `${-width * strip.frames}px`);
    sprite.style.animation = `strip ${strip.frames * 170}ms steps(${strip.frames}) infinite`;
  }

  function stat(list, label, share, figure) {
    const meter = el('div', { class: 'meter' }, el('i'));
    meter.firstChild.style.width = `${Math.max(0, Math.min(1, share)) * 100}%`;
    list.append(el('dt', { text: label }), el('dd', {}, meter), el('dd', { class: 'figure', text: figure }));
  }

  function show(weapon) {
    $$('.gun', pegboard).forEach((card) => {
      const picked = card.dataset.id === weapon.id;
      card.setAttribute('aria-selected', String(picked));
      card.tabIndex = picked ? 0 : -1;
    });
    const view = $('#bench-sprite');
    dress(view, weapon.id, Math.min(300, $('.bench-view').clientWidth - 30), 150);
    view.setAttribute('aria-label', `${weapon.name}, animated`);
    $('#bench-key').textContent = `Key ${weapon.key}`;
    $('#bench-name').textContent = weapon.name;
    $('#bench-text').textContent = weapon.text;
    const list = $('#bench-stats');
    list.textContent = '';
    const rate = 1 / weapon.fire;
    stat(list, 'Damage', weapon.damage / TOP.damage, weapon.hit);
    stat(list, 'Rate', rate / TOP.rate, `${rate.toFixed(1)} / sec`);
    stat(list, 'Reload', weapon.reload ? 1 - weapon.reload / TOP.reload : 1,
      weapon.reload ? `${weapon.reload.toFixed(2)} s` : 'never');
    stat(list, 'Magazine', weapon.mag / TOP.mag, weapon.mag ? String(weapon.mag) : weapon.id === 'tnt' ? 'by the stick' : 'none');
  }

  WEAPONS.forEach((weapon) => {
    const sprite = el('div', { class: 'sprite' });
    dress(sprite, weapon.id, 112, 82);
    const card = el('button', { class: 'gun', type: 'button', role: 'option', 'data-id': weapon.id,
      'aria-selected': 'false', tabindex: '-1' }, sprite, el('span', { class: 'label', text: weapon.name }));
    card.addEventListener('click', () => show(weapon));
    pegboard.append(card);
  });
  pegboard.addEventListener('keydown', (event) => {
    const cards = $$('.gun', pegboard);
    const at = cards.indexOf(document.activeElement);
    const step = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[event.key];
    if (at < 0 || !step) return;
    event.preventDefault();
    const next = cards[(at + step + cards.length) % cards.length];
    next.focus();
    next.click();
  });
  show(WEAPONS[1]);

  // ------------------------------------------------------------ chapters
  // Objectives, districts and sign-offs are the game's own text (campaign.py).
  const CHAPTERS = [
    { id: 'hickston', tab: 'Hickston', order: 'Chapter one', title: 'The Hickston Incident', shot: 'shot_hickston',
      caption: 'County road, facing Stanky\'s. Evening.',
      job: 'Find the brass key to Stanky\'s back office, then the steel one, and work north through the barn and the trailer lot to the pasture where they are keeping her.',
      stops: ['County Road', 'Stanky\'s Bar & Grill', 'Restroom', 'Supply Room', 'Feed Barn', 'Hog Pen', 'Packing Shed', 'Dispatch Office', 'Trailer Lot', 'Dry Creek', 'North Pasture'],
      bosses: [
        { name: 'The Alien Sheriff', img: 'boss_sheriff', text: 'Charges a plasma shot you can hear coming. Under half health he fires three at a time and hurries.' },
        { name: 'Jerry Jones', img: 'boss_jerry', text: 'Blows a whistle, then throws a football that hurts. Three footballs once he is losing.' },
      ],
      secrets: 'Three hidden rooms. Check the mirror in the GENTS while you are in there.',
      signoff: '"Next time, take the tractor."' },
    { id: 'fair', tab: 'County Fair', order: 'Chapter two', title: 'Possum County Fair', shot: 'shot_fair',
      caption: 'Main gate. The prize pavilion is lit; nobody is selling tickets.',
      job: 'Set concession power and patch the backstage PA. The patch lead is in the raffle office, and the shooting gallery pays out if you can still aim.',
      stops: ['Ticket Shack', 'The Midway', 'Concession Alley', 'Game Court', 'Prize Pavilion', 'Service Exit', 'Freight and Raffle Lot', 'Backstage Sideshows', 'PA Booth'],
      bosses: [
        { name: 'Rudy Racket', img: 'boss_rudy', text: 'Sweeps the stage with five horn blasts. His health bar calls LEFT HORN or RIGHT HORN first. Two of him are cardboard.' },
      ],
      secrets: 'Three hidden rooms. One hatch is low enough that you have to duck for it.',
      signoff: '"No refunds after the abduction."' },
    { id: 'sawmill', tab: 'Blackwater', order: 'Chapter three', title: 'Blackwater Timber', shot: 'shot_sawmill',
      caption: 'Delivery yard, looking over the flooded log pond.',
      job: 'Isolate the west feed and trip the dry-kiln belt. The handle on the belt release is stripped, so it wants hitting rather than turning.',
      stops: ['Delivery Yard', 'Flooded Log Pond', 'West Bank', 'East Bank', 'The Cutting Shed', 'Loading Apron', 'Green Chain Sort', 'Dry Kilns', 'Rain Storage'],
      bosses: [
        { name: 'The Splinter Foreman', img: 'boss_foreman', text: 'Sends saw blades down marked lanes, three lanes and then two. When it reads GAP IN THE MIDDLE, stand in the middle.' },
      ],
      secrets: 'Three hidden rooms. The county map only draws a secret once you have found it.',
      signoff: '"Clock out. Leave the boots outside."' },
    { id: 'quarry', tab: 'Stillwater', order: 'Chapter four', title: 'Stillwater Cut', shot: 'shot_quarry',
      caption: 'County weigh station at the limestone cut.',
      job: 'Stop the cutting feed and divert the copper condenser. The valves take cranking, and the works behind the cut is bottling something that is not spring water.',
      stops: ['County Weigh Station', 'Limestone Cut Yard', 'Cutting Shed', 'Condenser Yard', 'Bottling Works', 'Loading Court', 'Lower Cut', 'Chalk Terraces', 'Copper Recovery'],
      bosses: [
        { name: 'The Copper Baron', img: 'boss_baron', text: 'Takes turns venting steam from floor outlets and sweeping it across the room. Open a relief valve first: one outlet instead of two, and he recovers slower.' },
      ],
      secrets: 'Three hidden rooms in the cut and the works.',
      signoff: '"Weight includes contents and debts."' },
    { id: 'hub', tab: 'Crossroads', order: 'The hub', title: 'County Crossroads', shot: 'shot_hub',
      caption: 'The service road, in the shadow of the county water tower.',
      job: 'Every finished chapter opens the next gate here. Face a gate and press E to continue, revisit a finished chapter, or replay one from scratch with a fresh kit.',
      stops: ['Four road gates', 'Dispatch board', 'County service road', 'Water tower', 'Road shed', 'Culvert'],
      bosses: [],
      secrets: 'Road notes are pinned around the hub and in each chapter. The county map keeps count.',
      signoff: '"County crossroads. Face a gate and press E."' },
  ];
  const tabs = $('#chapter-tabs');
  const panel = $('#chapter-panel');

  function open(chapter) {
    $$('button', tabs).forEach((tab) => {
      const picked = tab.dataset.id === chapter.id;
      tab.setAttribute('aria-selected', String(picked));
      tab.tabIndex = picked ? 0 : -1;
    });
    panel.setAttribute('aria-labelledby', `tab-${chapter.id}`);
    panel.textContent = '';
    const photo = el('figure', { class: 'photo' },
      el('img', { src: `img/${chapter.shot}.png`, alt: chapter.caption }),
      el('figcaption', { text: chapter.caption }));
    const file = el('div', {},
      el('p', { class: 'order', text: chapter.order }),
      el('h3', { text: chapter.title }),
      el('h4', { text: 'The job' }), el('p', { text: chapter.job }),
      el('h4', { text: 'Stops on the route' }),
      el('ul', { class: 'stops' }, ...chapter.stops.map((stop) => el('li', { text: stop }))));
    if (chapter.bosses.length) {
      file.append(el('h4', { text: 'Waiting at the end' }),
        el('div', { class: 'mugs' }, ...chapter.bosses.map((boss) => el('div', { class: 'mug' },
          el('div', { class: 'frame' }, el('img', { src: `img/${boss.img}.png`, alt: '' })),
          el('p', {}, el('b', { text: boss.name }), boss.text)))));
    }
    file.append(el('h4', { text: 'Off the route' }), el('p', { text: chapter.secrets }),
      el('p', { class: 'signoff', text: chapter.signoff }));
    panel.append(el('div', {}, photo, el('span', { class: 'stamp', text: 'Route approved' })), file);
  }

  CHAPTERS.forEach((chapter) => {
    const tab = el('button', { type: 'button', role: 'tab', id: `tab-${chapter.id}`, 'data-id': chapter.id,
      'aria-controls': 'chapter-panel', 'aria-selected': 'false', tabindex: '-1', text: chapter.tab });
    tab.addEventListener('click', () => open(chapter));
    tabs.append(tab);
  });
  tabs.addEventListener('keydown', (event) => {
    const all = $$('button', tabs);
    const at = all.indexOf(document.activeElement);
    const step = { ArrowRight: 1, ArrowLeft: -1 }[event.key];
    if (at < 0 || !step) return;
    event.preventDefault();
    const next = all[(at + step + all.length) % all.length];
    next.focus();
    next.click();
  });
  open(CHAPTERS[0]);

  // ------------------------------------------------------------- jukebox
  const SIDES = [
    ['Hickston', [['music', 'County Road Shuffle'], ['county_line', 'County Line at Sundown'], ['porchlight_stomp', 'Porchlight Stomp']]],
    ['The fair', [['fair_score', 'The Wheel Turns Crooked'], ['tickets_after_dark', 'Tickets After Dark'], ['closing_time_shuffle', 'Last Call at the Midway']]],
    ['Blackwater', [['mill_score', 'Rain on the Green Chain'], ['green_chain', 'Green Chain Blues'], ['apron_run', 'Across the Loading Apron']]],
    ['Stillwater', [['quarry_score', 'Limestone Stomp'], ['copper_and_steam', 'Copper and Steam'], ['last_load', 'Last Load from Stillwater']]],
  ];
  const HOLLERS = [['yee_haw', 'Yee-haw'], ['yee_haw_alt', 'Yee-haw, again'], ['belch', 'Belch'], ['gulp', 'Beer'],
    ['moonshine', 'Moonshine'], ['shotgun_both', 'Both barrels'], ['cow_moo', 'Cow, outbound'], ['pig', 'Hog'],
    ['chicken', 'Chicken'], ['rudy_horn', 'Rudy\'s horn'], ['sheriff_siren', 'Sheriff'], ['got_bessie', 'Got Bessie']];
  const player = $('#player');
  const stop = $('#juke-stop');
  const nowPlaying = $('#juke-title');
  const progress = $('#juke-progress');

  function quiet() {
    player.pause();
    $$('.record').forEach((record) => record.setAttribute('aria-pressed', 'false'));
    nowPlaying.textContent = 'Pick a record.';
    progress.style.width = '0';
    stop.disabled = true;
  }

  SIDES.forEach(([side, tracks]) => {
    const list = el('ul');
    tracks.forEach(([stem, title]) => {
      const record = el('button', { class: 'record', type: 'button', 'aria-pressed': 'false', text: title });
      record.addEventListener('click', () => {
        const playing = record.getAttribute('aria-pressed') === 'true';
        quiet();
        if (playing) return;
        player.src = `audio/${stem}.mp3`;
        player.play().then(() => {
          record.setAttribute('aria-pressed', 'true');
          nowPlaying.textContent = title;
          stop.disabled = false;
        }).catch(() => { nowPlaying.textContent = 'That record skipped. Try it again.'; });
      });
      list.append(el('li', {}, record));
    });
    $('#records').append(el('div', {}, el('h3', { text: side }), list));
  });
  player.addEventListener('timeupdate', () => {
    if (player.duration) progress.style.width = `${(player.currentTime / player.duration) * 100}%`;
  });
  player.addEventListener('ended', quiet);
  stop.addEventListener('click', quiet);

  HOLLERS.forEach(([stem, label]) => {
    const key = el('button', { class: 'holler', type: 'button', text: label });
    key.addEventListener('click', () => { new Audio(`audio/${stem}.mp3`).play().catch(() => {}); });
    $('#hollers').append(key);
  });
})();
