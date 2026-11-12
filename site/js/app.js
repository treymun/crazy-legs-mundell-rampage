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
  // Older releases installed Godot's own offline worker under play/, and it
  // keeps handing out the old game from its cache. Remove it and its caches;
  // sw.js (which caches nothing) is the only worker the site uses now.
  if (canIsolate) {
    navigator.serviceWorker.getRegistrations().then((found) => found.forEach((r) => {
      const script = (r.active || r.waiting || r.installing || {}).scriptURL || '';
      if (!/\/sw\.js$/.test(script)) r.unregister();
    })).catch(() => {});
    if (window.caches) {
      caches.keys().then((keys) => keys.forEach((k) => {
        if (/sw-cache/.test(k)) caches.delete(k);
      })).catch(() => {});
    }
  }
  const worker = canIsolate
    ? navigator.serviceWorker.register('sw.js').then(() => navigator.serviceWorker.ready).catch(() => null)
    : Promise.resolve(null);

  // Phones and tablets from Apple run every browser on one engine that will
  // not reliably give a page shared memory, and so will any browser that
  // refuses to isolate this page. Those get the lighter build: one thread,
  // the view drawn at half size and doubled, and no isolation needed.
  const apple = /iPad|iPhone|iPod/.test(navigator.userAgent)
    || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const wantsLite = apple || new URLSearchParams(window.location.search).has('lite');
  if (wantsLite) $('#own-tab').setAttribute('href', 'play/lite/');

  function mountGame(lite) {
    if ($('iframe', screen)) return;
    const frame = el('iframe', {
      src: lite ? 'play/lite/index.html' : 'play/index.html',
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
    playNote.textContent = 'This browser would not hand over shared memory, so this is the lighter '
      + 'build: same game, a chunkier picture.';
    mountGame(true);
  }

  function startGame() {
    if (wantsLite) {
      playNote.textContent = 'Lighter build for this device: same game, a chunkier picture.';
      mountGame(true);
    } else if (window.crossOriginIsolated) {
      visit.drop('clm-isolating');
      mountGame(false);
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
  // Numbers are the game's own (godot/src/weapons.gd): damage per shot and the
  // delay between shots. Only the .38 and the sawed-off reload; the rest feed
  // straight from what you are carrying.
  const WEAPONS = [
    { id: 'crowbar', name: 'Rusted Crowbar', key: '1', damage: 44, hit: '44', fire: .33, reload: 0, mag: 0,
      text: 'Came with the truck. Opens crates, doors and negotiations. Hits harder on a moonshine sprint.' },
    { id: 'revolver', name: '.38 Special', key: '2', damage: 34, hit: '34', fire: .30, reload: .88, mag: 6,
      text: 'Six polite suggestions. Daddy called it the tie-breaker; it has never lost a vote.' },
    { id: 'shotgun', name: 'Sawed-Off', key: '3', damage: 120, hit: '10 × 12', fire: .55, reload: 1.10, mag: 2,
      text: 'Shortened for indoor use. Alt fire empties both barrels and most of the room. Up close it does not leave a body.' },
    { id: 'crossbow', name: 'Dynamite Crossbow', key: '4', damage: 160, hit: '160 blast', fire: 1.05, reload: 0, mag: 0,
      text: 'A truck leaf spring, a rail and a stick of dynamite where the sense should be. Opens the doors keys will not.' },
    { id: 'rifle', name: 'Ranch Rifle', key: '5', damage: 21, hit: '21', fire: .11, reload: 0, mag: 0,
      text: 'Somebody\'s uncle brought a Kalashnikov home and called it a ranch rifle. Nine rounds a second until it runs hot. Feather it.' },
    { id: 'ripsaw', name: 'Rip Saw', key: '6', damage: 54, hit: '54 blade', fire: .78, reload: 0, mag: 0,
      text: 'A two-stroke motor with a stack of blades on the arbor. Throws one that bounces three times; alt fire grinds up close for free.' },
    { id: 'armgun', name: 'Alien Arm Gun', key: '7', damage: 50, hit: '50', fire: .21, reload: 0, mag: 0,
      text: 'Not yours. Still warm, and the eye on top is still looking. The former owner is not asking for it back.' },
    { id: 'tnt', name: 'Dynamite', key: '8', damage: 160, hit: '160 blast', fire: .46, reload: 0, mag: 0,
      text: 'Hold fire to light it, let go to throw it. The fuse is 2.65 seconds whether or not you are counting.' },
    { id: 'slingblade', name: 'Sling Blade', key: '9', damage: 58, hit: '58', fire: .49, reload: 0, mag: 0,
      text: 'Some folks call it a kaiser blade. Longer reach than the crowbar and a worse attitude.' },
    { id: 'bottle_launcher', name: 'Bottle Rocket Launcher', key: '0', damage: 120, hit: '120 blast', fire: 1.15, reload: 0, mag: 0,
      text: 'A length of drain pipe hose-clamped to a two-by-four. Fourth of July, shoulder-fired; whistles so they know it is coming.' },
    { id: 'riveter', name: 'Mill Riveter', key: 'wheel', damage: 32, hit: '32', fire: .22, reload: 0, mag: 0,
      text: 'Blackwater Timber\'s pneumatic rivet gun, drum and all. Drives a hot stud through whatever is holding the wall up.' },
    { id: 'pressure_gun', name: 'Copperhead', key: 'wheel', damage: 24, hit: '24', fire: .60, reload: 0, mag: 0,
      text: 'A riveted copper boiler with a snake\'s head for a nozzle. Scalds a whole doorway and knocks the fight out of anyone in it.' },
    { id: 'bowling_ball', name: 'Bowling Ball', key: '−', damage: 108, hit: '108', fire: 1.10, reload: 0, mag: 0,
      text: 'League night at the county lanes ended early. Rolls flat, stops for nobody twice.' },
    { id: 'powder_keg', name: 'Powder Keg', key: '=', damage: 240, hit: '240 blast', fire: 1.35, reload: 0, mag: 0,
      text: 'The biggest bang in the county, lobbed underhand. Stand somewhere else.' },
    { id: 'cow_launcher', name: 'Cow Launcher', key: '\\', damage: 150, hit: '150 blast', fire: 1.55, reload: 0, mag: 0,
      text: 'A riveted stovepipe with a hide wrap and a cowbell. She moos on the way out. Nobody has asked the cow.' },
    { id: 'teat_gun', name: 'Teat Gun', key: '`', damage: 10, hit: '10', fire: .09, reload: 0, mag: 0,
      text: 'A milking machine with ideas. Fresh whole milk at eleven squirts a second, straight from the pail. Does a body bad.' },
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
    $('#bench-key').textContent = weapon.key === 'wheel' ? 'Mouse wheel' : `Key ${weapon.key}`;
    $('#bench-name').textContent = weapon.name;
    $('#bench-text').textContent = weapon.text;
    const list = $('#bench-stats');
    list.textContent = '';
    const rate = 1 / weapon.fire;
    stat(list, 'Damage', weapon.damage / TOP.damage, weapon.hit);
    stat(list, 'Rate', rate / TOP.rate, `${rate.toFixed(1)} / sec`);
    stat(list, 'Reload', weapon.reload ? 1 - weapon.reload / TOP.reload : 1,
      weapon.reload ? `${weapon.reload.toFixed(2)} s` : 'never');
    stat(list, 'Magazine', weapon.mag / TOP.mag, weapon.mag ? String(weapon.mag) : weapon.id === 'tnt' ? 'by the stick'
        : ['crowbar', 'slingblade'].includes(weapon.id) ? 'none' : 'straight from the pouch');
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
  // Objectives, districts and sign-offs are the game's own text (godot/src/campaign.gd);
  // bosses and locals follow their code (enemies.cfg, bayou_brains.gd, derby_champ.gd,
  // speedway_hands.gd, ship_aliens.gd, features/mothership.gd); the range is range_layout.gd.
  const CHAPTERS = [
    { id: 'hickston', tab: 'Hickston', order: 'Chapter one', title: 'The Hickston Incident', shot: 'shot_hickston',
      caption: 'County road, facing Stanky\'s. Evening.',
      job: 'Find the brass key to Stanky\'s back office, then the steel one, and work north through the barn and the trailer lot to the pasture where they are keeping her.',
      stops: ['County Road', 'Stanky\'s Bar & Grill', 'Restroom', 'Supply Room', 'Feed Barn', 'Hog Pen', 'Packing Shed', 'Dispatch Office', 'Trailer Lot', 'Dry Creek', 'North Pasture'],
      bosses: [
        { name: 'The Alien Sheriff', img: 'boss_sheriff', text: 'Charges a plasma shot you can hear coming. Under half health he fires three at a time and hurries.' },
        { name: 'Jerry Jones', img: 'boss_jerry', text: 'Blows a whistle, then throws a football that hurts. Three footballs once he is losing.' },
      ],
      secrets: 'Four hidden rooms. Check the mirror in the GENTS while you are in there.',
      signoff: '"Next time, take the tractor."' },
    { id: 'fair', tab: 'County Fair', order: 'Chapter two', title: 'Possum County Fair', shot: 'shot_fair',
      caption: 'Main gate. The prize pavilion is lit; nobody is selling tickets.',
      job: 'Set concession power and patch the backstage PA. The patch lead is in the raffle office, and the shooting gallery pays out if you can still aim.',
      stops: ['Ticket Shack', 'The Midway', 'Concession Alley', 'Game Court', 'Prize Pavilion', 'Service Exit', 'Freight and Raffle Lot', 'Backstage Sideshows', 'PA Booth'],
      bosses: [
        { name: 'Rudy Racket', img: 'boss_rudy', text: 'Sweeps the stage with five horn blasts. His health bar calls LEFT HORN or RIGHT HORN first. Two of him are cardboard.' },
      ],
      secrets: 'Two hidden rooms, one of them behind a sideshow panel.',
      signoff: '"No refunds after the abduction."' },
    { id: 'sawmill', tab: 'Blackwater', order: 'Chapter three', title: 'Blackwater Timber', shot: 'shot_sawmill',
      caption: 'Delivery yard, looking over the flooded log pond.',
      job: 'Isolate the west feed and trip the dry-kiln belt. The handle on the belt release is stripped, so it wants hitting rather than turning.',
      stops: ['Delivery Yard', 'Flooded Log Pond', 'West Bank', 'East Bank', 'The Cutting Shed', 'Loading Apron', 'Green Chain Sort', 'Dry Kilns', 'Rain Storage'],
      bosses: [
        { name: 'The Splinter Foreman', img: 'boss_foreman', text: 'Sends saw blades down marked lanes, three lanes and then two. When it reads GAP IN THE MIDDLE, stand in the middle.' },
      ],
      secrets: 'Four hidden rooms. The county map only draws a secret once you have found it.',
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
    { id: 'bayou', tab: 'Gator Bayou', order: 'Chapter five', title: 'Gator Bayou', shot: 'shot_bayou',
      caption: 'King\'s Lagoon at dusk. The Swamp King is out in his airboat.',
      job: 'Lower the bridges over the Big Channel: crank the boil yard generator and trip the cannery breaker. Then spike the fuel at the airboat dock, which fetches the king, and hot-wire his airboat home. The black water wades slow; the deep channels belong to the gators.',
      stops: ['County Line Landing', 'Bait & Tackle', 'Crawfish Boil', 'Stilt Row', 'Fish Camp Cabins', 'Swamp King Cannery', 'Big Channel', 'Bridge Tender\'s Hammock', 'Gator Farm', 'Wrasslin Pit', 'The Mudhole', 'King\'s Lagoon', 'Airboat Dock', 'The King\'s Still', 'Backwater'],
      locals: ['New varmints', 'Noodlers squat in the water up to the eyes and come up out of it all at once. Chum tossers sling chum the moment they see you, and every gator near comes for it. Gators lie low in the water, quick in it and slow on the bank.'],
      bosses: [
        { name: 'The Swamp King', img: 'boss_king', text: 'Circles his lagoon in an armoured airboat and fires a punt gun off the bow. A lane marked on the water means he is about to run it flat out; a run that ends on a piling or a bank beaches him, wide open. Past half health the runs come in pairs and he hollers for his gators.' },
      ],
      secrets: 'Four hidden rooms, and the king\'s own still hid behind the reeds. A taste counts.',
      signoff: '"No wake zone, my foot."' },
    { id: 'speedway', tab: 'Buzzard Bend', order: 'Chapter six', title: 'Dirt Track Speedway', shot: 'shot_speedway',
      caption: 'The front stretch on race night. Nobody told the drivers.',
      job: 'Dump the pit fuel, run the crusher and cut in on the PA. Until that fuel is dumped the cars keep running laps, and whoever is on the racing line gets run down. Then drop the green flag at the figure 8, beat the champ and take the checkered flag on the front stretch.',
      stops: ['Truck Stop', 'Lugnut\'s Diner', 'Haulers\' Lot', 'Pit Row', 'Fuel Depot', 'The Oval', 'Infield Camp', 'Figure 8', 'Grandstands', 'Announcer\'s Booth', 'The Concourse', 'Boggs Salvage', 'Crusher Yard', 'Tow Lot', 'Grandstand Parking'],
      locals: ['New varmints', 'Pit mechanics throw wrenches and tyre rollers roll tyres. Nitro huffers run in close and go up in a nitrous blast, shot down or not, and take their own side with them. Flagmen wave the green flag to call in every hand within earshot, then hang back and fire flares.'],
      bosses: [
        { name: 'Bumper Boggs', img: 'boss_boggs', text: 'The champ, in an armoured derby car. He paints his ramming lane on the ground while he revs, locks it a moment before he goes, and runs down whatever is in it. Up close he spits spare tyres down a fan of lanes. A charge into a wall stalls him: that is the opening. Fightin\' mad, he charges straight out of a crash and sheds parts.' },
      ],
      secrets: 'Three hidden rooms. Lugnut\'s walk-in is one of them.',
      signoff: '"Checkered flag. Nobody else finished."' },
    { id: 'mothership', tab: 'Mothership', order: 'Chapter seven, the last', title: 'The Mothership', shot: 'shot_mothership',
      caption: 'The specimen hold. Cows in the tubes, and a probe that has seen you.',
      job: 'Spike the shine drive and drain the cow tubes, and the core\'s iris opens on the bridge. Maw Glorb waits in the core. When she falls the ship comes apart round you all the way back to the escape outhouse in the tractor-beam bay. Ride it home and the whole campaign\'s tally comes up, then the credits.',
      stops: ['Tractor Beam Bay', 'Ring Deck', 'The Core', 'The Bridge', 'Trophy Room', 'Maw\'s Parlor', 'Crew Bunks', 'Crew Mess', 'Specimen Hold', 'Probe Lab', 'Corn Deck', 'Engine Room', 'Shine Tanks', 'Cargo Hold', 'Service Ducts'],
      locals: ['New varmints', 'Grey drones zap with a cattle prod and skitter back out of reach. Tin guards soak shots on a pickup\'s tailgate and swing it aside only to fire a bug zapper. Probes float in and reel you toward them on a beam.'],
      bosses: [
        { name: 'Maw Glorb', img: 'boss_maw', text: 'Everybody\'s maw. In her housecoat: a rolling pin on a marked circle, a hair dryer along marked lanes, and hollers to the pods for her younguns. With the housecoat on fire, stomps send a ring of cracks over the deck that has to be jumped, and the tractor beam gets loose on the floor. Out of the housecoat, all of it comes quicker.' },
      ],
      secrets: 'Four hidden rooms, and a lawn elf whose hat is worth a tug.',
      signoff: '"Tell yer maw she can keep the bus."' },
    { id: 'hub', tab: 'Crossroads', order: 'The hub', title: 'County Crossroads', shot: 'shot_hub',
      caption: 'The four-way stop. The fingerpost points down every road; the beam pad stands at the end of the one north.',
      job: 'Every finished chapter opens the next gate here. The county line road runs west and east from the four-way stop with a gate on it for each chapter, further out as the campaign goes on, and the road the county closed runs north to the crash site and the tractor-beam pad. Face a gate and press E to continue, revisit a finished chapter, or replay one from scratch with a fresh kit.',
      stops: ['Seven road gates', 'Fingerpost', 'Crossroads Diner', 'Road Department', 'Dispatch board', 'Road Crew Yard', 'County Impound', 'Crash Site', 'Beam pad'],
      bosses: [],
      secrets: 'Four road notes are pinned around the hub, and more in the chapters. The county map keeps count.',
      signoff: '"County crossroads. Face a gate and press E."' },
    { id: 'range', tab: 'Firing Range', order: 'Off the title menu', title: 'Mundell\'s Proving Grounds', shot: 'shot_range',
      caption: 'The armory. Every gun on the wall, and every one of them yours.',
      job: 'Pick FIRING RANGE on the title menu. Every gun is yours and the ammo refills itself. Walk up to a gun on the armory wall and press use to hear what it does and which lane to take it to; each lane keeps score on its own card.',
      stops: ['The Armory', 'Firing Line', 'Tin Can Alley', 'Pellet Patch', 'Rifle Range', 'Duck Gallery', 'Bowl-O-Rama', 'Soak Tank', 'Special Orders', 'Powder Pit', 'Whuppin\' Yard', 'The Bullpen', 'Boss Corral'],
      locals: ['Live targets', 'Pull a lever in the bullpen and meet the locals, one kind at a time or a whole squad: they duck behind cover, run for help when hurt and brawl if they shoot each other. The boss corral lets out the first five bosses, one at a time.'],
      bosses: [],
      secrets: 'Nothing to find and nothing saved. The range medic patches you up before you can buy the farm.',
      signoff: '"Every gun, all the ammo. Pause to leave."' },
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
    if (chapter.locals) {
      file.append(el('h4', { text: chapter.locals[0] }), el('p', { text: chapter.locals[1] }));
    }
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
    ['Main menu', [['title', 'Crazy Legs Mundell']]],
    ['Hickston', [['music', 'County Road Shuffle'], ['county_line', 'County Line at Sundown'], ['porchlight_stomp', 'Porchlight Stomp']]],
    ['The fair', [['fair_score', 'The Wheel Turns Crooked'], ['tickets_after_dark', 'Tickets After Dark'], ['closing_time_shuffle', 'Last Call at the Midway']]],
    ['Blackwater', [['mill_score', 'Rain on the Green Chain'], ['green_chain', 'Green Chain Blues'], ['apron_run', 'Across the Loading Apron']]],
    ['Stillwater', [['quarry_score', 'Limestone Stomp'], ['copper_and_steam', 'Copper and Steam'], ['last_load', 'Last Load from Stillwater']]],
    ['Gator Bayou', [['bayou_score', 'Black Water Stomp'], ['cypress_crawl', 'Cypress Knee Crawl'], ['crawdad_boil_hop', 'Crawdad Boil Hop']]],
    ['Buzzard Bend', [['music_speedway', 'Buzzard Bend Feature Race'], ['pit_row_boogie', 'Pit Row Boogie'], ['checkered_flag_rag', 'Checkered Flag Rag']]],
    ['The Mothership', [['mothership_score', 'Abducted Hoedown']]],
    ['Boss fights', [['boss_hickston', 'Sheriff\'s Last Stand'], ['boss_fair', 'Ringmaster Meltdown'], ['boss_mill', 'Head Saw Showdown'],
      ['boss_quarry', 'Boil-Over at the Still'], ['boss_bayou', 'Swamp King\'s Rampage'], ['boss_speedway', 'Bumper Boggs Wrecking Ball'],
      ['boss_mothership', 'Maw\'s Last Supper']]],
  ];
  const HOLLERS = [['yee_haw', 'Yee-haw'], ['yee_haw_alt', 'Yee-haw, again'], ['belch', 'Belch'], ['gulp', 'Beer'],
    ['moonshine', 'Moonshine'], ['shotgun_both', 'Both barrels'], ['cow_moo', 'Cow, outbound'], ['pig', 'Hog'],
    ['chicken', 'Chicken'], ['rudy_horn', 'Rudy\'s horn'], ['sheriff_siren', 'Sheriff'], ['got_bessie', 'Got Bessie'],
    ['king_holler', 'Swamp King'], ['gator_snap', 'Gator'], ['lap_car_pass', 'Race car'], ['maw_holler', 'Maw']];
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
