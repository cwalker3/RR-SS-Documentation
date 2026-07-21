"use strict";
/* ---- multi-game registry: each game's data file self-registers into window.RRSS_GAMES ---- */
const GAMES = window.RRSS_GAMES || (window.RRSS_DATA ? {rrss:{id:'rrss',name:'Rising Ruby / Sinking Sapphire',short:'RR/SS',data:window.RRSS_DATA}} : {});
let GAME_ID = (function(){
  try{const u=new URLSearchParams(location.search).get('game');if(u&&GAMES[u])return u;}catch(e){}
  try{const g=localStorage.getItem('rrss-game');if(g&&GAMES[g])return g;}catch(e){}
  return Object.keys(GAMES)[0];
})();
const GAME = GAMES[GAME_ID];
const RAW = GAME.data;
const GEN = (GAME && GAME.gen) || 6;   // base-game generation (drives gen-specific mechanics text)
const SPR = window.RRSS_SPR || {};
/* ---- attempts: each is its own independent run/tracking, per game ---- */
const attemptsKey = 'rrss-'+GAME_ID+'-attempts';
let ATTEMPTS=[];try{ATTEMPTS=JSON.parse(localStorage.getItem(attemptsKey)||'[]');}catch(e){}
if(!Array.isArray(ATTEMPTS)||!ATTEMPTS.length){ATTEMPTS=[{id:'a1',name:'Attempt 1'}];try{localStorage.setItem(attemptsKey,JSON.stringify(ATTEMPTS));}catch(e){}}
let ATTEMPT_ID=(function(){try{const a=localStorage.getItem('rrss-'+GAME_ID+'-attempt');if(a&&ATTEMPTS.some(x=>x.id===a))return a;}catch(e){}return ATTEMPTS[0].id;})();
function saveAttempts(){try{localStorage.setItem(attemptsKey,JSON.stringify(ATTEMPTS));}catch(e){}}
// 'a1' keeps the un-suffixed (legacy) keys so existing progress is preserved
const gkey = k => 'rrss-'+GAME_ID+(ATTEMPT_ID==='a1'?'':'-'+ATTEMPT_ID)+'-'+k;
function switchAttempt(id){try{localStorage.setItem('rrss-'+GAME_ID+'-attempt',id);}catch(e){}location.reload();}
function newAttempt(){
  const name=(prompt('Name this attempt:', 'Attempt '+(ATTEMPTS.length+1))||'').trim()||('Attempt '+(ATTEMPTS.length+1));
  const id='a'+Date.now();ATTEMPTS.push({id,name});saveAttempts();switchAttempt(id);
}
function renameAttempt(){
  const cur=ATTEMPTS.find(a=>a.id===ATTEMPT_ID);if(!cur)return;
  const name=(prompt('Rename attempt:', cur.name)||'').trim();if(name){cur.name=name;saveAttempts();reRenderKeepScroll();}
}
function deleteAttempt(){
  if(ATTEMPTS.length<2)return;
  const cur=ATTEMPTS.find(a=>a.id===ATTEMPT_ID);
  if(!confirm('Delete "'+(cur?cur.name:'this attempt')+'" and all its tracking? This cannot be undone.'))return;
  ['caught','trainers','missed','items','profile'].forEach(k=>{try{localStorage.removeItem(gkey(k));}catch(e){}});
  ATTEMPTS=ATTEMPTS.filter(a=>a.id!==ATTEMPT_ID);saveAttempts();switchAttempt(ATTEMPTS[0].id);
}
// one-time migration of pre-multi-game progress into the rrss namespace
(function migrateLegacy(){ if(GAME_ID!=='rrss')return;
  [['caught','rrss-caught'],['trainers','rrss-trainers'],['missed','rrss-missed'],['profile','rrss-profile']].forEach(([k,old])=>{
    try{ if(localStorage.getItem(gkey(k))==null){ const v=localStorage.getItem(old); if(v!=null)localStorage.setItem(gkey(k),v); } }catch(e){}
  });
})();
function spriteImg(dex,size,cls){const b=SPR[String(parseInt(dex,10))];if(!b)return '';return `<img class="spr ${cls||''}" width="${size}" height="${size}" src="data:image/png;base64,${b}" alt="" loading="lazy">`;}
const ITEMSPR=window.RRSS_ITEMSPR||{};
function itemSpriteImg(name){
  if(!name)return '';
  let b;
  if(/^TM\d/i.test(name))b=ITEMSPR._tm;else if(/^HM\d/i.test(name))b=ITEMSPR._hm;else b=ITEMSPR[normName(name)];
  if(!b)return '';
  return `<img class="itemspr" width="22" height="22" src="data:image/png;base64,${b}" alt="" loading="lazy">`;
}
const NAME2DEX={};
function normName(s){return String(s==null?'':s).toLowerCase().replace(/[^a-z0-9]/g,'');}
function spriteByName(name,size,cls){const d=NAME2DEX[normName(name)];return d?spriteImg(d,size,cls):'';}
function isMon(name){return !!NAME2DEX[normName(name)];}
function monAttr(name){return isMon(name)?` data-mon="${esc(name)}" role="button" tabindex="0" title="View ${esc(name)}"`:'';}

/* ---- caught tracking (global, by national dex) ---- */
let CAUGHT=new Set();
try{CAUGHT=new Set(JSON.parse(localStorage.getItem(gkey('caught'))||'[]'));}catch(e){}
function saveCaught(){try{localStorage.setItem(gkey('caught'),JSON.stringify([...CAUGHT]));}catch(e){}}
function isCaught(name){const d=NAME2DEX[normName(name)];return d?CAUGHT.has(d):false;}
function toggleCaught(name){const d=NAME2DEX[normName(name)];if(!d)return;if(CAUGHT.has(d))CAUGHT.delete(d);else CAUGHT.add(d);saveCaught();}
// trainers marked complete (by trainer id) + areas with a missed/killed encounter
let TRAINERS_DONE=new Set();try{TRAINERS_DONE=new Set(JSON.parse(localStorage.getItem(gkey('trainers'))||'[]'));}catch(e){}
function saveTrainers(){try{localStorage.setItem(gkey('trainers'),JSON.stringify([...TRAINERS_DONE]));}catch(e){}}
function toggleTrainer(id){if(TRAINERS_DONE.has(id))TRAINERS_DONE.delete(id);else TRAINERS_DONE.add(id);saveTrainers();}
let AREA_MISSED=new Set();try{AREA_MISSED=new Set(JSON.parse(localStorage.getItem(gkey('missed'))||'[]'));}catch(e){}
function saveMissed(){try{localStorage.setItem(gkey('missed'),JSON.stringify([...AREA_MISSED]));}catch(e){}}
function toggleMissed(name){if(AREA_MISSED.has(name))AREA_MISSED.delete(name);else AREA_MISSED.add(name);saveMissed();}
// items picked up (by per-area item id)
let ITEMS_DONE=new Set();try{ITEMS_DONE=new Set(JSON.parse(localStorage.getItem(gkey('items'))||'[]'));}catch(e){}
function saveItems(){try{localStorage.setItem(gkey('items'),JSON.stringify([...ITEMS_DONE]));}catch(e){}}
function toggleItem(id){if(ITEMS_DONE.has(id))ITEMS_DONE.delete(id);else ITEMS_DONE.add(id);saveItems();}
// gym badges are earned automatically when a gym's leader is beaten (see GYMS/gymLeaderIds below)
function trackTotal(){return CAUGHT.size+TRAINERS_DONE.size+AREA_MISSED.size+ITEMS_DONE.size;}
function resetCaught(){
  if(!trackTotal())return;
  if(!confirm('Reset all run progress? This clears every caught Pokémon, missed encounter, completed trainer, and picked-up item.'))return;
  CAUGHT.clear();TRAINERS_DONE.clear();AREA_MISSED.clear();ITEMS_DONE.clear();saveCaught();saveTrainers();saveMissed();saveItems();
  Object.keys(wildOpen).forEach(k=>delete wildOpen[k]);
  reRenderKeepScroll();
}

/* ---- encounter % for land methods (doc: ~10% each, 5% for asterisked) ---- */
const LAND_METHODS=new Set(['Grass','Tall Grass','Walking','Sand','Cave','Long Grass']);
function encPcts(list){
  const rare=list.filter(s=>s.rare).length, non=list.length-rare;
  const each = non>0 ? (100-5*rare)/non : (list.length?100/list.length:0);
  return list.map(s=> s.rare?5:each);
}
function fmtPct(p){return (Math.round(p*10)/10).toString().replace(/\.0$/,'')+'%';}

/* ---- player profile: gender + starter -> which Brendan/May rival fight ---- */
let PROFILE={gender:null,starter:null};
try{const p=JSON.parse(localStorage.getItem(gkey('profile'))||'{}');PROFILE.gender=p.gender||null;PROFILE.starter=p.starter||null;}catch(e){}
function saveProfile(){try{localStorage.setItem(gkey('profile'),JSON.stringify(PROFILE));}catch(e){}}
const RIVAL_COUNTER={Treecko:'Torchic',Torchic:'Mudkip',Mudkip:'Treecko'};
function rivalGenderOf(name){if(/\bBrendan\b/.test(name))return 'Brendan';if(/\bMay\b/.test(name))return 'May';return null;}
function rivalStarterOf(team){const s=team.map(m=>m.species).join(' ');
  if(/Treecko|Grovyle|Sceptile/.test(s))return 'Treecko';
  if(/Torchic|Combusken|Blaziken/.test(s))return 'Torchic';
  if(/Mudkip|Marshtomp|Swampert/.test(s))return 'Mudkip';return null;}
