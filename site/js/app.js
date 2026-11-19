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
  // Numbers are the game's own (godot/data/tuning/weapons.cfg and shots.cfg):
  // damage per shot or blast and the delay between shots. Only the .38 and the
  // sawed-off reload; the rest feed straight from what you are carrying.
  const WEAPONS = [
    { id: 'crowbar', name: 'Rusted Crowbar', key: '1', damage: 44, hit: '44', fire: .33, reload: 0, mag: 0,
      text: 'Came with the truck. Opens crates, doors and negotiations. Hits harder on a moonshine sprint.' },
    { id: 'revolver', name: '.38 Special', key: '2', damage: 36, hit: '36', fire: .30, reload: .88, mag: 6,
      text: 'Six polite suggestions. Daddy called it the tie-breaker; it has never lost a vote. The junk bench will tape a pawn shop scope or a speed loader on it.' },
    { id: 'shotgun', name: 'Sawed-Off', key: '3', damage: 120, hit: '10 × 12', fire: .55, reload: 1.10, mag: 2,
      text: 'Shortened for indoor use. Alt fire empties both barrels and most of the room. Up close it does not leave a body. Takes a corn knife bayonet if you have the scrap.' },
    { id: 'crossbow', name: 'Dynamite Crossbow', key: '4', damage: 160, hit: '160 blast', fire: 1.05, reload: 0, mag: 0,
      text: 'A truck leaf spring, a rail and a stick of dynamite where the sense should be. Opens the doors keys will not.' },
    { id: 'rifle', name: 'Ranch Rifle', key: '5', damage: 21, hit: '21', fire: .11, reload: 0, mag: 0,
      text: 'Somebody\'s uncle brought a Kalashnikov home and called it a ranch rifle. Nine rounds a second until it runs hot. Feather it.' },
    { id: 'ripsaw', name: 'Rip Saw', key: '6', damage: 54, hit: '54 blade', fire: .62, reload: 0, mag: 0,
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
    { id: 'pressure_gun', name: 'Copperhead', key: 'wheel', damage: 34, hit: '34', fire: .50, reload: 0, mag: 0,
      text: 'A riveted copper boiler with a snake\'s head for a nozzle. Scalds a whole doorway and knocks the fight out of anyone in it.' },
    { id: 'bowling_ball', name: 'Bowling Ball', key: '−', damage: 108, hit: '108', fire: 1.10, reload: 0, mag: 0,
      text: 'League night at the county lanes ended early. Rolls flat, stops for nobody twice.' },
    { id: 'powder_keg', name: 'Powder Keg', key: '=', damage: 240, hit: '240 blast', fire: 1.35, reload: 0, mag: 0,
      text: 'The biggest bang in the county, lobbed underhand. Stand somewhere else.' },
    { id: 'cow_launcher', name: 'Cow Launcher', key: '\\', damage: 180, hit: '180 blast', fire: 1.55, reload: 0, mag: 0,
      text: 'A riveted stovepipe with a hide wrap and a cowbell. She moos on the way out. Nobody has asked the cow.' },
    { id: 'teat_gun', name: 'Teat Gun', key: '`', damage: 12, hit: '12', fire: .09, reload: 0, mag: 0,
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
  // speedway_hands.gd, moonshine_hands.gd, ship_aliens.gd, features/mothership.gd,
  // bosses/revenue_man.gd); the range is range_layout.gd.
  const CHAPTERS = [
    { id: 'hickston', tab: 'Hickston', order: 'Chapter one', title: 'The Hickston Incident', shot: 'shot_hickston',
      caption: 'The county road into town. Evening, and raining.',
      job: 'Find the brass key to Stanky\'s back office, then the steel one, and work north through the barn and the trailer lot to the pasture where they are keeping her.',
      stops: ['County Road', 'Stanky\'s Bar & Grill', 'Restroom', 'Supply Room', 'Feed Barn', 'Hog Pen', 'Packing Shed', 'Dispatch Office', 'Trailer Lot', 'Dry Creek', 'Rodeo Grounds', 'Hogs Field'],
      bosses: [
        { name: 'The Alien Sheriff', img: 'boss_sheriff', text: 'Holds the rodeo grounds north of the corn, his crashed saucer smoking behind him. Charges a plasma shot you can hear coming. Once he is mad he turns his back every few shots to vent the power pack, and the pack takes double from behind. Plum desperate, he calls the saucer down on you and the ring catches fire.' },
        { name: 'Jerry Jones', img: 'boss_jerry', text: 'Waits at midfield on the Hogs\' football field, behind the stock gate the sheriff kept shut. Whistles, then throws. Aim for his knees; the helmet shrugs off shots. Plum desperate, he blitzes down a marked lane, and if he hits a goalpost he is out cold for a moment.' },
      ],
      secrets: 'Four hidden rooms. Check the mirror in the GENTS while you are in there. There is a riding mower by the chapel with the keys in it.',
      signoff: '"Next time, take the tractor."' },
    { id: 'fair', tab: 'County Fair', order: 'Chapter two', title: 'Possum County Fair', shot: 'shot_fair',
      caption: 'The main gate. Nobody is selling tickets.',
      job: 'Set concession power and patch the backstage PA. The patch lead is in the raffle office, and the shooting gallery pays out if you can still aim.',
      stops: ['Ticket Shack', 'The Midway', 'Concession Alley', 'Game Court', 'Prize Pavilion', 'Service Exit', 'Freight and Raffle Lot', 'Backstage Sideshows', 'PA Booth'],
      bosses: [
        { name: 'Rudy Racket', img: 'boss_rudy', text: 'Runs his big top in the prize pavilion. Sweeps the ring with horn blasts, LEFT HORN or RIGHT HORN called on his bar, and once he is mad the PA stacks fire down their lanes too. The drum is his soft spot, the horns more so while he winds up. Plum desperate: rings of horn blasts with the gaps painted on the floor.' },
      ],
      secrets: 'Two hidden rooms, one of them behind a sideshow panel.',
      signoff: '"No refunds after the abduction."' },
    { id: 'sawmill', tab: 'Blackwater', order: 'Chapter three', title: 'Blackwater Timber', shot: 'shot_sawmill',
      caption: 'The gate at the delivery yard. The flood shift never clocked out.',
      job: 'Isolate the west feed and trip the dry-kiln belt. The handle on the belt release is stripped, so it wants hitting rather than turning.',
      stops: ['Delivery Yard', 'Flooded Log Pond', 'West Bank', 'East Bank', 'The Cutting Shed', 'Loading Apron', 'Green Chain Sort', 'Dry Kilns', 'Rain Storage'],
      bosses: [
        { name: 'The Splinter Foreman', img: 'boss_foreman', text: 'Stands across the carriage track on the saw floor. Saw blades down marked lanes, and the log carriage runs on a bell and flattens anybody on the track, him included. Hit the saw rig on his back. Plum desperate: a fan of blades that bounce off the walls.' },
      ],
      secrets: 'Four hidden rooms. The county map only draws a secret once you have found it.',
      signoff: '"Clock out. Leave the boots outside."' },
    { id: 'quarry', tab: 'Stillwater', order: 'Chapter four', title: 'Stillwater Cut', shot: 'shot_quarry',
      caption: 'The county weigh station at the limestone cut.',
      job: 'Stop the cutting feed and divert the copper condenser. The valves take cranking, and the works behind the cut is bottling something that is not spring water.',
      stops: ['County Weigh Station', 'Limestone Cut Yard', 'Cutting Shed', 'Condenser Yard', 'Bottling Works', 'Loading Court', 'Lower Cut', 'Chalk Terraces', 'Copper Recovery'],
      bosses: [
        { name: 'The Copper Baron', img: 'boss_baron', text: 'Lords it over the still house between two giant copper boilers. Steam from the floor outlets nearest where you stood, and a sweep across the room; the boiler on his back takes double. Plum desperate: copper rain on marked spots while the wall pipes burst under red lights.' },
      ],
      secrets: 'Three hidden rooms in the cut and the works.',
      signoff: '"Weight includes contents and debts."' },
    { id: 'bayou', tab: 'Gator Bayou', order: 'Chapter five', title: 'Gator Bayou', shot: 'shot_bayou',
      caption: 'Stilt Row at dusk. The locals do not care for visitors.',
      job: 'Lower the bridges over the Big Channel: crank the boil yard generator and trip the cannery breaker. Then spike the fuel at the airboat dock, which fetches the king, and hot-wire his airboat home. The black water wades slow; the deep channels belong to the gators.',
      stops: ['County Line Landing', 'Bait & Tackle', 'Crawfish Boil', 'Stilt Row', 'Fish Camp Cabins', 'Swamp King Cannery', 'Big Channel', 'Bridge Tender\'s Hammock', 'Gator Farm', 'Wrasslin Pit', 'The Mudhole', 'King\'s Lagoon', 'Airboat Dock', 'The King\'s Still', 'Backwater'],
      locals: ['New varmints', 'Noodlers squat in the water up to the eyes and come up out of it all at once. Chum tossers sling chum the moment they see you, and every gator near comes for it. Gators lie low in the water, quick in it and slow on the bank.'],
      bosses: [
        { name: 'The Swamp King', img: 'boss_king', text: 'Runs his lagoon in an armoured airboat. When the water reaches you he paints a lane and runs it flat out; when it does not, it is the punt gun. A run that ends on a bank beaches him wide open, and the engine cage takes double from behind. Plum desperate: lit dynamite onto marked spots, and his holed tank sets the water burning.' },
      ],
      secrets: 'Four hidden rooms, and the king\'s own still hid behind the reeds. A taste counts. The airboat at the dock has its keys in it: take it and the king\'s boys chase you down the CHANNEL RUN.',
      signoff: '"No wake zone, my foot."' },
    { id: 'speedway', tab: 'Buzzard Bend', order: 'Chapter six', title: 'Dirt Track Speedway', shot: 'shot_speedway',
      caption: 'The start and finish line on race night. Nobody told the drivers.',
      job: 'Dump the pit fuel, run the crusher and cut in on the PA. Until that fuel is dumped the cars keep running laps, and whoever is on the racing line gets run down. Then drop the green flag at the figure 8, beat the champ and take the checkered flag on the front stretch.',
      stops: ['Truck Stop', 'Lugnut\'s Diner', 'Haulers\' Lot', 'Pit Row', 'Fuel Depot', 'The Oval', 'Infield Camp', 'Demolition Derby', 'Grandstands', 'Announcer\'s Booth', 'The Concourse', 'Boggs Salvage', 'Crusher Yard', 'Tow Lot', 'Grandstand Parking'],
      locals: ['New varmints', 'Pit mechanics throw wrenches and tyre rollers roll tyres. Nitro huffers run in close and go up in a nitrous blast, shot down or not, and take their own side with them. Flagmen wave the green flag to call in every hand within earshot, then hang back and fire flares.'],
      bosses: [
        { name: 'Bumper Boggs', img: 'boss_boggs', text: 'Owns the derby bowl behind the flag gate. Paints his ramming lane while he revs and runs down whatever is in it; a charge into a wall stalls him, and the radiator up front is the soft spot. Plum desperate: nitro rams off the walls while the floodlights blow one by one.' },
      ],
      secrets: 'Three hidden rooms. Lugnut\'s walk-in is one of them. The stock car on pit row has its keys in it, and the Boggs boys will race you three laps in the HEAT RACE.',
      signoff: '"Checkered flag. Nobody else finished."' },
    { id: 'moonshine', tab: 'Copperhead Ridge', order: 'Chapter seven', title: 'The Moonshine Run', shot: 'shot_moonshine',
      caption: 'The county line checkpoint by night. The revenue men parked a cruiser across the road.',
      job: 'Load Granny\'s shine, cut the revenue radio and ring the church bell. The trunk is in Granny Hooten\'s tobacco barn, the radio on Buzzard Knob keeps the cruisers circling the blacktop until you shut it up, and Little Bethel\'s bell opens the log gate. Then run the load: the stock car out of the barn, over the low water bridge, round the church curve and through the checkpoint in forty-five seconds, roadblocks and all. Granny\'s dinner iron by the still cave calls out the man who has been waiting for her.',
      stops: ['Granny Hooten\'s Place', 'The Tobacco Barn', 'Mule Creek', 'Low Water Bridge', 'Little Bethel Church', 'Bethel Graveyard', 'The Backroad', 'County Blacktop', 'Buzzard Knob', 'Deer Camp', 'Snake Holler', 'County Line Checkpoint', 'The Switchbacks', 'Revenue Camp', 'The Still Cave'],
      locals: ['New varmints', 'The revenooers: agents with snub .38s who, while the radio on Buzzard Knob still talks, call in every hand within earshot instead of shooting. Still busters come in swinging, gas men lob tear gas, and the cruisers run down whatever stands on the blacktop. It is night up here; keep a flashlight handy.'],
      bosses: [
        { name: 'The Revenue Man', img: 'boss_revenue_man', text: 'Waits in the still cave with his dynamite wired to Granny\'s copper still. A fanned tommy-gun burst, an axe charge that sticks in the rock and leaves him stuck and open, and tear gas lobbed round you. His mirrored shades are the soft spot, so you have to face the gun. Plum desperate: the still blows, the spilled shine burns and the roof comes down a rock at a time, on him too.' },
      ],
      secrets: 'Three stashes: the smokehouse, the pulpit and the sinkhole. The brass key in Skeeter\'s trailer opens the barn\'s tack room.',
      signoff: '"Granny says the tax is paid in full."' },
    { id: 'mothership', tab: 'Mothership', order: 'Chapter eight, the last', title: 'The Mothership', shot: 'shot_mothership',
      caption: 'The tractor-beam bay. Somebody\'s pickup is on its way up, and a grey has seen you.',
      job: 'Spike the shine drive and drain the cow tubes, and the core\'s iris opens on the bridge. Maw Glorb waits in the core. When she falls the ship comes apart round you all the way back to the escape outhouse in the tractor-beam bay. Ride it home and the whole campaign\'s tally comes up, then the credits.',
      stops: ['Tractor Beam Bay', 'Ring Deck', 'The Core', 'The Bridge', 'Trophy Room', 'Maw\'s Parlor', 'Crew Bunks', 'Crew Mess', 'Specimen Hold', 'Probe Lab', 'Corn Deck', 'Engine Room', 'Shine Tanks', 'Cargo Hold', 'Service Ducts'],
      locals: ['New varmints', 'Grey drones zap with a cattle prod and skitter back out of reach. Tin guards soak shots on a pickup\'s tailgate and swing it aside only to fire a bug zapper. Probes float in and reel you toward them on a beam.'],
      bosses: [
        { name: 'Maw Glorb', img: 'boss_maw', text: 'Everybody\'s maw, on her throne in the core. A rolling pin on a marked circle, a hair dryer down marked lanes and hollers to the pods for her younguns; the curlers on top of her head are the soft spot. Housecoat on fire, then out of it: hot curlers drop on marked spots and the core goes critical. Jump the pulses.' },
      ],
      secrets: 'Four hidden rooms, and a lawn elf whose hat is worth a tug.',
      signoff: '"Tell yer maw she can keep the bus."' },
    { id: 'hub', tab: 'Crossroads', order: 'The hub', title: 'County Crossroads', shot: 'shot_hub',
      caption: 'The four-way stop, under the Hickston water tower.',
      job: 'Every finished chapter opens the next gate here. The county line road runs west and east from the four-way stop with a gate on it for each chapter, further out as the campaign goes on, and the road the county closed runs north to the crash site and the tractor-beam pad. Face a gate and press USE to continue, revisit a finished chapter, or replay one from scratch with a fresh kit. Mundell\'s junk bench stands in the Road Department\'s yard, and his trophy shack fills up with every boss you beat.',
      stops: ['Eight road gates', 'Junk bench', 'Trophy shack', 'Fingerpost', 'Crossroads Diner', 'Road Department', 'Dispatch board', 'Road Crew Yard', 'County Impound', 'Crash Site', 'Beam pad'],
      bosses: [],
      secrets: 'Four road notes are pinned around the hub, and more in the chapters. The county map keeps count.',
      signoff: '"County crossroads. Face a gate and press E."' },
    { id: 'range', tab: 'Firing Range', order: 'Off the title menu', title: 'Mundell\'s Proving Grounds', shot: 'shot_range',
      caption: 'The armory. Every gun on the wall, and the board says how to use them.',
      job: 'Pick FIRING RANGE on the title menu. Every gun is yours and the ammo refills itself. Walk up to a gun on the armory wall and press use to hear what it does and which lane to take it to; each lane keeps score on its own card.',
      stops: ['The Armory', 'Firing Line', 'Tin Can Alley', 'Pellet Patch', 'Rifle Range', 'Duck Gallery', 'Bowl-O-Rama', 'Soak Tank', 'Special Orders', 'Powder Pit', 'Whuppin\' Yard', 'The Bullpen', 'Boss Corral'],
      locals: ['Live targets', 'Pull a lever in the bullpen and meet the locals, one kind at a time or a whole squad: they duck behind cover, run for help when hurt and brawl if they shoot each other. The boss corral lets the bosses out one at a time. Down the games row: horseshoes, a dunk tank, skee-ball and knock \'em down.'],
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

  // The fight card (index.html #fightcard): each boss in its arena, from the
  // boss files (src/bosses/*.gd, features/boss_arena.gd, boss_arenas.gd).
  const FIGHTS = [
    { name: 'The Alien Sheriff', where: 'Rodeo grounds, Hickston', img: 'fight_sheriff', soft: 'The power pack on his back.', desperate: 'Calls the saucer down: rings close, bolts drop, the ring burns.', hog: 'A ring of plasma in every direction, with one gap.' },
    { name: 'Jerry Jones', where: 'Hogs Field, Hickston', img: 'fight_jerry', soft: 'His knees. Not the helmet.', desperate: 'A blitz down a marked lane. Make him hit a post.', hog: 'A flaming football that bursts where it lands.' },
    { name: 'Rudy Racket', where: 'The big top, Possum County Fair', img: 'fight_rudy', soft: 'The drum; the horns while he winds up.', desperate: 'Rings of horn blasts. Find the painted gaps.', hog: 'Balloon bombs that drift after you. Shoot them down.' },
    { name: 'The Splinter Foreman', where: 'The saw floor, Blackwater Timber', img: 'fight_foreman', soft: 'The saw rig on his back.', desperate: 'A fan of saw blades that bounce off the walls.', hog: 'Kicks a fuel drum at you. Shoot it first.' },
    { name: 'The Copper Baron', where: 'The still house, Stillwater Cut', img: 'fight_baron', soft: 'The boiler on his back.', desperate: 'Copper rain on marked spots, burst pipes, red lights.', hog: 'Every third attack, every outlet in the house goes.' },
    { name: 'The Swamp King', where: 'King\'s Lagoon, Gator Bayou', img: 'fight_king', soft: 'The engine cage, from behind.', desperate: 'Lit dynamite on marked spots; the water burns.', hog: 'A punt-gun broadside at the end of every run.' },
    { name: 'Bumper Boggs', where: 'The derby bowl, Buzzard Bend', img: 'fight_boggs', soft: 'The radiator, up front and low.', desperate: 'Nitro rams off the walls as the floodlights blow.', hog: 'Burning oil down every charge lane.' },
    { name: 'The Revenue Man', where: 'The still cave, Copperhead Ridge', img: 'fight_revenue', soft: 'His mirrored shades. Face the gun.', desperate: 'The still blows, the shine burns, the roof comes down.', hog: 'Three cans of tear gas, not two.' },
    { name: 'Maw Glorb', where: 'The throne in the core, the Mothership', img: 'fight_maw', soft: 'The curlers on top of her head.', desperate: 'Hot curlers and a core gone critical. Jump.', hog: 'The rolling pin comes down twice.' },
  ];
  const card = $('#fight-cards');
  if (card) {
    FIGHTS.forEach((fight) => {
      card.append(el('article', { class: 'bout' },
        el('p', { class: 'bout-bill', text: 'Tonight' }),
        el('img', { src: `img/${fight.img}.png`, alt: `${fight.name} in ${fight.where}`, loading: 'lazy' }),
        el('h3', { text: fight.name }),
        el('p', { class: 'bout-where', text: fight.where }),
        el('dl', {},
          el('dt', { text: 'Soft spot' }), el('dd', { text: fight.soft }),
          el('dt', { text: 'Plum desperate' }), el('dd', { text: fight.desperate }),
          el('dt', { text: 'HOG WILD' }), el('dd', { text: fight.hog }))));
    });
  }

  // The party line (index.html #partyline): the modes as docs/online.md and
  // docs/dev/modes.md have them.
  const MODES = [
    { name: 'Campaign co-op', bill: 'Two to four', img: 'feature_coop', alt: 'A co-op partner beside Mundell and Blue on the road into Hickston',
      rows: [['The deal', 'The whole campaign together, from a chapter the host has reached or THE PARTY SAVE.'],
        ['Shared', 'Keys and the PA lead. Everybody keeps his own guns, pockets and hound.'],
        ['Down', 'A partner holds USE over you, or you are back beside them in twenty seconds.']] },
    { name: 'Deathmatch', bill: 'Two to four', img: 'feature_deathmatch', alt: 'Team deathmatch: red and blue players in Mundell\'s Proving Grounds',
      rows: [['The deal', 'Every man for himself, or TEAM DEATHMATCH, red against blue.'],
        ['Where', 'The boss arenas, the Crossroads, the range, the versus maps or your own.'],
        ['Ends', 'At the frag limit or the time limit, then back to the lobby.']] },
    { name: '5v5 and tag team', bill: 'Up to ten', img: 'feature_fivev5', alt: 'A 5v5 round on the holler: the shine bomb just planted on B, the outlaws holding it, the team radio and the kill feed up top',
      rows: [['The deal', 'Outlaws against deputies: SEARCH AND DESTROY with a shine bomb, or HOSTAGE RESCUE. Bots fill the empty places, and the dead talk only to the dead.'],
        ['The store', 'Ten side guns, a vest and four throwables, bought between rounds. RULES can make it shotguns only, a pistol party or big money.'],
        ['TAG TEAM 2V2', 'Two a side on three small maps, first to nine. PLAY VS BOTS runs any of it offline.']] },
    { name: 'County Run co-op', bill: 'Two to four', img: 'feature_county', alt: 'County Run\'s level-up cards: an upgrade, a new gun and a perk',
      rows: [['The deal', 'The endless survival mode with a posse: one build and one pile of XP for the lot of you.'],
        ['Cards', 'The first one up picks; everybody sees who is picking, and the game runs on smooth around it.'],
        ['Over', 'When the last of you is down. Then back to the lobby for another.']] },
  ];
  const modes = $('#modes');
  if (modes) {
    MODES.forEach((mode) => {
      const list = el('dl');
      mode.rows.forEach(([term, text]) => list.append(el('dt', { text: term }), el('dd', { text })));
      modes.append(el('article', { class: 'bout' },
        el('p', { class: 'bout-bill', text: mode.bill }),
        el('img', { src: `img/${mode.img}.png`, alt: mode.alt, loading: 'lazy', width: '640', height: '480' }),
        el('h3', { text: mode.name }), list));
    });
  }

  // The feed store wall (index.html #bill): flyers for the bigger pieces.
  const FLYERS = [
    { title: 'County Run', img: 'feature_county_xp', alt: 'County Run on the Hickston map: bottle-cap XP lying beside a barn, the run clock, level and slots on the bar',
      text: 'Endless survival on three big maps: Hickston, the quarry and Gator Bayou. Kills drop bottle-cap XP; every level stops the clock for three cards, every tenth for a big milestone, while a storm front closes in. DAILY RUN gives everybody the same dice and keeps a board. Alone, or online with three friends.' },
    { title: 'Behind the wheel', img: 'feature_vehicle', alt: 'The stock car in the HEAT RACE, forty-three miles an hour, the .38 out of the window',
      text: 'Three rides with the keys in them: the Swamp King\'s airboat, a stock car and a riding mower. Run the bayou\'s CHANNEL RUN, three laps of the HEAT RACE at Buzzard Bend, or Granny\'s load down the Moonshine blacktop. A partner rides along and shoots, and a one-handed gun comes out the car\'s window.' },
    { title: 'Blue', img: 'feature_blue', alt: 'Blue the bluetick coonhound trotting past the gate of the Possum County Fairgrounds, his badge at lower left',
      text: 'Mundell\'s bluetick coonhound, built new from nose to tail, comes along on every chapter. He trots at your heel or ranges out ahead like a hunting dog, keeps out of your sights, hops in when you drive, bays at secret doors and new guns, points at loot, pins a hurt man down, fetches, and minds the whistle: G, BACK held on a pad, or WHISTLE on a phone. His badge says how he feels and what he\'s up to. Every co-op player gets a dog of his own.' },
    { title: 'Twister weather', img: 'feature_twister', alt: 'A twister touching down beyond the trees outside Hickston',
      text: 'Some runs through a chapter get something nobody planned. The civil defence siren and a twister that flings whatever is loose and tears down barns; a hog stampede; a revenue raid that comes in shooting at everybody, the county\'s hands included.' },
    { title: 'Lights out', img: 'feature_blackout', alt: 'A flashlight beam on the main breaker in a blackout',
      text: 'In the night chapters the power can die in stutters. Every player has a flashlight on L, with a battery that runs down, some hands carry lanterns, and the main breaker is out there somewhere if you can find it.' },
    { title: 'The big breaks', img: 'feature_destruction', alt: 'A water tower going over in the rain, its tank bursting',
      text: 'Shoot the legs out from under a water tower and it topples, bursts and floods the yard. Barns and sheds come down, fuel lines burn and the bosses wreck their own arenas: more in the wrecking yard below.' },
    { title: 'Coming attractions', img: 'feature_opener', alt: 'The Revenue Man in silhouette between a red and a blue police light',
      text: 'Every chapter opens on a short cutscene the way they did in 1997: the camera gliding over the county to the chapter\'s own song, a painted title card, the boss in silhouette and an old storyteller with two lines. FIRST TIME, ALWAYS or OFF; any key skips it.' },
    { title: 'Greenhorns welcome', img: 'feature_tips', alt: 'The first hand coming at the gas station, a chalk-green tip at the top: left click shoots, R reloads, right click is the gun\'s other fire',
      text: 'New to the county? The first time something comes up, a hand drawing on you, a locked door, a reeling man in reach, loose junk, the junk bench or Blue, a short tip says what to do with your own keys, pad or thumbs. Each shows once. NEW PLAYER TIPS on SETUP\'s PLAY page turns them off.' },
  ];
  const flyers = $('#flyers');
  if (flyers) {
    FLYERS.forEach((flyer) => {
      flyers.append(el('article', { class: 'handbill' },
        el('img', { src: `img/${flyer.img}.png`, alt: flyer.alt, loading: 'lazy', width: '640', height: '480' }),
        el('h3', { text: flyer.title }), el('p', { text: flyer.text })));
    });
  }

  // The wrecking yard (index.html #wreckage): what 3.9 did to breaking things.
  const WRECKS = [
    { title: 'Shot apart', img: 'feature_break', alt: 'A barrel blown apart by the sawed-off in Hickston\'s yard, its staves in the air and its stump still standing',
      text: 'Crates, barrels, coolers, mash tubs and mailboxes come apart where the round lands and the way it pushed, and the pieces tumble by what they are made of: wood, tin, glass or straw. Plank walls lose the boards you shoot, windows crack fresh and every round leaves its own hole.' },
    { title: 'Barn raising, backwards', img: 'feature_barn', alt: 'An orchard shed coming down behind a scarecrow, its roof sliding off and dust coming up',
      text: 'Shoot out a barn\'s posts and it comes down in its own boards, beams and tin, in a cloud of dust, onto whatever was under it. Hay sheds and lumber sheds too.' },
    { title: 'What blew', img: 'feature_blast', alt: 'A powder keg going up in Hickston\'s yard, the fireball rolling up round its smoke column',
      text: 'A blast looks like what went up: a stick of dynamite, a powder keg, a fuel drum, a gas can, the propane, a cow. The fireball rolls up through its own smoke and leaves a column standing over the yard.' },
    { title: 'Totaled', img: 'feature_wreck', alt: 'The stock car blown up by a stick of dynamite, a body panel flying off through the fire',
      text: 'Blow up the stock car, the airboat or the mower and it throws its panels and parts across the lot, then sits there burning.' },
    { title: 'Down they go', img: 'feature_ragdoll', alt: 'A coot thrown backwards off his feet by buckshot in front of the gas pumps',
      text: 'Hands go down the way they were hit: buckshot from the side throws a man off his feet, the knees fold the way knees do and the body goes slack. Billy, the millhands and the tin guards fall right again.' },
    { title: 'Gator in the air', img: 'feature_gator', alt: 'A gator thrown up off the road by a stick of dynamite, tail and jaws flung wide, outside Hickston',
      text: 'New in 3.11: gators, crawlers, the stampede\'s hogs and the cows die as bodies too, knees folding their own way, landing on the belly, the side or the back, and a dead gator floats. The sheriff, Jerry, Rudy, the foreman and the Revenue Man finish their falls the same way.' },
  ];
  const wrecksBoard = $('#wrecks');
  if (wrecksBoard) {
    WRECKS.forEach((wreck) => {
      wrecksBoard.append(el('article', { class: 'handbill' },
        el('img', { src: `img/${wreck.img}.png`, alt: wreck.alt, loading: 'lazy', width: '640', height: '480' }),
        el('h3', { text: wreck.title }), el('p', { text: wreck.text })));
    });
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
    ['Copperhead Ridge', [['moonshine_score', 'Copperhead Ridge Run'], ['fight_moonshine', 'Revenuer Roadblock Brawl']]],
    ['The Mothership', [['mothership_score', 'Abducted Hoedown']]],
    ['Boss fights', [['boss_hickston', 'Sheriff\'s Last Stand'], ['boss_fair', 'Ringmaster Meltdown'], ['boss_mill', 'Head Saw Showdown'],
      ['boss_quarry', 'Boil-Over at the Still'], ['boss_bayou', 'Swamp King\'s Rampage'], ['boss_speedway', 'Bumper Boggs Wrecking Ball'],
      ['boss_moonshine', 'The Revenue Man Cometh'], ['boss_mothership', 'Maw\'s Last Supper']]],
  ];
  const HOLLERS = [['yee_haw', 'Yee-haw'], ['yee_haw_alt', 'Yee-haw, again'], ['belch', 'Belch'], ['gulp', 'Beer'],
    ['moonshine', 'Moonshine'], ['shotgun_both', 'Both barrels'], ['cow_moo', 'Cow, outbound'], ['pig', 'Hog'],
    ['chicken', 'Chicken'], ['rudy_horn', 'Rudy\'s horn'], ['sheriff_siren', 'Sheriff'], ['got_bessie', 'Got Bessie'],
    ['king_holler', 'Swamp King'], ['gator_snap', 'Gator'], ['lap_car_pass', 'Race car'], ['maw_holler', 'Maw'],
    ['boss_sheriff_intro', 'Sheriff talks'], ['boss_jerry_taunt_1', 'Jerry talks'], ['boss_rudy_intro', 'Rudy talks'],
    ['boss_foreman_intro', 'Foreman talks'], ['boss_baron_intro', 'Baron talks'], ['boss_swamp_king_intro', 'King talks'],
    ['boss_boggs_taunt_0', 'Boggs talks'], ['boss_revenue_man_taunt_0', 'Revenue Man'], ['boss_maw_worried', 'Maw frets'],
    ['hound_bay', 'Blue bays'], ['hound_whistle', 'Whistle for Blue'], ['dj_id_0', 'KPSM'],
    ['tornado_siren', 'Twister siren'], ['raid_siren', 'Revenue raid']];
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