function isRivalTrainer(t){return !!(rivalGenderOf(t.name)&&rivalStarterOf(t.team));}
function rivalName(){return PROFILE.gender?(PROFILE.gender==='Brendan'?'May':'Brendan'):null;}
function rivalStarter(){return PROFILE.starter?RIVAL_COUNTER[PROFILE.starter]:null;}
const arr = v => Array.isArray(v) ? v : (v==null ? [] : [v]);
const normRows = r => { r = arr(r); if(r.length && !Array.isArray(r[0])) r=[r]; return r.map(x=>arr(x)); };
const esc = s => String(s==null?'':s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const el = (t,c,h)=>{const e=document.createElement(t);if(c)e.className=c;if(h!=null)e.innerHTML=h;return e;};

/* ---- asterisk badge helper ---- */
function starOf(str){ const m=/(\*+)\s*$/.exec(str||''); return m?m[1].length:0; }
function stripStar(str){ return String(str||'').replace(/\s*\*+\s*$/,'').trim(); }
function starBadge(n){ if(!n) return ''; return ` <sup class="ast a${n}" title="${n===2?'Hack-only — not obtainable in the base game':'Learnable, but not by level-up (egg / TM / tutor)'}">${n===2?'**':'*'}</sup>`; }

/* ---- method color mapping ---- */
function methodTag(m){
  const s=m.toLowerCase(); let c='var(--m-other)';
  if(s.includes('grass'))c='var(--m-grass)';
  else if(s.includes('surf')||s.includes('water')||s.includes('dive'))c='var(--m-surf)';
  else if(s.includes('rod')||s.includes('fish'))c='var(--m-rod)';
  else if(s.includes('horde'))c='var(--m-horde)';
  else if(s.includes('dexnav'))c='var(--m-dex)';
  else if(s.includes('smash')||s.includes('rock'))c='var(--m-static)';
  return `<span class="mtag" style="background:${c}">${esc(m)}</span>`;
}

/* ================= SECTIONS ================= */
const ICONS={
  pokemon:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><circle cx="12" cy="12" r="9"/><path d="M3 12h5.5a3.5 3.5 0 0 0 7 0H21"/><circle cx="12" cy="12" r="2.3" fill="currentColor" stroke="none"/></svg>',
  areas:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M12 21s7-5.4 7-11a7 7 0 1 0-14 0c0 5.6 7 11 7 11Z"/><circle cx="12" cy="10" r="2.4"/></svg>',
  moves:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M13 2 4 14h6l-1 8 9-12h-6l1-8Z"/></svg>',
  evolution:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M4 7h11l-3-3M4 7l3 3M20 17H9l3 3M20 17l-3-3"/></svg>',
  items:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M6 8h12l-1 12H7L6 8Z"/><path d="M9 8V6a3 3 0 0 1 6 0v2"/></svg>',
  gifts:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M4 11h16v9H4z"/><path d="M4 8h16v3H4zM12 8v12M12 8S9.5 3.5 7.5 5.5 12 8 12 8ZM12 8s2.5-4.5 4.5-2.5S12 8 12 8Z"/></svg>',
  thief:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M6 11V8a6 6 0 0 1 12 0v3"/><path d="M5 11h14l-1 9H6l-1-9Z"/><circle cx="12" cy="15.5" r="1.4"/></svg>',
  box:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M3 8l9-5 9 5v8l-9 5-9-5V8Z"/><path d="M3 8l9 5 9-5M12 13v8"/></svg>',
  sun:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M19.1 4.9l-1.4 1.4M6.3 17.7l-1.4 1.4"/></svg>'
};
const ALL_SECTIONS=[
  {id:'pokemon',label:'Pokémon',sub:''},
  {id:'areas',label:'Areas',sub:''},
  {id:'moves',label:'Moves',sub:''},
  {id:'evolution',label:'Evolutions',sub:''},
  {id:'items',label:'Items & Shops',sub:''},
  {id:'gifts',label:'Gifts & Statics',sub:''},
  {id:'thief',label:'Thief Items',sub:''},
  {id:'box',label:'Your Box',sub:'caught Pokémon'},
];
// a game may ship only some sections (e.g. a Pokédex-only game) — show only populated ones
function sectionHasData(id){switch(id){
  case 'pokemon': case 'box': return arr(RAW.pokemon&&RAW.pokemon.entries).length>0;
  case 'areas': return arr(RAW.areas&&RAW.areas.areas).length>0;
  case 'moves': return Object.keys(RAW.moveInfo||{}).length>0||arr(RAW.attacks&&RAW.attacks.entries).length>0;
  case 'evolution': return arr(RAW.evolution&&RAW.evolution.blocks).length>0;
  case 'items': return arr(RAW.items&&RAW.items.blocks).length>0;
  case 'gifts': return arr(RAW.gifts&&RAW.gifts.blocks).length>0;
  case 'thief': return arr(RAW.thief&&RAW.thief.stages).length>0;
  default: return true;
}}
const SECTIONS=ALL_SECTIONS.filter(s=>sectionHasData(s.id));
SECTIONS.forEach(s=>{
  if(s.id==='pokemon')s.sub=arr(RAW.pokemon.entries).length+' species';
  if(s.id==='areas')s.sub=arr(RAW.areas.areas).length+' locations';
  if(s.id==='moves')s.sub=Object.keys(RAW.moveInfo||{}).length+' moves · '+arr(RAW.attacks&&RAW.attacks.entries).length+' changed';
});

const state={section:(SECTIONS.find(s=>s.id==='areas')||SECTIONS[0]||{id:'pokemon'}).id,query:'',pkSel:0,areaSel:0,areaInit:false};
const $=id=>document.getElementById(id);

/* ---- build nav ---- */
const nav=$('nav');
SECTIONS.forEach(s=>{
  const b=el('button','navbtn');b.dataset.id=s.id;
  b.innerHTML=`${ICONS[s.id]}<span class="nm">${esc(s.label)}<small>${esc(s.sub)}</small></span>`;
  b.onclick=()=>{go(s.id);closeMenu();};
  nav.appendChild(b);
});

/* ---- brand + game picker (multi-game) ---- */
(function setupGames(){
  const brand=document.querySelector('.brand h1');
  if(brand)brand.innerHTML=esc(GAME.name).replace(/\s\/\s/,' <span class="sl">/</span> ');
  const ids=Object.keys(GAMES);
  if(ids.length>1){
    const wrap=document.querySelector('.brand');
    const sel=el('select','gamepicker');
    sel.setAttribute('aria-label','Choose game');
    sel.innerHTML=ids.map(id=>`<option value="${esc(id)}"${id===GAME_ID?' selected':''}>${esc(GAMES[id].short||GAMES[id].name)}</option>`).join('');
    sel.onchange=()=>{try{localStorage.setItem('rrss-game',sel.value);}catch(e){}const u=new URL(location.href);u.searchParams.set('game',sel.value);location.href=u.toString();};
    if(wrap)wrap.appendChild(sel);
  }
  // keep the URL in sync with the selected game
  try{const u=new URL(location.href);if(u.searchParams.get('game')!==GAME_ID){u.searchParams.set('game',GAME_ID);history.replaceState(null,'',u.toString());}}catch(e){}
})();

function setActiveNav(){document.querySelectorAll('.navbtn').forEach(b=>b.classList.toggle('active',b.dataset.id===state.section));}
function go(id){state.section=id;state.query='';$('search').value='';render();history.replaceState(null,'','#'+id);}

/* ---- search placeholder per section ---- */
const SEARCH_PH={pokemon:'Search species, move, location…',areas:'Search area or a Pokémon in it…',moves:'Search move, type, or category…',evolution:'Search a Pokémon…',items:'Search items…',gifts:'Search gifts & statics…',thief:'Search item or Pokémon…',box:'Search your box…'};

/* ================= RENDER ROOT ================= */
function render(){
  setActiveNav();
  // keep the Box nav count live
  const boxNav=document.querySelector('.navbtn[data-id="box"] .nm small');
  if(boxNav)boxNav.textContent=CAUGHT.size?`${CAUGHT.size} caught`:'caught Pokémon';
  const sec=SECTIONS.find(s=>s.id===state.section);
  $('secTitle').textContent=sec.label;
  const meta=metaFor(state.section);
  $('secSub').textContent=state.section==='box'?(CAUGHT.size+' caught'):(meta&&meta.subtitle?meta.subtitle:(sec.sub||''));
  $('search').placeholder=SEARCH_PH[state.section]||'Search…';
  const c=$('content');c.innerHTML='';
  ({pokemon:renderPokemon,areas:renderAreas,moves:renderMoves,evolution:renderEvolution,items:renderItems,gifts:renderGifts,thief:renderThief,box:renderBox}[state.section])(c);
}
function metaFor(id){const map={pokemon:RAW.pokemon,areas:RAW.areas,moves:RAW.attacks,evolution:RAW.evolution,items:RAW.items,gifts:RAW.gifts};return map[id]?map[id].meta:null;}

/* ---- reusable: about panel ---- */
function aboutPanel(meta,extra){
  if(!meta)return '';
  const blurb=arr(meta.blurb);
  const files=arr(meta.files);
  return `<div class="about">
    <div class="panel"><div class="pbody prose">
      <div class="eyebrow" style="margin-bottom:8px">About this document</div>
      ${blurb.map(p=>`<p>${esc(p)}</p>`).join('')}
      ${extra||''}
    </div></div>
    ${files.length?`<div class="panel"><div class="phead"><h3>Game files</h3></div><div class="pbody"><div class="files">
      ${files.map(f=>`<div class="file"><code>${esc(f.code)}</code><span>${esc(f.desc)}</span></div>`).join('')}
    </div></div></div>`:''}
  </div>`;
}
let aboutOpen={};
function collapsibleAbout(id,meta,extra){
  const open=aboutOpen[id];
  const wrap=el('div');
  const btn=el('button','themebtn');btn.style.cssText='margin:0 0 16px;width:auto;padding:7px 12px';
  btn.innerHTML=(open?'Hide':'Show')+' document notes';
  btn.onclick=()=>{aboutOpen[id]=!open;render();};
  wrap.appendChild(btn);
  if(open)wrap.insertAdjacentHTML('beforeend',aboutPanel(meta,extra));
  return wrap;
}

/* ================= POKÉMON ================= */
const PK=arr(RAW.pokemon.entries).map(e=>({
  dex:e.dex,name:e.name,attrs:arr(e.attrs),changes:arr(e.changes),moves:arr(e.moves),notes:arr(e.notes),
  stats:e.stats||{},statChg:e.statChg||{},a1:e.a1||'',a2:e.a2||'',ah:e.ah||'',megas:arr(e.megas),
  tms:(e.tms||'').split(' ').filter(Boolean),tmsNew:new Set((e.tmsNew||'').split(' ').filter(Boolean)),tmsExtra:arr(e.tmsExtra),evo:arr(e.evo),
  loc:(arr(e.attrs).find(a=>a.label==='Location')||{}).value||'',
  _s:(e.dex+' '+e.name+' '+arr(e.attrs).map(a=>a.value).join(' ')+' '+arr(e.moves).map(m=>m.name).join(' ')).toLowerCase()
}));
PK.forEach(p=>{const n=normName(p.name);if(!NAME2DEX[n])NAME2DEX[n]=p.dex;});
// species that appear in-game but aren't Pokédex entries (alt forms, etc.) still need a dex for sprites/catching
Object.keys(RAW.nameDex||{}).forEach(k=>{if(!NAME2DEX[k])NAME2DEX[k]=RAW.nameDex[k];});
const TM_MOVES=RAW.pokemon.tmMoves||{};
const MOVE_INFO=RAW.moveInfo||{};
function moveData(name){return MOVE_INFO[normName(name)];}
// before→after change rows for moves the hack modifies (keyed by normalized name)
const MOVE_CHG={};
arr(RAW.attacks&&RAW.attacks.entries).forEach(e=>{MOVE_CHG[normName(e.name)]=arr(e.rows);});
function moveChgRowsHtml(name){
  const rows=MOVE_CHG[normName(name)];if(!rows||!rows.length)return '';
  let h='';
  rows.forEach(r=>{
    if(r.kind==='change'){
      const from=+r.from,to=+r.to,d=(!isNaN(from)&&!isNaN(to))?to-from:null;
      h+=`<div class="chgrow"><span class="cl">${esc(r.label)}</span><span class="was">${esc(r.from)}</span><span class="arrow">→</span><span class="now">${esc(r.to)}</span>${d?`<span class="delta ${d>0?'up':'down'}">${d>0?'+':''}${d}</span>`:''}</div>`;
    } else if(r.kind!=='note'||r.label!=='Effect'){ // Effect note is already shown as mm-fx
      h+=`<div class="chgrow"><span class="cl">${esc(r.label||'Effect')}</span><span class="now">${esc(r.value)}</span></div>`;
    }
  });
  return h?`<div class="mm-changes"><div class="mm-changes-h">Changes in this hack</div>${h}</div>`:'';
}
const TYPE_COLORS={Normal:'#9099a1',Fire:'#ff9d55',Water:'#4d90d5',Electric:'#f4d23c',Grass:'#63bc5a',Ice:'#73cec0',Fighting:'#ce4069',Poison:'#ab6ac8',Ground:'#d97845',Flying:'#8fa8dd',Psychic:'#f97176',Bug:'#90c12c',Rock:'#c5b78c',Ghost:'#5269ad',Dragon:'#0b6dc3',Dark:'#5a5366',Steel:'#5a8ea1',Fairy:'#ec8fe6'};
/* ---- move info modal ---- */
const moveModal=el('div','movemodal-backdrop');moveModal.innerHTML='<div class="movemodal" role="dialog" aria-modal="true"></div>';document.body.appendChild(moveModal);
moveModal.addEventListener('click',e=>{if(e.target===moveModal||e.target.closest('.mm-close'))closeMove();});
document.addEventListener('keydown',e=>{if(e.key==='Escape'){closeMove();closeMon();}});
function closeMove(){moveModal.classList.remove('show');}
/* ---- Pokémon preview popup (clicking a mon anywhere opens this instead of leaving the page) ---- */
const monModal=el('div','monmodal-backdrop');monModal.innerHTML='<div class="monmodal" role="dialog" aria-modal="true"></div>';document.body.appendChild(monModal);
monModal.addEventListener('click',e=>{
  if(e.target===monModal||e.target.closest('.pm-close')){closeMon();return;}
  const full=e.target.closest('.pm-full');
  if(full){closeMon();gotoPokemon(full.dataset.mon);return;}
  const mv=e.target.closest('.movelink');
  if(mv&&mv.dataset.move){e.preventDefault();openMove(mv.dataset.move);return;}
  const mon=e.target.closest('.monlink');
  if(mon&&mon.dataset.mon){e.preventDefault();openMon(mon.dataset.mon);return;}
});
function closeMon(){monModal.classList.remove('show');}
function openMon(name){
  let p=PK.find(x=>normName(x.name)===normName(name));
  if(!p){const d=NAME2DEX[normName(name)];if(d)p=PK.find(x=>x.dex===d);}
  if(!p)return;
  const box=monModal.firstElementChild;
  box.innerHTML=`<div class="pm-bar"><button class="pm-full" data-mon="${esc(p.name)}" title="Open full Pokédex page">Full page ↗</button><button class="pm-close" aria-label="Close">✕</button></div>`;
  box.appendChild(pokemonDetail(p));
  monModal.scrollTop=0;box.scrollTop=0;
  monModal.classList.add('show');
}
function openMove(name){
  const mi=moveData(name), box=moveModal.firstElementChild;
  if(!mi){box.innerHTML=`<div class="mm-head"><h3>${esc(name)}</h3><button class="mm-close" aria-label="Close">✕</button></div><div class="mm-body"><p class="mm-desc">No data available for this move.</p></div>`;}
  else{
    const tcol=TYPE_COLORS[mi.t]||'var(--surface-3)';
    box.innerHTML=`<div class="mm-head"><h3>${esc(mi.n||name)}</h3><button class="mm-close" aria-label="Close">✕</button></div>`+
      `<div class="mm-body">`+
      `<div class="mm-tags"><span class="mm-type" style="background:${tcol}">${esc(mi.t||'—')}</span><span class="mm-cat mm-cat-${(mi.c||'').toLowerCase()}">${esc(mi.c||'—')}</span>${mi.chg?'<span class="mm-chg" title="Modified in this hack"><span class="chgmark"></span> Changed in hack</span>':''}</div>`+
      `<div class="mm-stats"><div><b>${mi.pow==null?'—':mi.pow}</b><span>Power</span></div><div><b>${mi.acc==null?'—':mi.acc}</b><span>Accuracy</span></div><div><b>${mi.pp==null?'—':mi.pp}</b><span>PP</span></div></div>`+
      (mi.fx?`<div class="mm-fx"><b>Effect:</b> ${esc(mi.fx)}</div>`:'')+
      (mi.d?`<p class="mm-desc">${esc(mi.d)}</p>`:'')+
      (mi.chg?moveChgRowsHtml(mi.n||name):'')+
      `</div>`;
  }
  moveModal.classList.add('show');
}
function moveChip(name,extra){return `<span class="movelink ${extra||''}" data-move="${esc(name)}" role="button" tabindex="0">${esc(name)}</span>`;}
function moveChgMark(name){const m=moveData(name);return (m&&m.chg)?'<span class="chgmark" title="Move changed in this hack — click for details" aria-label="changed in this hack"></span>':'';}
// soft type-colored background + left accent for a move chip, so its element reads at a glance
function moveTypeBg(name){const m=moveData(name),t=m&&m.t,c=t&&TYPE_COLORS[t];if(!c)return '';
  return ` style="background:color-mix(in srgb,${c} 16%,transparent);border-left:3px solid ${c}" title="${esc(t)}-type"`;}
// forward evolution map, derived from each species' "Evolve <Pre> (…)" obtain location
const PK_BY_DEX={};PK.forEach(p=>PK_BY_DEX[p.dex]=p);
const EVO_NEXT={};
PK.forEach(q=>{
  const m=/^Evolve\s+(.+?)\s*(?:\((.*)\))?\s*$/.exec(q.loc||'');
  if(!m)return;
  const lv=/Lv\.?\s*(\d+)/i.exec(m[2]||'');
  const key=normName(m[1]);
  (EVO_NEXT[key]=EVO_NEXT[key]||[]).push({name:q.name,dex:q.dex,level:lv?+lv[1]:null,method:(m[2]||'').trim()});
});
// Per-move evolution-delay tag: 'excl' = the next evolution never learns it by level-up;
// {early:N} = the evolution learns it N levels later. Only for moves learned after you
// could already evolve, and only for meaningful early leads (systematic +1/+2 shifts hidden).
const EARLY_MIN=3;
function moveDelayMap(p){
  const nexts=EVO_NEXT[normName(p.name)];const map={};if(!nexts||!nexts.length)return map;
  p.moves.forEach((m,i)=>{
    const k=m.name.toLowerCase();let applicable=false,anyLearns=false,minLater=Infinity;
    nexts.forEach(q=>{
      if(m.level<=(q.level||0))return;applicable=true;
      const qe=PK_BY_DEX[q.dex];if(!qe)return;
      let ql=null;qe.moves.forEach(x=>{if(x.name.toLowerCase()===k&&(ql==null||x.level<ql))ql=x.level;});
      if(ql!=null){anyLearns=true;if(ql>m.level)minLater=Math.min(minLater,ql-m.level);}
    });
    if(!applicable)return;
    if(!anyLearns)map[i]={type:'excl'};
    else if(minLater!==Infinity&&minLater>=EARLY_MIN)map[i]={type:'early',n:minLater};
  });
  return map;
}
const STAT_ORDER=['HP','Attack','Defense','Sp. Attack','Sp. Def','Sp. Defense','Sp. Atk','Speed','Total'];
const STAT_SET=new Set(STAT_ORDER);
function changeFlags(p){
  let stat=Object.keys(p.statChg||{}).length>0,ability=false,type=false;
  arr(p.changes).forEach(c=>{if(STAT_SET.has(c.label))stat=true;else if(/Ability/i.test(c.label))ability=true;else if(c.label==='Type')type=true;});
  // a new/edited ability shows up as an asterisked attr (e.g. "Ability 2: Effect Spore **")
  arr(p.attrs).forEach(a=>{if(/Ability/i.test(a.label)&&/\*/.test(a.value))ability=true;});
  return {stat,ability,type};
}

function renderPokemon(c){
  c.appendChild(collapsibleAbout('pokemon',RAW.pokemon.meta,
    `<div class="note" style="margin-top:12px"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><path d="M12 8v5M12 16h.01"/></svg>
     <div><b>*</b> = learnable but not by level-up (egg/TM/tutor). <b>**</b> = unobtainable in the base game (hack-only, omitted from the legal-only build).</div></div>`));
  const md=el('div','md');
  const list=el('div','mlist');
  const detail=el('div','detail');
  md.append(list,detail);c.appendChild(md);

  const q=state.query.toLowerCase().trim();
  const items=q?PK.filter(p=>p._s.includes(q)):PK;
  list.appendChild(el('div','count',items.length+(items.length===1?' match':' Pokémon')));
  if(!items.length){detail.innerHTML=emptyState('No Pokémon match your search.');return;}
  if(!items.includes(PK[state.pkSel]))state.pkSel=PK.indexOf(items[0]);
  const frag=document.createDocumentFragment();
  items.forEach(p=>{
    const b=el('button','litem');
    const idx=PK.indexOf(p);
    b.classList.toggle('active',idx===state.pkSel);
    const fl=changeFlags(p);
    const marks=(fl.stat?`<span class="cmark s" title="Stat changes">S</span>`:'')+(fl.type?`<span class="cmark t" title="Type change">T</span>`:'')+(fl.ability?`<span class="cmark a" title="Ability changes">A</span>`:'');
    b.innerHTML=`${spriteImg(p.dex,32,'lspr')}<span class="dex">${esc(p.dex)}</span><span class="lname">${esc(p.name)}</span>${marks?`<span class="cmarks">${marks}</span>`:''}`;
    b.onclick=()=>{state.pkSel=idx;reRenderKeepScroll();};
    frag.appendChild(b);
  });
  list.appendChild(frag);
  detail.appendChild(pokemonDetail(PK[state.pkSel]));
}

function pokemonDetail(p){
  const wrap=el('div','panel');
  // hero
  const attrsNoLoc=p.attrs.filter(a=>a.label!=='Location');
  wrap.innerHTML=`<div class="pkhero">
    ${spriteImg(p.dex,96,'hspr')}
    <div class="pkid"><span class="num">#${esc(p.dex)}</span><h2>${esc(p.name)}</h2></div>
    ${p.loc?`<div class="loc">Obtain<br><b>${locHtml(p.loc)}</b></div>`:''}
  </div>`;
  const body=el('div','pbody');
  // base stats (always shown)
  if(p.stats && p.stats.total){
    if(p.megas.length){
      const col=(lbl,s,c)=>`<div class="statcol"><div class="eyebrow" style="margin-bottom:9px">${esc(lbl)}</div>${statsPanelOf(s,c)}</div>`;
      let cols=col('Base stats',p.stats,p.statChg);
      p.megas.forEach(mg=>{
        const diff={};STATMETA.forEach(([k])=>{if((+mg.stats[k]||0)!==(+p.stats[k]||0))diff[k]={from:+p.stats[k]||0,to:+mg.stats[k]||0};});
        if((+mg.stats.total||0)!==(+p.stats.total||0))diff.total={from:+p.stats.total||0,to:+mg.stats.total||0};
        cols+=col(`${mg.forme} ${p.name}`,mg.stats,diff);
      });
      body.appendChild(el('div','',`<div class="statcols">${cols}</div>`));
    } else {
      body.appendChild(el('div','',`<div class="eyebrow" style="margin-bottom:10px">Base stats</div>${statsPanel(p)}`));
    }
    body.appendChild(el('div','divider'));
  }
  // single left column: abilities, other changes, moves, TMs, notes (stats stay full-width above)
  const left=el('div','detailcol');
  // evolution: what this species evolves into, and how (shown on the pre-evo)
  if(p.evo.length){
    const evoHtml=p.evo.map(ev=>{
      const meth=ev.level?`<span class="lv">${esc(ev.level)}</span>`:`<span class="lv">special</span>`;
      const link=isMon(ev.into);
      return `<span class="tmon${link?' monlink':''}"${link?monAttr(ev.into):''}>${spriteByName(ev.into,20,'cspr')}${esc(ev.into)}${meth}</span>`;
    }).join('');
    left.appendChild(sub('Evolves into',`<div class="team">${evoHtml}</div>`));
  }
  // abilities: vanilla slots filled in. The docs' "Ability 2"/"Hidden Ability" = the hidden slot.
  const findChg=re=>p.changes.find(c=>re.test(c.label));
  const findAttr=re=>attrsNoLoc.find(a=>re.test(a.label));
  let ab1=p.a1,ab1s=0;const a1c=findChg(/^Ability 1$/),a1a=findAttr(/^Ability 1$/);
  if(a1c){ab1=stripStar(a1c.to);ab1s=starOf(a1c.to);}else if(a1a){ab1=stripStar(a1a.value);ab1s=starOf(a1a.value);}
  const ab2=p.a2||'';   // second regular ability (vanilla; hack docs don't track this slot)
  let hid=p.ah,hids=0;const hc=findChg(/^(Ability 2|Hidden Ability)$/),ha=findAttr(/^(Ability 2|Hidden Ability)$/);
  if(hc){hid=stripStar(hc.to);hids=starOf(hc.to);}else if(ha){hid=stripStar(ha.value);hids=starOf(ha.value);}
  const otherAttrs=attrsNoLoc.filter(a=>!/^(Ability 1|Ability 2|Hidden Ability)$/.test(a.label));
  {
    let dl='<dl class="dl">';
    if(ab1)dl+=`<dt>Ability 1</dt><dd>${esc(ab1)}${starBadge(ab1s)}</dd>`;
    if(ab2&&ab2!==ab1)dl+=`<dt>Ability 2</dt><dd>${esc(ab2)}</dd>`;
    if(hid&&hid!==ab1&&hid!==ab2)dl+=`<dt>Hidden Ability</dt><dd>${esc(hid)}${starBadge(hids)}</dd>`;
    otherAttrs.forEach(a=>{const n=starOf(a.value);dl+=`<dt>${esc(a.label)}</dt><dd>${esc(stripStar(a.value))}${starBadge(n)}</dd>`;});
    if(dl!=='<dl class="dl">')left.appendChild(sub('Abilities',dl));
  }
  // changes grouped by forme (primary-forme stat changes live in the base-stats panel)
  if(p.changes.length){
    const byForme={};
    p.changes.forEach(ch=>{(byForme[ch.forme||'']=byForme[ch.forme||'']||[]).push(ch);});
    const chWrap=el('div');
    Object.keys(byForme).forEach(fk=>{
      const isPrimary=(fk===''||/normal/i.test(fk));
      const isMega=/mega|primal/i.test(fk);   // mega/primal stats are shown in the Base-stats columns
      const group=byForme[fk];
      const stats=group.filter(g=>STAT_SET.has(g.label));
      const others=group.filter(g=>!STAT_SET.has(g.label)&&!/^(Ability 1|Ability 2|Hidden Ability)$/.test(g.label));
      const showStats=!isPrimary && !isMega && stats.length>0;
      if(!showStats && !others.length)return;
      let html='';
      if(fk)html+=`<div class="eyebrow" style="margin:10px 0 8px">${esc(fk)}</div>`;
      if(showStats)html+=statBlock(stats);
      if(others.length)html+=`<div style="margin-top:${showStats?'10px':'0'}">`+others.map(o=>chgRow(o)).join('')+`</div>`;
      chWrap.insertAdjacentHTML('beforeend',html);
    });
    if(chWrap.innerHTML.trim())left.appendChild(sub('Other changes',chWrap.innerHTML));
  }

  // level-up moves (tag moves you'd keep by delaying evolution)
  const dmap=moveDelayMap(p);
  const nextName=(EVO_NEXT[normName(p.name)]||[]).map(q=>q.name).join(' / ');
  if(p.moves.length){
    const mv='<div class="moves">'+p.moves.map((m,i)=>{
      const d=dmap[i];
      const dBadge=d?(d.type==='excl'
        ?`<span class="badge excl" title="${esc(nextName)} never learns this by level-up">exclusive</span>`
        :`<span class="badge early" title="${esc(nextName)} learns this ${d.n} levels later">${d.n} lv early</span>`):'';
      return `<div class="move movelink${d?' mv-'+d.type:''}" data-move="${esc(m.name)}" role="button" tabindex="0"${moveTypeBg(m.name)}><span class="lv">${m.level}</span><span class="mv">${esc(m.name)}${starBadge(m.rarity)}${moveChgMark(m.name)}</span>${dBadge}</div>`;
    }).join('')+'</div>';
    left.appendChild(sub('Level-up moves',mv));
  }
  // TM / HM compatibility (ORAS base + hack additions), collapsed by default
  if(p.tms.length || p.tmsExtra.length){
    const chips=p.tms.map(k=>{const nu=p.tmsNew.has(k),mn=TM_MOVES[k]||'';return `<span class="tmchip movelink${nu?' tmnew':''}" data-move="${esc(mn)}" role="button" tabindex="0"${nu?' title="Added by the hack — not learnable in base ORAS"':moveTypeBg(mn)}><span class="tmn">${esc(k)}</span>${esc(mn)}${moveChgMark(mn)}</span>`;}).join('')
      + p.tmsExtra.map(mv=>`<span class="tmchip tmnew movelink" data-move="${esc(mv)}" role="button" tabindex="0" title="Hack-added move taught by TM"><span class="tmn">TM</span>${esc(mv)}</span>`).join('');
    const nNew=p.tmsNew.size+p.tmsExtra.length;
    left.appendChild(el('div','',`<details class="tmwrap"><summary>TM / HM compatibility · ${p.tms.length+p.tmsExtra.length}${nNew?` <span class="tmnewcount">+${nNew} added</span>`:''}</summary><div class="tmgrid">${chips}</div>${nNew?`<div class="tmcap"><span class="tmswatch"></span> Green = added by this hack (not learnable in base ORAS).</div>`:''}</details>`));
  }
  if(p.notes.length){
    left.appendChild(el('div','',`<div class="note plain" style="margin-top:14px"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 8v5M12 16h.01"/><circle cx="12" cy="12" r="9"/></svg><div>${p.notes.map(esc).join('<br>')}</div></div>`));
  }
  body.appendChild(left);
  wrap.appendChild(body);
  return wrap;
}
function sub(title,html){return el('div','',`<div class="eyebrow" style="margin-bottom:9px">${esc(title)}</div>${html}`);}
const STATMETA=[['hp','HP'],['atk','Attack'],['def','Defense'],['spa','Sp. Atk'],['spd','Sp. Def'],['spe','Speed']];
function statRow(lbl,v,c,scale){
  const w=Math.min(100,Math.round(v/scale*100));
  let cls='',ghost='',ann='<span class="sann"></span>';
  if(c){const d=(+c.to)-(+c.from);cls=d>0?'up':'down';
    ghost=`<i class="ghost" style="width:${Math.min(100,Math.round((+c.from)/scale*100))}%"></i>`;
    ann=`<span class="sann"><span class="delta ${d>0?'up':'down'}" title="was ${esc(c.from)} in the base game">${d>0?'+':''}${d}</span></span>`;}
  return `<div class="strow ${cls}${lbl==='Total'?' total':''}"><span class="sl">${lbl}</span><span class="sbar">${ghost}<i style="width:${w}%"></i></span>${ann}<span class="sv"><b>${v}</b></span></div>`;
}
function statsPanelOf(s,chg){
  s=s||{};chg=chg||{};
  let rows=STATMETA.map(([k,lbl])=>statRow(lbl,+s[k]||0,chg[k],200)).join('');
  rows+=statRow('Total',+s.total||0,chg.total,720);
  return `<div class="stats">${rows}</div>`;
}
function statsPanel(p){return statsPanelOf(p.stats,p.statChg);}
function statBlock(stats){
  const order=['HP','Attack','Defense','Sp. Attack','Sp. Atk','Sp. Defense','Sp. Def','Speed','Total'];
  stats.sort((a,b)=>order.indexOf(a.label)-order.indexOf(b.label));
  const maxv=Math.max(...stats.map(s=>Math.max(+s.from||0,+s.to||0,1)));
  return '<div class="statchg">'+stats.map(s=>{
    const from=+s.from,to=+s.to,ok=!isNaN(from)&&!isNaN(to);
    const d=ok?to-from:0;
    const wF=ok?Math.round(Math.min(from,to)/maxv*100):0;
    const wT=ok?Math.round(Math.max(from,to)/maxv*100):0;
    return `<div class="statrow">
      <span class="sn">${esc(s.label)}</span>
      <span class="bar"><i style="width:${wT}%;opacity:.28"></i><i class="now" style="width:${wF}%"></i></span>
      <span class="val"><span class="to">${esc(s.to)}</span>${d?`<span class="delta ${d>0?'up':'down'}" title="was ${esc(s.from)} in the base game">${d>0?'+':''}${d}</span>`:''}</span>
    </div>`;
  }).join('')+'</div>';
}
function chgRow(o){
  const n=starOf(o.to);
  return `<div class="chgrow"><span class="cl">${esc(o.label)}</span><span class="was">${esc(o.from)}</span><span class="arrow">→</span><span class="now">${esc(stripStar(o.to))}${starBadge(n)}</span></div>`;
}

/* ================= AREAS ================= */
const AREAS=arr(RAW.areas&&RAW.areas.areas).map(a=>{
  const wild=arr(a.wild).map(w=>({method:w.method,level:w.level,species:arr(w.species)}));
  const rosters=arr(a.rosters).map(r=>({title:r.title,kind:r.kind,reward:r.reward||'',note:r.note||'',optional:!!r.optional,trainers:arr(r.trainers).map(t=>({id:t.id,name:t.name,badge:t.badge,choice:t.choice||'',split:t.split||'',optional:!!t.optional,b2b:t.b2b||'',reward:t.reward||'',notes:arr(t.notes),team:arr(t.team)}))}));
  const special=arr(a.special).map(s=>({title:s.title,team:arr(s.team).map(m=>({...m,moves:arr(m.moves)}))}));
  // note: rosters below already keep the full team objects (species/level/item/ability/nature/moves)
  const items=arr(a.items).map(it=>({id:it.id,name:it.name}));
  const notes=arr(a.notes);
  const gifts=arr(a.gifts);
  const giftMons=[];gifts.forEach(g=>g.replace(/\s*\(\d+%\)\s*$/,'').split('/').forEach(s=>{s=s.trim();if(s)giftMons.push(s);}));
  const mons=new Set();wild.forEach(w=>w.species.forEach(s=>mons.add(s.name.toLowerCase())));
  rosters.forEach(r=>r.trainers.forEach(t=>t.team.forEach(m=>mons.add((m.species||'').toLowerCase()))));
  return {name:a.name,weather:a.weather||'',wild,rosters,special,items,notes,gifts,giftMons,sep:!!a.sep,_s:(a.name+' '+[...mons].join(' ')+' '+items.map(it=>it.name).join(' ')+' '+notes.join(' ')+' '+gifts.join(' ')).toLowerCase()};
});
// permanent weather in an area (was "(PERMA X)" in the name); shown as an icon + a top banner.
// effect text is generation-aware — several mechanics were only added in Gen 4 / Gen 5.
const WEATHER={
  sun:{icon:'☀️',label:'Permanent harsh sunlight',fx:'Fire moves ×1.5, Water ×0.5 · SolarBeam charges in one turn · Synthesis/Morning Sun heal more.'},
  rain:{icon:'🌧️',label:'Permanent rain',fx:'Water moves ×1.5, Fire ×0.5 · Thunder'+(GEN>=5?' & Hurricane':'')+' never miss · SolarBeam weakened.'},
  sand:{icon:'🌪️',label:'Permanent sandstorm',fx:'Non Rock/Ground/Steel lose 1⁄16 HP each turn.'+(GEN>=4?' · Rock types get +50% Sp. Def.':'')},
  hail:{icon:'❄️',label:'Permanent hail',fx:'Non-Ice Pokémon lose 1⁄16 HP each turn.'+(GEN>=4?' · Blizzard never misses.':'')}
};
function weatherOf(a){return (a&&a.weather&&WEATHER[a.weather])||null;}
const wildOpen={};
// gym badges — earned automatically when a gym's leader is beaten.
function gymKey(n){return n.replace(/\s*\(.*\)\s*$/,'').toLowerCase().trim();}
// the badge-granting trainer(s) in a gym: names like "Gym Leader X" / "Leaders Liza & Tate"
// (bracketed "Leader Rival [Theme]" battles are rival mirrors fought elsewhere, not real leaders)
function gymLeaderIds(g){const out=[];g.rosters.forEach(r=>r.trainers.forEach(t=>{if(/^(gym )?leaders?\b/i.test(t.name)&&!/\[/.test(t.name))out.push(t.id);}));return out;}
function badgeEarned(g){return gymLeaderIds(g).some(id=>TRAINERS_DONE.has(id));}
// map a gym (by its leader's name) to its canonical badge image key in window.RRSS_BADGES
const BADGE_BY_LEADER=[[/\bbrock\b/,'boulder'],[/\bmisty\b/,'cascade'],[/\bsurge\b/,'thunder'],[/\berika\b/,'rainbow'],[/\bkoga\b/,'soul'],[/\bsabrina\b/,'marsh'],[/\bblaine\b/,'volcano'],[/\bgiovanni\b/,'earth'],
[/\broxanne\b/,'stone'],[/\bbrawly\b/,'knuckle'],[/\bwattson\b/,'dynamo'],[/\bflannery\b/,'heat'],[/\bnorman\b/,'balance'],[/\bwinona\b/,'feather'],[/\b(tate|liza)\b/,'mind'],[/\b(wallace|juan)\b/,'rain'],
[/\b(cilan|chili|cress)\b/,'trio'],[/\blenora\b/,'basic'],[/\bburgh\b/,'insect'],[/\belesa\b/,'bolt'],[/\bclay\b/,'quake'],[/\bskyla\b/,'jet'],[/\bbrycen\b/,'freeze'],[/\b(drayden|iris)\b/,'legend']];
function gymBadgeKey(g){const nm=g.name.toLowerCase();for(const[re,k]of BADGE_BY_LEADER){if(re.test(nm))return k;}
  for(const id of gymLeaderIds(g)){const t=g.rosters.flatMap(r=>r.trainers).find(x=>x.id===id);if(t){const ln=t.name.toLowerCase();for(const[re,k]of BADGE_BY_LEADER){if(re.test(ln))return k;}}}return null;}
function badgeImg(g){const bk=gymBadgeKey(g),spr=window.RRSS_BADGES;return bk&&spr&&spr[bk]?`data:image/png;base64,${spr[bk]}`:null;}
// a chip label from the badge key ("boulder" -> "Boulder"); falls back to the gym name
function badgeLabel(g){const k=gymBadgeKey(g);return k?k[0].toUpperCase()+k.slice(1):g.name.replace(/\s*\(.*\)\s*$/,'').replace(/\s*Gym$/,'');}
// every area that holds a real gym leader (in story order), de-duped by badge (so Blaine's
// oddly-named area still counts, and revisits collapse into one chip)
const GYMS=AREAS.filter(a=>gymLeaderIds(a).length>0).filter((a,i,arr)=>{const k=gymBadgeKey(a)||gymKey(a.name);return arr.findIndex(x=>(gymBadgeKey(x)||gymKey(x.name))===k)===i;});
// level caps: each split has a cap and a boss whose defeat advances you to the next cap
const SPLITS=arr(RAW.areas&&RAW.areas.meta&&RAW.areas.meta.splits);
function currentSplitIdx(){for(let i=0;i<SPLITS.length;i++){const bs=arr(SPLITS[i].bosses);if(!bs.length||!bs.some(b=>TRAINERS_DONE.has(b)))return i;}return SPLITS.length;}
function currentCap(){const i=currentSplitIdx();return i<SPLITS.length?SPLITS[i].cap:(SPLITS.length?SPLITS[SPLITS.length-1].cap:null);}
function splitLabel(n){return n.replace(/\s*Split$/i,'');}
// areas that hold a split boss (beating it raises the level cap) get highlighted in the list
const BOSS_IDS=new Set();SPLITS.forEach(s=>arr(s.bosses).forEach(b=>{if(b)BOSS_IDS.add(b);}));
function areaHasBoss(a){return a.rosters.some(r=>r.trainers.some(t=>BOSS_IDS.has(t.id)));}
const AREA2IDX={};
AREAS.forEach((a,i)=>{const n=normName(a.name);if(AREA2IDX[n]==null)AREA2IDX[n]=i;});
function areaCaughtCount(a){
  const wildC=a.wild.reduce((n,w)=>n+w.species.filter(s=>isCaught(s.name)).length,0);
  // a gift (e.g. the starter) is its own separate encounter only where there's no wild
  const giftC=a.wild.length?0:a.giftMons.filter(s=>isCaught(s)).length;
  return wildC+giftC;
}
// in-game "met location": areas sharing one count as a single nuzlocke encounter (e.g. Route 104 South/North -> Route 104)
function metLoc(name){
  let s=name.replace(/\s*\(.*\)\s*$/,'');
  s=s.replace(/-\d+$/,'').trim();
  s=s.replace(/\s+(North|South|East|West|South-West|North-West|South-East|North-East)$/,'');
  s=s.replace(/\s+B?\d+F(\s*[\/,]\s*B?\d+F)*$/,'');
  s=s.replace(/\s+Summit(\s+\d+)?$/,'');
  s=s.replace(/\s+(Basement|Ice Room|Outside|Inside|Out|Interior|Entrance|Other|Front Rooms|Water Rooms|Back Rooms|Rooms)$/,'');
  return s.trim();
}
const MET_GROUP={};
AREAS.forEach(a=>{if(a.sep)return;const m=metLoc(a.name);(MET_GROUP[m]=MET_GROUP[m]||[]).push(a);});
function areaGroup(a){return a.sep?[a]:(MET_GROUP[metLoc(a.name)]||[a]);}
function groupSiblings(a){return areaGroup(a).filter(x=>x!==a);}
function groupCaughtArea(a){return areaGroup(a).find(x=>areaCaughtCount(x)>0);}
function groupMissedArea(a){return areaGroup(a).find(x=>AREA_MISSED.has(x.name));}
// roster (non-rematch) trainers you'd actually face, rival variants filtered by profile
function areaRosterTrainers(a){
  const rn=rivalName(), rs=rivalStarter(), out=[];
  a.rosters.forEach(r=>{if(r.kind==='rematch')return;r.trainers.forEach(t=>{
    if(t.choice&&PROFILE.starter&&t.choice!==PROFILE.starter)return;
    if(isRivalTrainer(t)){if(rn&&rivalGenderOf(t.name)!==rn)return;if(rs&&rivalStarterOf(t.team)!==rs)return;}
    out.push(t);});});
  return out;
}
// run-wide totals for the progress bar: trainers you'd face, and nuzlocke encounters
// (one per met-location group that has a wild table, plus each gift-only encounter)
// mandatory / optional trainer totals and beaten counts, tracked separately
function trainerCounts(){let mT=0,oT=0,mB=0,oB=0;AREAS.forEach(a=>areaRosterTrainers(a).forEach(t=>{const done=TRAINERS_DONE.has(t.id);if(t.optional){oT++;if(done)oB++;}else{mT++;if(done)mB++;}}));return{mT,oT,mB,oB};}
function encounterTotal(){
  const seen=new Set();let n=0;
  AREAS.forEach(a=>{const key=a.sep?(' '+a.name):metLoc(a.name);if(seen.has(key))return;seen.add(key);
    const grp=areaGroup(a);
    if(grp.some(x=>x.wild.length>0)||grp.some(x=>x.wild.length===0&&x.giftMons.length>0))n++;});
  return n;
}
function areaStatus(a){
  const caught=areaCaughtCount(a)>0, missed=AREA_MISSED.has(a.name), hasEnc=a.wild.length>0||a.giftMons.length>0;
  const grp=areaGroup(a);
  const grpCaught=grp.some(x=>areaCaughtCount(x)>0), grpMissed=grp.some(x=>AREA_MISSED.has(x.name));
  const grpHasEnc=grp.some(x=>x.wild.length>0||x.giftMons.length>0);
  const trs=areaRosterTrainers(a), hasTr=trs.length>0;
  // optional fights (item-guard bosses, side trainers) don't block area completion
  const reqTrs=trs.filter(t=>!t.optional);
  const trainersDone=reqTrs.every(t=>TRAINERS_DONE.has(t.id));
  const encResolved=!grpHasEnc||grpCaught||grpMissed;
  const complete=(hasEnc||hasTr)&&encResolved&&trainersDone;
  const optionalsLeft=trs.some(t=>t.optional&&!TRAINERS_DONE.has(t.id));
  const resolvedElsewhere=hasEnc&&!caught&&!missed&&(grpCaught||grpMissed);
  return {caught,missed,hasEnc,hasTr,trainersDone,complete,optionalsLeft,trs,resolvedElsewhere};
}

function profileBar(){
  const wrap=el('div','profilebar');
  const seg=(label,key,opts)=>`<div class="pfield"><span class="plabel">${label}</span><div class="seg">`+
    opts.map(o=>`<button class="segbtn${PROFILE[key]===o.val?' on':''}" data-pkey="${key}" data-pval="${o.val}">${o.html}</button>`).join('')+`</div></div>`;
  const gameStarters=arr(RAW.areas&&RAW.areas.meta&&RAW.areas.meta.starters);
  if(gameStarters.length){
    // starter-only games (e.g. Brutal Black): pick a starter to show its battle variants
    const starters=gameStarters.map(s=>({val:s,html:spriteByName(s,18,'cspr')+s}));
    const hint=PROFILE.starter?`Trainer battles show the teams for <b>${esc(PROFILE.starter)}</b>`:'Pick your starter to show the matching (rival & first-gym) battles';
    wrap.innerHTML=`${seg('Your starter','starter',starters)}<div class="pnote">${hint}</div>`;
  } else {
    const genders=[{val:'Brendan',html:'Brendan'},{val:'May',html:'May'}];
    const starters=['Treecko','Torchic','Mudkip'].map(s=>({val:s,html:spriteByName(s,18,'cspr')+s}));
    const rn=rivalName(), rs=rivalStarter();
    const hint=(rn&&rs)?`Rival battles show only <b>${rn}</b> with <b>${rs}</b>`:'Pick both to filter rival (Brendan/May) battles to yours';
    wrap.innerHTML=`${seg('You play as','gender',genders)}${seg('Your starter','starter',starters)}<div class="pnote">${hint}</div>`;
  }
  wrap.querySelectorAll('.segbtn').forEach(b=>b.onclick=()=>{const k=b.dataset.pkey,v=b.dataset.pval;PROFILE[k]=(PROFILE[k]===v)?null:v;saveProfile();reRenderKeepScroll();});
  return wrap;
}
function renderAreas(c){
  c.appendChild(collapsibleAbout('areas',RAW.areas.meta));
  c.appendChild(profileBar());
  if(GYMS.length){
    const earned=GYMS.filter(g=>badgeEarned(g)).length;
    const bd=el('div','badgebar');
    bd.innerHTML=`<span class="plabel">Badges <span class="badgecount">${earned}/${GYMS.length}</span></span>`+
      GYMS.map(g=>{const on=badgeEarned(g),lbl=badgeLabel(g),
        img=badgeImg(g),glyph=img?`<img class="bimg" src="${img}" alt="">`:`<span class="bmark"></span>`;
        return `<button class="badgechip${on?' on':''}" data-badge="${esc(gymBadgeKey(g)||gymKey(g.name))}" title="${esc(lbl)} Badge${on?' — earned (leader beaten)':' — click when you beat the leader'}">${glyph}${esc(lbl)}</button>`;}).join('');
    c.appendChild(bd);
  }
  if(SPLITS.length){
    const curIdx=currentSplitIdx(),cap=currentCap(),done=curIdx>=SPLITS.length;
    const curName=done?'run complete':splitLabel(SPLITS[curIdx].name)+' split';
    const lc=el('div','lcapbar');
    lc.innerHTML=`<span class="plabel">Level cap <span class="lcapnow">${cap!=null?cap:'—'}</span> <span class="lcapsub">${esc(curName)}</span></span>`+
      SPLITS.map((s,i)=>{const beaten=i<curIdx,cur=i===curIdx&&!done;
        return `<span class="lcapchip${beaten?' done':''}${cur?' cur':''}" title="${esc(splitLabel(s.name))} split — cap ${s.cap}${beaten?' · cleared':cur?' · current':''}">${s.cap}</span>`;}).join('');
    c.appendChild(lc);
  }
  const bar=el('div','areabar');
  const nc=CAUGHT.size, nm=AREA_MISSED.size, eTot=encounterTotal(), tc=trainerCounts();
  const parts=[`<b>${nc}</b>/<b>${eTot}</b> caught`,`<b>${tc.mB}</b>/<b>${tc.mT}</b> trainers beaten`];
  if(tc.oT)parts.push(`<b>${tc.oB}</b>/<b>${tc.oT}</b> optional beaten`);
  if(nm)parts.push(`<b>${nm}</b> missed`);
  bar.innerHTML=`<div class="attempts"><span class="plabel">Attempt</span>`+
      `<select class="attemptsel" aria-label="Choose attempt">${ATTEMPTS.map(a=>`<option value="${esc(a.id)}"${a.id===ATTEMPT_ID?' selected':''}>${esc(a.name)}</option>`).join('')}</select>`+
      `<button class="attbtn attnew" title="Start a new attempt with fresh tracking">+ New</button>`+
      `<button class="attbtn attren" title="Rename this attempt">Rename</button>`+
      (ATTEMPTS.length>1?`<button class="attbtn attdel" title="Delete this attempt and its tracking">Delete</button>`:'')+
    `</div>`+
    `<span class="caughtcount">${parts.length?parts.join(' · '):'No progress yet'}</span>`+
    `<button class="resetbtn"${trackTotal()?'':' disabled'}>Reset progress</button>`;
  bar.querySelector('.resetbtn').onclick=resetCaught;
  bar.querySelector('.attemptsel').onchange=e=>switchAttempt(e.target.value);
  bar.querySelector('.attnew').onclick=newAttempt;
  bar.querySelector('.attren').onclick=renameAttempt;
  const _del=bar.querySelector('.attdel');if(_del)_del.onclick=deleteAttempt;
  c.appendChild(bar);
  const md=el('div','md');const list=el('div','mlist');const detail=el('div','detail');
  md.append(list,detail);c.appendChild(md);
  const q=state.query.toLowerCase().trim();
  const items=q?AREAS.filter(a=>a._s.includes(q)):AREAS;
  list.appendChild(el('div','count',items.length+' location'+(items.length===1?'':'s')+(q?'':` · ${eTot} encounters · ${tc.mT} trainers${tc.oT?` + ${tc.oT} optional`:''}`)));
  if(!items.length){detail.innerHTML=emptyState('No areas match your search.');return;}
  // on first open, jump to the first area you still have work left in
  if(!state.areaInit&&!q){state.areaInit=true;for(let i=0;i<AREAS.length;i++){const st=areaStatus(AREAS[i]);if((st.hasEnc||st.hasTr)&&!st.complete){state.areaSel=i;break;}}}
  if(!items.includes(AREAS[state.areaSel]))state.areaSel=AREAS.indexOf(items[0]);
  const frag=document.createDocumentFragment();
  items.forEach(a=>{
    const idx=AREAS.indexOf(a);
    const b=el('button','litem');b.classList.toggle('active',idx===state.areaSel);
    const tc=a.rosters.reduce((n,r)=>n+(r.kind==='rematch'?0:r.trainers.length),0);
    const st=areaStatus(a);
    b.classList.toggle('done',st.complete);
    b.classList.toggle('optleft',st.complete&&st.optionalsLeft);
    const boss=areaHasBoss(a);b.classList.toggle('hasboss',boss);
    const optN=st.trs.filter(t=>t.optional&&!TRAINERS_DONE.has(t.id)).length;
    const marker=st.complete&&st.optionalsLeft?`<span class="areacheck optleft" title="Done — ${optN} optional trainer${optN===1?'':'s'} still available here">◑</span>`
      :st.complete?`<span class="areacheck done" title="Route complete">✓</span>`
      :st.caught?`<span class="areacheck" title="Pokémon caught here">✓</span>`
      :st.missed?`<span class="areamiss" title="Encounter missed here">✕</span>`
      :st.resolvedElsewhere?`<span class="arealinked" title="Encounter used elsewhere at this met location">↔</span>`:'';
    const wx=weatherOf(a);
    b.innerHTML=`<span class="lname">${boss?`<span class="bosstag" title="Contains a split boss — beating it raises the level cap">★</span>`:''}${esc(a.name)}${wx?` <span class="wxicon" title="${esc(wx.label)}">${wx.icon}</span>`:''}</span><span class="lmeta">${a.wild.length?a.wild.length+' wild':''}${a.wild.length&&tc?' · ':''}${tc?tc+' trn':''}</span>${marker}`;
    b.onclick=()=>{state.areaSel=idx;reRenderKeepScroll();};
    frag.appendChild(b);
  });
  list.appendChild(frag);
  detail.appendChild(areaDetail(AREAS[state.areaSel]));
}
function speciesChip(s,pct){
  const link=isMon(s.name), caught=isCaught(s.name);
  const cls='chip mon'+(s.rare?' rare':'')+(link?' monlink':'')+(caught?' caught':'');
  return `<span class="${cls}"${monAttr(s.name)}>`+
    (link?`<button class="catch" data-catch="${esc(s.name)}" aria-pressed="${caught}" title="${caught?'Caught — click to unmark':'Mark as caught'}"></button>`:'')+
    `${spriteByName(s.name,22,'cspr')}${esc(s.name)}`+
    (pct==='dupe'?`<span class="pct dupe" title="Already caught — skipped under the dupes clause">dupe</span>`
      :(pct!=null?`<span class="pct">${fmtPct(pct)}</span>`:(s.rare?' <span style="opacity:.7">5%</span>':'')))+
    `</span>`;
}
function wildRow(w){
  const total=w.species.length;
  const caughtN=w.species.filter(s=>isCaught(s.name)).length;
  const hasPct=w.species.some(s=>s.pct!=null);
  let chips;
  if(hasPct){
    // the game gives real encounter rates: show them as-is, for every method
    chips=w.species.map(s=>speciesChip(s,s.pct!=null?s.pct:null)).join('');
  } else {
    // dupes clause: caught species are skipped; rescale the base odds over the uncaught ones
    const isLand=LAND_METHODS.has(w.method);
    let pcts=null;
    if(isLand){
      const base=encPcts(w.species);
      const sum=w.species.reduce((a,s,i)=>a+(isCaught(s.name)?0:base[i]),0);
      pcts=w.species.map((s,i)=>sum>0?base[i]/sum*100:0);
    }
    chips=w.species.map((s,i)=>isCaught(s.name)?speciesChip(s,'dupe'):speciesChip(s,isLand?pcts[i]:null)).join('');
  }
  const summary=`<span class="cc">${caughtN}/${total} caught</span>`;
  return `<tr><td>${methodTag(w.method)}<div class="wsum">${summary}</div></td><td class="mono">${esc(w.level)}</td><td><div class="chips">${chips}</div></td></tr>`;
}
function areaDetail(a){
  const wrap=el('div');
  // permanent-weather banner at the top of the area
  const wx=weatherOf(a);
  if(wx){const wb=el('div','wxbanner wx-'+a.weather);
    wb.innerHTML=`<span class="wxbig">${wx.icon}</span><div><b>${esc(wx.label)}</b><div class="wxfx">${esc(wx.fx)}</div></div>`;
    wrap.appendChild(wb);}
  // a plain (non-starter) gift is its own encounter, so it shows as a "Gift" method row in the
  // encounters table; the multi-option starter choice keeps its dedicated picker panel below.
  const starters=arr(RAW.areas&&RAW.areas.meta&&RAW.areas.meta.starters);
  const isStarterGift=g=>{const o=g.replace(/\s*\(\d+%\)\s*$/,'').split('/').map(s=>s.trim());return o.length>1&&o.every(x=>starters.indexOf(x)>-1);};
  const giftRows=arr(a.gifts).filter(g=>!isStarterGift(g)).map(g=>({method:'Gift',level:'',species:g.replace(/\s*\(\d+%\)\s*$/,'').split('/').map(s=>s.trim()).filter(Boolean).map(n=>({name:n}))})).filter(r=>r.species.length);
  const wildRows=a.wild.concat(giftRows);
  // wild
  if(wildRows.length){
    const caughtList=[];wildRows.forEach(w=>w.species.forEach(s=>{if(isCaught(s.name))caughtList.push(s);}));
    const caughtHere=caughtList.length;
    const missed=AREA_MISSED.has(a.name);
    // shared met-location: this route's encounter may be used at a sibling area
    const sibs=groupSiblings(a);
    const elseCaught=sibs.find(x=>areaCaughtCount(x)>0);
    const elseMissed=sibs.find(x=>AREA_MISSED.has(x.name));
    const resolvedElse=(caughtHere===0&&!missed)&&(elseCaught||elseMissed);
    const resolved=caughtHere>0||missed||!!resolvedElse;
    const open=(a.name in wildOpen)?wildOpen[a.name]:!resolved;
    const areaLink=x=>`<span class="loclink arealink" data-area="${esc(x.name)}" role="button" tabindex="0">${esc(x.name)}</span>`;
    const p=el('div','panel');
    let sub;
    if(missed)sub=`<span class="submiss">✕ Encounter missed</span>${open?'':' · collapsed'}`;
    else if(caughtHere>0)sub=`<span class="subcaught">✓ ${caughtHere} caught here</span>${open?'':' · collapsed for your nuzlocke'}`;
    else if(resolvedElse)sub=`<span class="submiss">↔ Encounter used at ${(elseCaught||elseMissed).name}</span>`;
    else sub='Wild encounters · tick a box to mark caught';
    p.innerHTML=`<div class="phead"><h3>${esc(a.name)}</h3><span class="sub">${sub}</span><div class="pheadbtns">`+
      `<button class="missbtn${missed?' on':''}" data-miss="${esc(a.name)}" title="No usable encounter here (fainted or fled)">${missed?'Un-miss':'Mark missed'}</button>`+
      `<button class="collapsebtn" data-wild="${esc(a.name)}" data-open="${open}">${open?'Hide':'Show'} wild</button></div></div>`;
    const body=el('div','pbody');
    const groupNote=sibs.length?`<div class="wcap grpnote">↔ Counts as <b>one nuzlocke encounter</b> (same met location) with: ${sibs.map(areaLink).join(', ')}</div>`:'';
    if(open){
      body.innerHTML=groupNote+`<div class="tblwrap"><table class="data"><thead><tr><th>Method</th><th>Level</th><th>Species</th></tr></thead><tbody>`+
        wildRows.map(w=>wildRow(w)).join('')+
        `</tbody></table></div>`;
    } else if(resolvedElse){
      body.innerHTML=`<div class="collapsednote">↔ Your <b>${esc(metLoc(a.name))}</b> encounter was already ${elseCaught?'caught':'missed'} at ${areaLink(elseCaught||elseMissed)} — same met location.</div>`;
    } else if(missed && caughtHere===0){
      body.innerHTML=`<div class="collapsednote">✕ Encounter <b>missed</b> here — nothing obtained (fainted or fled).</div>`;
    } else {
      body.innerHTML=`<div class="collapsednote">Caught here: <span class="chips" style="display:inline-flex;vertical-align:middle">${caughtList.map(s=>speciesChip(s,'dupe')).join('')}</span></div>`;
    }
    p.appendChild(body);wrap.appendChild(p);
  } else if(!arr(a.gifts).length){
    const p=el('div','panel');p.innerHTML=`<div class="phead"><h3>${esc(a.name)}</h3></div><div class="pbody" style="color:var(--muted);font-size:13px">No wild encounter data for this location.</div>`;wrap.appendChild(p);
  }
  // starter choice (e.g. the Nuvema Town starter); highlights your pick. plain gifts are
  // shown as a "Gift" encounter method row in the table above instead.
  if(arr(a.gifts).some(isStarterGift)){
    const p=el('div','panel');
    p.innerHTML=`<div class="phead"><h3>Starter</h3>${!PROFILE.starter?`<span class="sub">Pick yours in the bar above</span>`:''}</div>`;
    const body=el('div','pbody');
    body.innerHTML=a.gifts.filter(isStarterGift).map(g=>{
      const opts=g.replace(/\s*\(\d+%\)\s*$/,'').split('/').map(s=>s.trim()).filter(Boolean);
      return `<div class="chips">`+opts.map(o=>{
        const mine=PROFILE.starter&&PROFILE.starter===o, caught=isCaught(o), link=isMon(o);
        return `<span class="chip mon${link?' monlink':''}${caught?' caught':''}"${monAttr(o)}>`+
          (link?`<button class="catch" data-catch="${esc(o)}" aria-pressed="${caught}" title="${caught?'Caught — click to unmark':'Mark this gift as caught (adds it to your box)'}"></button>`:'')+
          `${spriteByName(o,22,'cspr')}${esc(o)}${mine?` <span class="pct">yours</span>`:''}</span>`;
      }).join('')+`</div>`;
    }).join('');
    p.appendChild(body);wrap.appendChild(p);
  }
  // notes from the mastersheet (rival hints, item gifts, etc.)
  if(arr(a.notes).length){
    const p=el('div','panel');
    p.innerHTML=`<div class="phead"><h3>Notes</h3></div>`;
    const body=el('div','pbody');
    body.innerHTML=a.notes.map(n=>`<div class="note plain" style="margin-bottom:8px"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><path d="M12 8v5M12 16h.01"/></svg><div>${esc(n).replace(/\n/g,'<br>')}</div></div>`).join('');
    p.appendChild(body);wrap.appendChild(p);
  }
  // rosters (rival Brendan/May battles filtered by the chosen gender + starter)
  const rn=rivalName(), rs=rivalStarter();
  a.rosters.forEach(r=>{
    if(r.kind==='rematch')return;
    const trainers=r.trainers.filter(t=>{
      if(t.choice&&PROFILE.starter&&t.choice!==PROFILE.starter)return false;   // starter-variant battle
      if(!isRivalTrainer(t))return true;
      if(rn&&rivalGenderOf(t.name)!==rn)return false;
      if(rs&&rivalStarterOf(t.team)!==rs)return false;
      return true;
    });
    if(!trainers.length)return;
    const track=r.kind!=='rematch';
    const doneN=track?trainers.filter(t=>TRAINERS_DONE.has(t.id)).length:0;
    const p=el('div','panel'+(r.kind==='gauntlet'?' gauntlet':'')+(r.optional?' optroster':''));
    const gicon=r.kind==='gauntlet'?`<span class="gicon" title="A gauntlet: back-to-back fights with no healing in between">⚔</span> `:'';
    const otag=r.optional?`<span class="optpill big" title="Optional — you can skip this whole group; it doesn't block the area">optional</span>`:'';
    const rtag=r.reward?`<span class="rewardpill" title="What clearing this gauntlet gets you">🎁 ${esc(r.reward)}</span>`:'';
    const gnote=r.note?`<div class="gauntnote">${esc(r.note)}</div>`:'';
    p.innerHTML=`<div class="phead"><h3>${gicon}${esc(r.title)}</h3>${otag}${rtag}<span class="sub">${track&&doneN?`<span class="subcaught">✓ ${doneN}/${trainers.length} beaten</span>`:`${trainers.length} trainer${trainers.length===1?'':'s'}`}</span></div>${gnote}`;
    const body=el('div','pbody');
    body.innerHTML=trainers.map(t=>{
        let tag='';const rival=isRivalTrainer(t);
        if(rival){const g=rivalGenderOf(t.name),st=rivalStarterOf(t.team);
          tag=(rn&&rs&&g===rn&&st===rs)?` <span class="rivalpill" title="Your rival, based on your gender & starter">★ Your rival</span>`:` <span class="varpill">${esc(g)} · ${esc(st)}</span>`;}
        if(t.choice&&!PROFILE.starter)tag+=` <span class="varpill">if ${esc(t.choice)}</span>`;
        if(t.split)tag+=` <span class="varpill" title="You fight this on a later visit here, during the ${esc(t.split)}">${esc(t.split)}</span>`;
        if(t.b2b&&r.kind!=='gauntlet')tag+=` <span class="b2bpill" title="${esc(t.b2b)}">⚔ back-to-back</span>`;
        if(t.optional&&r.kind!=='gauntlet')tag+=` <span class="optpill" title="Optional — skippable; doesn't block this area from counting as done">optional</span>`;
        if(t.reward)tag+=` <span class="rewardpill" title="Beating this trainer gives you this">🎁 ${esc(t.reward)}</span>`;
        const done=track&&TRAINERS_DONE.has(t.id);
        const chk=track?`<button class="tcheck catch" data-trainer="${esc(t.id)}" aria-pressed="${done}" title="${done?'Beaten — click to unmark':'Mark as beaten'}"></button>`:'';
        const tnote=arr(t.notes).length?`<div class="tnote">${t.notes.map(esc).join('<br>')}</div>`:'';
        const badge=t.badge?` <span class="badgepill" title="${t.badge==='C'?'Champion rematch':'Available after '+t.badge+' badge(s)'}">${esc(t.badge)}</span>`:'';
        const team=arr(t.team);
        const tcell=(fn)=>team.map(m=>`<td>${fn(m)}</td>`).join('');
        const hasItem=team.some(m=>m.item), hasAb=team.some(m=>m.ability), hasNat=team.some(m=>m.nature);
        const detail=`<div class="tblwrap"><table class="data teamsheet">`+
          `<tr><th>Pokémon</th>${tcell(m=>`<div class="tsmon${isMon(m.species)?' monlink':''}"${monAttr(m.species)}>${spriteByName(m.species,60,'tsspr')}<div class="tsname">${esc(m.species)}</div></div>`)}</tr>`+
          `<tr><th>Level</th>${tcell(m=>`<span class="mono">${esc(m.level)}</span>`)}</tr>`+
          (hasItem?`<tr><th>Held Item</th>${tcell(m=>m.item?`<span class="tsitem">${itemSpriteImg(m.item)}${esc(m.item)}</span>`:'<span class="faint">—</span>')}</tr>`:'')+
          (hasAb?`<tr><th>Ability</th>${tcell(m=>m.ability?esc(m.ability):'<span class="faint">—</span>')}</tr>`:'')+
          (hasNat?`<tr><th>Nature</th>${tcell(m=>m.nature?esc(m.nature):'<span class="faint">—</span>')}</tr>`:'')+
          `<tr><th>Moves</th>${tcell(m=>arr(m.moves).map(mv=>`<div class="tsmove movelink" data-move="${esc(mv)}" role="button" tabindex="0"${moveTypeBg(mv)}>${esc(mv)}${moveChgMark(mv)}</div>`).join('')||'<span class="faint">—</span>')}</tr>`+
          `</table></div>`;
        return `<details class="trainer${done?' tdone':''}${rival?' rivalrow':''}${t.optional?' optrow':''}"><summary><span class="tsumhead">${chk}<span class="tname">${esc(t.name)}${badge}${tag}</span></span>${tnote}<div class="tpreview">${teamInline(t.team)}</div></summary><div class="tdetail">${detail}</div></details>`;
      }).join('');
    p.appendChild(body);wrap.appendChild(p);
  });
  // special battles
  a.special.forEach(s=>{
    const p=el('div','panel');
    p.innerHTML=`<div class="phead"><h3>${esc(s.title)}</h3><span class="sub">Detailed team</span></div>`;
    const body=el('div','pbody');
    body.innerHTML=`<div class="tblwrap"><table class="data"><thead><tr><th>Pokémon</th><th>Lv</th><th>Item</th><th>Ability</th><th>Moves</th></tr></thead><tbody>`+
      s.team.map(m=>`<tr><td><span class="monname${isMon(m.name)?' monlink':''}"${monAttr(m.name)}>${spriteByName(m.name,26,'cspr')}<b>${esc(m.name)}</b></span></td><td class="mono">${esc(m.level)}</td><td>${esc(m.item)}</td><td>${esc(m.ability)}</td><td>${arr(m.moves).map(mv=>`<span class="chip movelink" data-move="${esc(mv)}" role="button" tabindex="0"${moveTypeBg(mv)}>${esc(mv)}${moveChgMark(mv)}</span>`).join(' ')}</td></tr>`).join('')+
      `</tbody></table></div>`;
    p.appendChild(body);wrap.appendChild(p);
  });
  // items obtainable here (documented item-ball swaps) — tick as picked up
  if(arr(a.items).length){
    const items=a.items, doneN=items.filter(it=>ITEMS_DONE.has(it.id)).length;
    const p=el('div','panel');
    p.innerHTML=`<div class="phead"><h3>Items</h3><span class="sub">${doneN?`<span class="subcaught">✓ ${doneN}/${items.length} picked up</span>`:`${items.length} item${items.length===1?'':'s'}`}</span></div>`;
    const body=el('div','pbody');
    body.innerHTML=`<div class="tblwrap"><table class="data"><tbody>`+
      items.map(it=>{const done=ITEMS_DONE.has(it.id);
        return `<tr class="${done?'tdone':''}"><td style="width:1%"><button class="tcheck catch" data-item="${esc(it.id)}" aria-pressed="${done}" title="${done?'Picked up — click to unmark':'Mark as picked up'}"></button></td><td>${itemSpriteImg(it.name)}<b>${esc(it.name)}</b></td></tr>`;
      }).join('')+
      `</tbody></table></div>`;
    p.appendChild(body);wrap.appendChild(p);
  }
  return wrap;
}
function teamInline(team){
  return '<div class="team">'+team.map(m=>`<span class="tmon${isMon(m.species)?' monlink':''}"${monAttr(m.species)}>${spriteByName(m.species,20,'cspr')}${esc(m.species)}${m.level!=null?`<span class="lv">${m.level}</span>`:''}</span>`).join('')+'</div>';
}

/* ================= MOVES ================= */
let movesChangedOnly=false;
function renderMoves(c){
  c.appendChild(collapsibleAbout('moves',RAW.attacks.meta));
  const q=state.query.toLowerCase().trim();
  const all=Object.keys(MOVE_INFO).map(k=>MOVE_INFO[k]);
  const changedCount=all.filter(m=>m.chg).length;
  let list=all.slice();
  if(movesChangedOnly)list=list.filter(m=>m.chg);
  if(q)list=list.filter(m=>(m.n||'').toLowerCase().includes(q)||(m.t||'').toLowerCase().includes(q)||(m.c||'').toLowerCase().includes(q));
  list.sort((a,b)=>(a.n||'').localeCompare(b.n||''));
  // toolbar: changed-only filter + count
  const bar=el('div','moves-toolbar');
  bar.innerHTML=`<label class="chgtoggle"><input type="checkbox"${movesChangedOnly?' checked':''}><span>Changed only</span><span class="cnt">${changedCount}</span></label><span class="moves-count">${list.length} move${list.length===1?'':'s'}</span>`;
  bar.querySelector('input').onchange=e=>{movesChangedOnly=e.target.checked;render();};
  c.appendChild(bar);
  if(!list.length){c.insertAdjacentHTML('beforeend',emptyState('No moves match your search.'));return;}
  const rows=list.map(mi=>{
    const tcol=TYPE_COLORS[mi.t]||'var(--surface-3)';
    return `<tr class="movelink moverow${mi.chg?' changed':''}" data-move="${esc(mi.n)}" role="button" tabindex="0" title="View ${esc(mi.n)}">`+
      `<td class="mv-name">${mi.chg?'<span class="chgmark" title="Changed in this hack" aria-label="changed in this hack"></span>':''}<b>${esc(mi.n)}</b></td>`+
      `<td>${mi.t?`<span class="mv-type" style="background:${tcol}">${esc(mi.t)}</span>`:'—'}</td>`+
      `<td><span class="mv-cat mv-cat-${(mi.c||'').toLowerCase()}">${esc(mi.c||'—')}</span></td>`+
      `<td class="mono num">${mi.pow==null?'—':mi.pow}</td>`+
      `<td class="mono num">${mi.acc==null?'—':mi.acc}</td>`+
      `<td class="mono num">${mi.pp==null?'—':mi.pp}</td>`+
    `</tr>`;
  }).join('');
  const wrap=el('div','panel');
  wrap.innerHTML=`<div class="tblwrap"><table class="data moves-tbl"><thead><tr><th>Move</th><th>Type</th><th>Cat.</th><th class="num">Pow</th><th class="num">Acc</th><th class="num">PP</th></tr></thead><tbody>${rows}</tbody></table></div>`;
  c.appendChild(wrap);
}

/* ============ generic block docs (Evolution / Items / Gifts) ============ */
function cellWithMon(cell){
  const c=String(cell==null?'':cell).trim();
  if(isMon(c))return `${spriteByName(c,20,'cspr')}<span class="monlink celllink" data-mon="${esc(c)}" role="button" tabindex="0">${esc(c)}</span>`;
  const ci=c.lastIndexOf(',');
  if(ci>=0){const tail=c.slice(ci+1).trim();if(tail&&isMon(tail))return `${esc(c.slice(0,ci+1))} ${spriteByName(tail,20,'cspr')}<span class="monlink celllink" data-mon="${esc(tail)}" role="button" tabindex="0">${esc(tail)}</span>`;}
  const ic=itemSpriteImg(c);
  return (ic?ic:'')+esc(c);
}
function renderBlocks(c,doc,id,q){
  const blocks=arr(doc.blocks);
  const ql=(q||'').toLowerCase().trim();
  let any=false;
  let cur=null; // current heading wrapper
  const flush=()=>{if(cur&&cur._has)c.appendChild(cur.node);cur=null;};
  blocks.forEach(b=>{
    if(b.type==='heading'){
      flush();
      const node=el('div');
      node.innerHTML=`<div class="section-head"><h3>${esc(b.text)}</h3></div>`;
      cur={node,_has:false};
      return;
    }
    let html='',matched=false;
    if(b.type==='table'){
      const cols=arr(b.columns),rows=normRows(b.rows);
      const frows=ql?rows.filter(r=>r.join(' ').toLowerCase().includes(ql)):rows;
      if(!frows.length)return;
      matched=frows.some(r=>!ql||r.join(' ').toLowerCase().includes(ql));
      html=`<div class="panel"><div class="tblwrap"><table class="data"><thead><tr>${cols.map(x=>`<th>${esc(x)}</th>`).join('')}</tr></thead><tbody>`+
        frows.map(r=>`<tr>${r.map((cell,i)=>`<td${/^\d|^Lv|^¥|^\-\s*\d/.test(cell)?' class="mono"':''}>${cellWithMon(cell)}</td>`).join('')}</tr>`).join('')+
        `</tbody></table></div></div>`;
    } else if(b.type==='prose'){
      const paras=arr(b.paragraphs);
      if(ql && !paras.join(' ').toLowerCase().includes(ql))return;
      html=`<div class="panel"><div class="pbody prose">${paras.map(p=>`<p>${esc(p)}</p>`).join('')}</div></div>`;matched=true;
    } else if(b.type==='chips'){
      const items=arr(b.items).filter(x=>!ql||x.toLowerCase().includes(ql));
      if(!items.length)return;
      html=`<div class="panel"><div class="pbody"><div class="chips">${items.map(x=>`<span class="chip">${esc(x)}</span>`).join('')}</div></div></div>`;matched=true;
    }
    if(!html)return;
    any=true;
    if(cur){cur.node.insertAdjacentHTML('beforeend',html);cur._has=true;}
    else c.insertAdjacentHTML('beforeend',html);
  });
  flush();
  if(!any)c.insertAdjacentHTML('beforeend',emptyState('Nothing matches your search.'));
}
function renderEvolution(c){c.appendChild(collapsibleAbout('evolution',RAW.evolution.meta));renderBlocks(c,RAW.evolution,'evolution',state.query);}
function renderItems(c){c.appendChild(collapsibleAbout('items',RAW.items.meta));renderBlocks(c,RAW.items,'items',state.query);}
function renderGifts(c){c.appendChild(collapsibleAbout('gifts',RAW.gifts.meta));renderBlocks(c,RAW.gifts,'gifts',state.query);}

/* ================= THIEF ================= */
function thiefNote(n){return `<div class="note plain" style="margin-top:10px;font-size:12.5px"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><path d="M12 8v5M12 16h.01"/></svg><div>${esc(n)}</div></div>`;}
function monCell(nameStr){
  const tokens=String(nameStr).split(/\s*[,\/]\s*/).filter(Boolean);
  return `<span class="team">`+tokens.map(tok=>isMon(tok)
    ?`<span class="tmon monlink"${monAttr(tok)}>${spriteByName(tok,20,'cspr')}${esc(tok)}</span>`
    :`<span class="tmon">${esc(tok)}</span>`).join('')+`</span>`;
}
function thiefTable(title,sub,c1,c2,bodyRows){
  return `<div class="panel" style="margin-bottom:18px"><div class="phead"><h3>${esc(title)}</h3>${sub?`<span class="sub">${esc(sub)}</span>`:''}</div>`+
    `<div class="pbody"><div class="tblwrap"><table class="data thief-tbl"><thead><tr><th>${esc(c1)}</th><th>${esc(c2)}</th></tr></thead><tbody>${bodyRows}</tbody></table></div></div></div>`;
}
function renderThief(c){
  const t=RAW.thief, q=state.query.toLowerCase().trim();
  const hit=s=>!q||String(s).toLowerCase().includes(q);
  const titleHit=s=>q&&s.toLowerCase().includes(q);

  if(!q && t.intro){
    c.insertAdjacentHTML('beforeend',`<div class="panel" style="margin-bottom:18px"><div class="pbody prose"><div class="eyebrow" style="margin-bottom:8px">How thieving works</div><p>${esc(t.intro)}</p>${t.earlyNote?thiefNote(t.earlyNote):''}</div></div>`);
  }

  // Learn early
  const early=arr(t.earlyLearn).filter(r=>hit(r.name+' '+r.detail));
  if(early.length){
    c.insertAdjacentHTML('beforeend',thiefTable('Learn Thief / Covet early','Steal before you even get the TM','Pokémon','How',
      early.map(r=>`<tr><td class="tname">${monCell(r.name)}</td><td class="titem">${esc(r.detail)}</td></tr>`).join('')));
  }

  // Gym-stage grid
  const grid=el('div','thief-grid');
  arr(t.stages).forEach(s=>{
    let rows=arr(s.rows);
    const showAll=!q||titleHit(s.title);
    if(!showAll)rows=rows.filter(r=>hit(r.name+' '+r.item));
    const notes=showAll?arr(s.notes):arr(s.notes).filter(hit);
    if(q && !showAll && !rows.length && !notes.length)return;
    let bodyHtml='';
    if(rows.length)bodyHtml+=`<div class="tblwrap"><table class="data thief-tbl"><tbody>${rows.map(r=>`<tr><td class="tname">${monCell(r.name)}</td><td class="titem">${itemSpriteImg(r.item)}${esc(r.item)}</td></tr>`).join('')}</tbody></table></div>`;
    notes.forEach(n=>bodyHtml+=thiefNote(n));
    if(!rows.length&&!notes.length)bodyHtml=`<div style="color:var(--muted);font-size:13px">Nothing new to steal here.</div>`;
    const p=el('div','panel thief-card');
    p.innerHTML=`<div class="phead"><h3>${esc(s.title)}</h3>${rows.length?`<span class="sub">${rows.length} item${rows.length===1?'':'s'}</span>`:''}</div><div class="pbody">${bodyHtml}</div>`;
    grid.appendChild(p);
  });
  if(grid.children.length)c.appendChild(grid);

  // Contest prizes
  if(t.contest){
    const rows=arr(t.contest.rows).filter(r=>hit(r.name+' '+r.item));
    if(rows.length)c.insertAdjacentHTML('beforeend',thiefTable('Contest Prizes',t.contest.subtitle,'Contest rank','Items you can win',
      rows.map(r=>`<tr><td class="tname"><b>${esc(r.name)}</b></td><td class="titem">${esc(r.item)}</td></tr>`).join('')));
  }
  // Mega stones
  if(t.mega){
    const rows=arr(t.mega.rows).filter(r=>hit((r.name||'')+' '+r.detail));
    if(rows.length)c.insertAdjacentHTML('beforeend',thiefTable('Mega Stones','Available after the Groudon / Kyogre storyline — not sold in shops','Stone','Where to find',
      rows.map(r=>`<tr><td class="tname"><b>${esc(r.name)}</b></td><td class="titem">${esc(r.detail)}</td></tr>`).join('')));
  }
  // Extra tips
  if(!q){
    const gn=arr(t.generalNotes);
    if(gn.length)c.insertAdjacentHTML('beforeend',`<div class="panel"><div class="phead"><h3>Extra tips</h3></div><div class="pbody">${gn.map(thiefNote).join('')}</div></div>`);
  }

  if(!c.querySelector('.panel'))c.insertAdjacentHTML('beforeend',emptyState('No thief entries match your search.'));
}

/* ================= BOX ================= */
function renderBox(c){
  const seenDex=new Set();
  const caught=PK.filter(p=>CAUGHT.has(p.dex)&&!seenDex.has(p.dex)&&(seenDex.add(p.dex),true));
  if(!caught.length){c.insertAdjacentHTML('beforeend',emptyState('Your box is empty. Tick a species’ box in the Areas tab to add it here.'));return;}
  const q=state.query.toLowerCase().trim();
  const items=q?caught.filter(p=>p._s.includes(q)):caught;
  c.insertAdjacentHTML('beforeend',`<div class="areabar"><span class="caughtcount"><b>${caught.length}</b> Pokémon in your box${q?` · ${items.length} shown`:''}</span></div>`);
  if(!items.length){c.insertAdjacentHTML('beforeend',emptyState('No caught Pokémon match your search.'));return;}
  const grid=el('div','boxgrid');
  items.forEach(p=>{
    const b=el('button','boxcard monlink');b.dataset.mon=p.name;b.setAttribute('role','button');
    b.innerHTML=`${spriteImg(p.dex,64,'boxspr')}<span class="bxname">${esc(p.name)}</span><span class="bxdex">#${esc(p.dex)}</span>`;
    grid.appendChild(b);
  });
  c.appendChild(grid);
}

/* ================= misc ================= */
function emptyState(msg){return `<div class="empty"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.2-3.2"/></svg><div>${esc(msg)}</div></div>`;}

/* ---- cross-link: click a Pokémon anywhere -> open its entry ---- */
function gotoPokemon(name){
  const dex=NAME2DEX[normName(name)];if(!dex)return;
  const idx=PK.findIndex(p=>p.dex===dex);if(idx<0)return;
  state.section='pokemon';state.query='';$('search').value='';state.pkSel=idx;
  render();history.replaceState(null,'','#pokemon');
  requestAnimationFrame(()=>{window.scrollTo(0,0);const a=document.querySelector('.mlist .litem.active');if(a)a.scrollIntoView({block:'center'});});
}
function gotoArea(name){
  const idx=AREA2IDX[normName(name)];if(idx==null)return;
  state.section='areas';state.query='';$('search').value='';state.areaSel=idx;state.areaInit=true;
  render();history.replaceState(null,'','#areas');
  requestAnimationFrame(()=>{window.scrollTo(0,0);const a=document.querySelector('.mlist .litem.active');if(a)a.scrollIntoView({block:'center'});});
}
// render an "Obtain" location string, linking evolve-from Pokémon and known areas
function locHtml(loc){
  if(!loc)return '';
  const ev=/^Evolve\s+(.+?)(\s*\(.*\))?$/.exec(loc);
  if(ev&&isMon(ev[1]))return `Evolve <span class="loclink monlink" data-mon="${esc(ev[1])}" role="button" tabindex="0" title="View ${esc(ev[1])}">${esc(ev[1])}</span>${ev[2]?esc(ev[2]):''}`;
  return loc.split(',').map(part=>{
    const p=part.trim();
    return AREA2IDX[normName(p)]!=null?`<span class="loclink arealink" data-area="${esc(p)}" role="button" tabindex="0" title="Go to ${esc(p)}">${esc(p)}</span>`:esc(p);
  }).join(', ');
}
const contentEl=$('content');
function reRenderKeepScroll(){const ml=document.querySelector('.mlist');const sc=ml?ml.scrollTop:0;render();const ml2=document.querySelector('.mlist');if(ml2)ml2.scrollTop=sc;}
contentEl.addEventListener('click',e=>{
  const tc=e.target.closest('.tcheck');
  if(tc){e.preventDefault();e.stopPropagation();if(tc.dataset.item!=null)toggleItem(tc.dataset.item);else toggleTrainer(tc.dataset.trainer);reRenderKeepScroll();return;}
  const cb=e.target.closest('.catch');
  if(cb){e.preventDefault();e.stopPropagation();toggleCaught(cb.dataset.catch);reRenderKeepScroll();return;}
  const bg=e.target.closest('.badgechip');
  if(bg){e.preventDefault();const g=GYMS.find(x=>(gymBadgeKey(x)||gymKey(x.name))===bg.dataset.badge);if(g){const ids=gymLeaderIds(g);
    if(badgeEarned(g))ids.forEach(id=>TRAINERS_DONE.delete(id));else if(ids.length)TRAINERS_DONE.add(ids[0]);
    saveTrainers();}reRenderKeepScroll();return;}
  const mb=e.target.closest('.missbtn');
  if(mb){e.preventDefault();toggleMissed(mb.dataset.miss);reRenderKeepScroll();return;}
  const wb=e.target.closest('.collapsebtn');
  if(wb){e.preventDefault();wildOpen[wb.dataset.wild]=!(wb.dataset.open==='true');reRenderKeepScroll();return;}
  const mv=e.target.closest('.movelink');
  if(mv&&mv.dataset.move){e.preventDefault();openMove(mv.dataset.move);return;}
  const al=e.target.closest('.arealink');
  if(al&&al.dataset.area){e.preventDefault();gotoArea(al.dataset.area);return;}
  const t=e.target.closest('.monlink');
  if(t&&t.dataset.mon){e.preventDefault();openMon(t.dataset.mon);}
});
contentEl.addEventListener('keydown',e=>{
  if(e.key!=='Enter'&&e.key!==' ')return;
  if(e.target.closest('.catch'))return; // native button click handles it
  const mv=e.target.closest('.movelink');
  if(mv&&mv.dataset.move){e.preventDefault();openMove(mv.dataset.move);return;}
  const al=e.target.closest('.arealink');
  if(al&&al.dataset.area){e.preventDefault();gotoArea(al.dataset.area);return;}
  const t=e.target.closest('.monlink');
  if(t&&t.dataset.mon){e.preventDefault();openMon(t.dataset.mon);}
});

/* ---- search wiring (debounced) ---- */
let sT;
$('search').addEventListener('input',e=>{clearTimeout(sT);sT=setTimeout(()=>{state.query=e.target.value;render();},120);});

/* ---- theme ---- */
function applyTheme(t){document.documentElement.setAttribute('data-theme',t);$('themelabel').textContent=t==='dark'?'Dark':'Light';$('themebtn').firstElementChild.innerHTML=t==='dark'?ICONS.sun.replace(/<svg[^>]*>|<\/svg>/g,''):'<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8Z"/>';try{localStorage.setItem('rrss-theme',t);}catch(e){}}
(function initTheme(){let t;try{t=localStorage.getItem('rrss-theme');}catch(e){}if(!t)t=matchMedia('(prefers-color-scheme:dark)').matches?'dark':'light';applyTheme(t);})();
$('themebtn').onclick=()=>{const cur=document.documentElement.getAttribute('data-theme')==='dark'?'light':'dark';applyTheme(cur);};

/* ---- mobile menu ---- */
function closeMenu(){$('sidebar').classList.remove('open');$('scrim').classList.remove('show');}
$('menutoggle').onclick=()=>{$('sidebar').classList.add('open');$('scrim').classList.add('show');};
$('scrim').onclick=closeMenu;

/* ---- init from hash ---- */
(function(){const h=location.hash.replace('#','');if(SECTIONS.find(s=>s.id===h))state.section=h;render();})();