namespace RobloxBridge;

public static class Web{

    // language=html
    public const string HTML = """
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<title>RobloxBridge</title>
<style>
:root{
    --bg:#12141a; --panel:#1a1d25; --bg3:#252a35; --bd:#2b303c;
    --tx:#e8eaf0; --mu:#8a92a3;
    --ac:#4c8dff; --gr:#3ecf8e; --rd:#ff5d6c; --am:#f5a524;
}
*{ box-sizing:border-box; }
[hidden]{ display:none !important; }
html,body{ margin:0; height:100%; background:var(--bg); color:var(--tx); font:13px/1.45 "Segoe UI",system-ui,sans-serif; overflow:hidden; }
::-webkit-scrollbar{ width:10px; height:10px; }
::-webkit-scrollbar-thumb{ background:#343a48; border-radius:6px; border:2px solid transparent; background-clip:padding-box; }
::-webkit-scrollbar-track{ background:transparent; }

button{ font:inherit; color:var(--tx); background:var(--bg3); border:1px solid var(--bd); border-radius:8px; padding:7px 12px; cursor:pointer; transition:background .12s,border-color .12s; }
button:hover:not(:disabled){ background:#2f3441; border-color:#3a4050; }
button:disabled{ opacity:.4; cursor:default; }
button.primary{ background:var(--ac); border-color:var(--ac); color:#fff; }
button.primary:hover:not(:disabled){ background:#6aa0ff; border-color:#6aa0ff; }
button.good{ background:var(--gr); border-color:var(--gr); color:#08150f; }
button.good:hover:not(:disabled){ background:#5fe0a6; border-color:#5fe0a6; }
button.danger{ background:#3a2026; border-color:#6b2b36; color:#ffb3bb; }
input[type=number]{ font:inherit; color:var(--tx); background:var(--bg); border:1px solid var(--bd); border-radius:8px; padding:6px 8px; width:84px; }
input[type=number]:focus{ outline:none; border-color:var(--ac); }
input[type=checkbox]{ accent-color:var(--ac); width:15px; height:15px; margin:0; }
label{ cursor:pointer; user-select:none; }

#App{ display:flex; flex-direction:column; height:100%; }

header{ display:flex; align-items:center; gap:10px; padding:10px 14px; background:var(--panel); border-bottom:1px solid var(--bd); }
.Brand{ font-size:16px; font-weight:700; letter-spacing:.2px; margin-right:6px; }
.Grow{ flex:1; min-width:0; }
.Pill{ display:inline-flex; align-items:center; gap:6px; padding:3px 10px; border-radius:20px; font-size:12px; background:var(--bg3); color:var(--mu); border:1px solid var(--bd); white-space:nowrap; }
.Pill::before{ content:""; width:8px; height:8px; border-radius:50%; background:var(--mu); }
.Pill.ok{ color:#b9f3d8; border-color:#245a43; background:#15271f; }
.Pill.ok::before{ background:var(--gr); box-shadow:0 0 6px var(--gr); }
.Pill.warn{ color:#ffd999; border-color:#6a4d14; background:#2a2212; }
.Pill.warn::before{ background:var(--am); }
.Pill.bad{ color:#ffb3bb; border-color:#6b2b36; background:#2a1519; }
.Pill.bad::before{ background:var(--rd); }
.PortBox{ display:flex; align-items:center; gap:6px; color:var(--mu); }

main{ flex:1; min-height:0; display:grid; grid-template-columns:300px 1fr; gap:12px; padding:12px; }
aside{ display:flex; flex-direction:column; gap:12px; min-height:0; overflow:auto; }
#Work{ display:flex; flex-direction:column; gap:12px; min-height:0; min-width:0; }

.Card{ background:var(--panel); border:1px solid var(--bd); border-radius:10px; padding:12px; }
.Title{ font-size:11px; font-weight:700; letter-spacing:.8px; text-transform:uppercase; color:var(--mu); margin-bottom:8px; }
.Row2{ display:flex; gap:8px; margin-top:10px; }
.Row2 button{ flex:1; }
.Sub{ color:var(--mu); font-size:12px; word-break:break-all; }

#PrjName{ font-size:15px; font-weight:600; }
#PrjPath{ color:var(--mu); font-size:12px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.Places{ margin-top:8px; display:flex; flex-direction:column; gap:3px; font-size:12px; }
.Places div{ display:flex; justify-content:space-between; gap:8px; background:var(--bg); border-radius:6px; padding:3px 8px; }
.Places span:first-child{ color:var(--mu); }

#DumpCard{ border-left:4px solid var(--mu); }
#DumpCard.dump-ok{ border-left-color:var(--gr); }
#DumpCard.dump-checking{ border-left-color:var(--ac); }
#DumpCard.dump-outdated,#DumpCard.dump-newer{ border-left-color:var(--am); }
#DumpCard.dump-missing,#DumpCard.dump-broken{ border-left-color:var(--rd); background:#221619; }
#DumpState{ font-weight:600; margin-bottom:2px; }

#SyncCard .Acts, #TerrainCard .Acts{ display:flex; gap:8px; }
.Act[hidden]{ display:none; }
.Act{ flex:1; display:flex; flex-direction:column; align-items:flex-start; gap:1px; padding:10px 12px; text-align:left; }
.Act b{ font-size:14px; font-weight:600; }
.Act small{ opacity:.7; font-size:11px; }
.Auto{ display:flex; align-items:center; gap:8px; margin-top:10px; }
.Hint{ margin-top:8px; padding:6px 10px; border-radius:6px; background:var(--bg); color:var(--mu); font-size:12px; }
.Hint.warn{ background:#2a2212; color:#ffd999; }
.Hint.busy{ background:#13233d; color:#a9c8ff; }

.Fill{ flex:1; min-height:0; display:flex; flex-direction:column; padding:0; overflow:hidden; }
.Tabs{ display:flex; align-items:center; gap:4px; padding:8px 10px; border-bottom:1px solid var(--bd); }
.Tab{ background:none; border:0; color:var(--mu); padding:6px 12px; }
.Tab.on{ background:var(--bg3); color:var(--tx); }
.Badge{ background:var(--rd); color:#fff; border-radius:9px; padding:0 6px; font-size:11px; margin-left:6px; }
.Pane{ flex:1; min-height:0; display:flex; flex-direction:column; }

#DiffHead{ padding:10px 14px; border-bottom:1px solid var(--bd); }
#DiffText{ font-weight:600; }
#DiffText.err{ color:#ff8c98; } #DiffText.warn{ color:#ffd18a; } #DiffText.ok{ color:#8fe6bd; }
.Chips{ display:flex; gap:8px; margin-top:6px; flex-wrap:wrap; }
.Chip{ padding:1px 9px; border-radius:12px; font-size:12px; font-weight:600; }
.Chip.Add{ background:#15271f; color:var(--gr); } .Chip.Mod{ background:#2a2212; color:var(--am); } .Chip.Del{ background:#2a1519; color:var(--rd); }
.Mono{ font:12px/1.5 Consolas,"Cascadia Mono",monospace; white-space:pre; }
#DiffList{ flex:1; overflow:auto; padding:8px 14px; }
.Empty{ color:var(--mu); padding:24px 14px; text-align:center; }

.Add{ color:var(--gr); } .Del{ color:var(--rd); } .Mod{ color:var(--am); } .Skip{ color:#6d7586; } .Warn{ color:#ff9f43; } .Note{ color:#8a92a3; }

.LogTools{ display:flex; align-items:center; gap:14px; padding:7px 14px; border-bottom:1px solid var(--bd); color:var(--mu); }
.LogTools label{ display:flex; align-items:center; gap:6px; }
.LogTools button{ margin-left:auto; padding:3px 10px; }
#LogList{ flex:1; overflow:auto; padding:6px 14px; }
.LogRow{ display:flex; gap:10px; font:12px/1.5 Consolas,"Cascadia Mono",monospace; }
.LogRow .T{ color:#5d6578; flex:none; }
.LogRow .X{ white-space:pre-wrap; word-break:break-word; min-width:0; }
.LogRow.Error .X{ color:#ff8c98; }
.LogRow.Request .X{ color:#6d7586; }
#LogList:not(.show-req) .LogRow.Request{ display:none; }
#LogList.only-err .LogRow:not(.Error){ display:none; }

#ErrorOverlay{ position:fixed; inset:0; background:rgba(0,0,0,.6); display:none; align-items:center; justify-content:center; padding:24px; z-index:10; }
#ErrorOverlay.on{ display:flex; }
#ErrorBox{ background:var(--panel); border:1px solid #6b2b36; border-radius:12px; padding:16px; max-width:760px; width:100%; max-height:90%; display:flex; flex-direction:column; gap:10px; }
#ErrorTitle{ font-size:15px; font-weight:700; color:#ff8c98; }
#ErrorDetails{ margin:0; overflow:auto; background:var(--bg); border-radius:8px; padding:10px; font:12px/1.5 Consolas,monospace; white-space:pre-wrap; word-break:break-word; }
#ErrorBox button{ align-self:flex-end; }

button.Act.pull, button.Act.push { color: #fff; border-color: transparent; }
button.Act.pull { background: #2d69be; }
button.Act.push { background: #28914f; }
button.Act.pull:hover:not(:disabled) { background: #3a7ad4; }
button.Act.push:hover:not(:disabled) { background: #32a65e; }
button.Act.pull:disabled, button.Act.push:disabled { opacity: .45; }
.Act b { font-size: 14px; }
.Act small { display: block; font-size: 11px; font-weight: 400; opacity: .85; }
</style>
</head>
<body>
<div id="App">

    <header>
        <div class="Brand">RobloxBridge</div>
        <span id="ServerPill" class="Pill">Сервер остановлен</span>
        <span id="PluginPill" class="Pill">Плагин: нет связи</span>
        <div class="Grow"></div>
        <label class="PortBox">Порт <input type="number" id="Port" min="1" max="65535" value="4949"></label>
        <button id="BtnServer" class="primary">▶ Запустить</button>
    </header>

    <main>
        <aside>
            <section class="Card" id="ProjectCard">
                <div class="Title">Проект</div>
                <div id="PrjName">Проект не открыт</div>
                <div id="PrjPath"></div>
                <div id="PrjMeta" class="Sub"></div>
                <div id="PrjPlaces" class="Places"></div>
                <div class="Row2">
                    <button id="BtnOpen" class="primary">📂 Открыть проект</button>
                    <button id="BtnClose" class="danger" hidden>Закрыть проект</button>
                </div>
                <div style="margin-top:8px"><button id="BtnAgents" style="width:100%">📄 Создать AGENTS.md</button></div>
            </section>

            <section class="Card" id="DumpCard">
                <div class="Title">API-дамп Roblox</div>
                <div id="DumpState">…</div>
                <div id="DumpMsg" class="Sub"></div>
                <div id="DumpSub" class="Sub"></div>
                <div class="Row2">
                    <button id="DumpPick">Выбрать файл…</button>
                    <button id="DumpGit">GitHub</button>
                </div>
            </section>
        </aside>

        <section id="Work">
            <section class="Card" id="SyncCard">
                <div class="Title">Синхронизация</div>
                <div class="Acts">
                    <button id="BtnPull" class="Act pull"><b>Studio → файлы</b><small>Pull · сохранить</small></button>
                    <button id="BtnPush" class="Act push"><b id="BtnPushT">Файлы → Studio</b><small id="BtnPushS">Push · применить</small></button>
                    <button id="BtnApply" class="Act"><b>✔ Применить</b><small id="BtnApplyS">после предпросмотра</small></button>
                    <button id="BtnUndo" class="Act"><b>↩ Отменить</b><small>последнее применение</small></button>
                </div>
                <label class="Auto"><input type="checkbox" id="AutoApply"> Применять сразу после проверки (без второго клика)</label>
                <div id="SyncHint" class="Hint"></div>
            </section>
            
            <section class="Card" id="TerrainCard">
                <div class="Title">Террейн</div>
                <div class="Acts">
                    <button id="BtnTPull" class="Act pull"><b>Studio → файл</b><small>Террейн · сохранить</small></button>
                    <button id="BtnTPush" class="Act push"><b>Файл → Studio</b><small>Террейн · предпросмотр</small></button>
                </div>
                <div class="Acts" style="margin-top:8px">
                    <button id="BtnTApply" class="Act" hidden><b>✔ Применить террейн</b><small>после предпросмотра</small></button>
                    <button id="BtnTUndo" class="Act" hidden><b>↩ Отменить террейн</b><small>последнее применение</small></button>
                </div>
                <div class="Hint">Область задаётся в плагине (карточка «Террейн»). Перед применением сохраните плейс. Push террейна всегда с предпросмотром.</div>
            </section>

            <section class="Card Fill">
                <div class="Tabs">
                    <button class="Tab on" data-tab="Diff">Изменения</button>
                    <button class="Tab" data-tab="Log">Лог<span id="ErrBadge" class="Badge" hidden></span></button>
                </div>

                <div id="PaneDiff" class="Pane">
                    <div id="DiffHead" hidden>
                        <div id="DiffText"></div>
                        <div id="DiffChips" class="Chips"></div>
                    </div>
                    <div id="DiffList" class="Mono"><div class="Empty">Здесь появится результат Pull/Push: что создастся, изменится, удалится.</div></div>
                </div>

                <div id="PaneLog" class="Pane" hidden>
                    <div class="LogTools">
                        <label><input type="checkbox" id="ShowReq"> Запросы</label>
                        <label><input type="checkbox" id="OnlyErr"> Только ошибки</label>
                        <button id="BtnClearLog">Очистить</button>
                    </div>
                    <div id="LogList"></div>
                </div>
            </section>
        </section>
    </main>
</div>

<div id="ErrorOverlay">
    <div id="ErrorBox">
        <div id="ErrorTitle">Ошибка</div>
        <pre id="ErrorDetails"></pre>
        <button id="ErrorClose">Закрыть</button>
    </div>
</div>

<script>
{{JS}}
</script>
</body>
</html>
""";

    // language=js
    public const string JS = """
(function(){
'use strict';

const $ = id => document.getElementById(id);

const S = {
    running:false, port:4949,
    project:null, ping:-1, dump:null,
    sync:{ text:'', kind:'', lines:[], canApply:false, canUndo:false },
    waiting:null,      // { label }
    auto:false,        // идёт цепочка «предпросмотр → применить»
    conn:false
};
let WaitT = 0, AutoStarted = false, ErrUnread = 0, Tab = 'Diff';

const LS = {
    get(k, d){ try{ const v = localStorage.getItem(k); return v === null ? d : v; }catch(e){ return d; } },
    set(k, v){ try{ localStorage.setItem(k, v); }catch(e){} }
};

// ---------------------------------------------------------------- связь с C#

function send(Type, Data){
    try{ window.chrome.webview.postMessage(JSON.stringify({ Type: Type, Data: Data || {} })); }
    catch(e){ console.error(e); }
}

function onHost(e){
    let m = e.data;
    for(let i = 0; i < 2 && typeof m === 'string'; i++){ try{ m = JSON.parse(m); }catch(x){ return; } }
    if(!m || !m.Type){ return; }
    const f = H[m.Type];
    if(f){ f(m.Data || {}); }
}

// ---------------------------------------------------------------- обработчики сообщений

const H = {
    ServerStatus(D){
        S.running = !!D.Running;
        S.port = D.Port;
        if(document.activeElement !== $('Port')){ $('Port').value = D.Port; }
        renderServer(); renderPing(true);
        if(!AutoStarted){
            AutoStarted = true;
            if(!S.running){ send('StartServer', { Port: parseInt($('Port').value, 10) || 4949 }); }
        }
    },

    ProjectState(D){ S.project = D; renderProject(); renderSync(); },

    DumpState(D){ S.dump = D; renderDump(); renderSync(); },

    PingUpdate(D){ S.ping = D.Seconds; renderPing(false); },

    LogMessage(D){ addLog(D); },

    Error(D){ showError(D.Title || 'Ошибка', D.Details || ''); },

    SyncResult(D){
        S.tApply = !!D.tApply; S.tUndo = !!D.tUndo; renderTerrain();
        S.sync = {
            text:     D.text || '',
            kind:     String(D.kind || ''),
            lines:    Array.isArray(D.lines) ? D.lines : [],
            canApply: !!D.canApply,
            canUndo:  !!D.canUndo
        };
        renderDiff();
        if(S.sync.text || S.sync.lines.length){ showTab('Diff'); }

        if(S.waiting){
            if(S.auto && S.sync.canApply){
                S.auto = false;
                wait('Применяю изменения', 20000);
                cmd('apply');
                return;
            }
            if(S.auto){
                // ждём итог: промежуточные «Проверяю…» игнорируем
                const t = S.sync.text + ' ' + S.sync.kind;
                if(/ошиб|error|warn|изменений нет|не изменил|отмен|создастся 0, изменится 0, удалится 0/i.test(t)){
                    S.auto = false; done();
                }
                return;
            }
            done();
        }
        renderSync();
    }
};

// ---------------------------------------------------------------- команды синхронизации

function cmd(c){ send('SyncCmd', { Cmd: c }); }

function wait(label, ms){
    S.waiting = { label: label };
    clearTimeout(WaitT);
    WaitT = setTimeout(() => { S.waiting = null; S.auto = false; renderSync(); }, ms);
    renderSync();
}

function done(){
    clearTimeout(WaitT);
    S.waiting = null;
    renderSync();
}

function doPull(){
    S.auto = false;
    S.sync.canApply = false;
    wait('Pull', 20000);
    cmd('pull');
}

function doPush(){
    S.auto = $('AutoApply').checked;
    S.sync.canApply = false;
    wait(S.auto ? 'Push (проверка и применение)' : 'Предпросмотр', S.auto ? 45000 : 20000);
    cmd('preview');
}

function doApply(){
    S.auto = false;
    wait('Применяю изменения', 20000);
    cmd('apply');
}

function doUndo(){
    S.auto = false;
    wait('Отменяю', 20000);
    cmd('undo');
}

// ---------------------------------------------------------------- отрисовка

function ready(){
    if(!S.running){ return 'Сервер остановлен. Нажмите «Запустить».'; }
    if(S.dump && S.dump.Blocking){ return 'Нужен файл дампа API. Выберите его слева.'; }
    const P = S.project;
    if(!P || !P.Open){
        return P && P.Creating ? 'Выберите папку для нового проекта в открывшемся диалоге.'
                               : 'Откройте проект (папку с bridge.json). Новый проект создаётся из плагина в Studio.';
    }
    if(!(S.ping >= 0 && S.ping <= 9)){ return 'Плагин не отвечает. Откройте Studio с плейсом этого проекта и проверьте, что плагин установлен.'; }
    return '';
}

function renderServer(){
    const p = $('ServerPill');
    p.className = 'Pill ' + (S.running ? 'ok' : 'bad');
    p.textContent = S.running ? 'Сервер :' + S.port : 'Сервер остановлен';
    $('BtnServer').textContent = S.running ? '■ Остановить' : '▶ Запустить';
    $('BtnServer').className = S.running ? '' : 'primary';
    $('Port').disabled = S.running;
}

function renderPing(force){
    const p = $('PluginPill');
    let cls = '', txt = '';
    if(!S.running){ cls = '';     txt = 'Плагин: —'; }
    else if(S.ping < 0){ cls = 'bad';  txt = 'Плагин: нет связи'; }
    else if(S.ping <= 9){ cls = 'ok';   txt = 'Плагин на связи'; }
    else{ cls = 'warn'; txt = 'Плагин молчит ' + S.ping + ' с'; }
    p.className = 'Pill ' + cls;
    p.textContent = txt;

    const c = S.running && S.ping >= 0 && S.ping <= 9;
    if(force || c !== S.conn){ S.conn = c; renderSync(); }
}

function renderProject(){
    const P = S.project || { Open:false };
    $('PrjName').textContent = P.Open ? P.Name : (P.Creating ? 'Создаётся проект…' : 'Проект не открыт');
    $('PrjPath').textContent = P.Open ? P.Path : '';
    $('PrjPath').title = P.Open ? P.Path : '';
    $('PrjMeta').textContent = P.Open ? 'Игра (UniverseId): ' + P.UniverseId
                                      : (P.Creating ? 'Плагин просит создать проект' : 'Откройте папку с bridge.json');
    const box = $('PrjPlaces');
    box.textContent = '';
    if(P.Open){
        const E = Object.entries(P.Places || {});
        if(E.length === 0){
            const d = document.createElement('div'); d.textContent = 'Плейсов пока нет'; box.appendChild(d);
        }
        for(const [id, folder] of E){
            const d = document.createElement('div');
            const a = document.createElement('span'); a.textContent = 'Плейс ' + id;
            const b = document.createElement('span'); b.textContent = 'Places/' + folder;
            d.appendChild(a); d.appendChild(b); box.appendChild(d);
        }
    }
    $('BtnOpen').hidden = !!P.Open;
    $('BtnOpen').disabled = !!P.Creating;
    $('BtnClose').hidden = !P.Open;
}

const DumpNames = { ok:'✔ Совместим', checking:'… Проверяется', outdated:'⚠ Устарел', newer:'⚠ Новее Studio', missing:'✖ Не выбран', broken:'✖ Не подходит' };

function renderDump(){
    const D = S.dump;
    if(!D){ return; }
    $('DumpCard').className = 'Card dump-' + D.State;
    $('DumpState').textContent = DumpNames[D.State] || D.State;
    $('DumpMsg').textContent = D.Message || '';
    const parts = [];
    if(D.Path){ parts.push(D.Path.split(/[\\/]/).pop()); }
    if(D.Classes){ parts.push('классов ' + D.Classes + ', свойств ' + D.Props); }
    if(D.Studio){ parts.push('Studio ' + D.Studio); }
    if(D.Diff){ parts.push(D.Diff); }
    $('DumpSub').textContent = parts.join(' · ');
    $('DumpSub').title = D.Path || '';
}

function renderSync(){
    const why = ready(), ok = !why, busy = !!S.waiting, A = $('AutoApply').checked;

    $('BtnPull').disabled  = !ok || busy;
    $('BtnPush').disabled  = !ok || busy;
    $('BtnPushT').textContent = 'Файлы → Studio';
    $('BtnPushS').textContent = 'Push · ' + (A ? 'применить сразу' : 'сначала предпросмотр');

    const canApply = ok && !busy && S.sync.canApply;
    $('BtnApply').disabled = !canApply;
    $('BtnApply').className = 'Act' + (canApply ? ' good' : '');
    $('BtnUndo').disabled  = !ok || busy || !S.sync.canUndo;

    const h = $('SyncHint');
    h.className = 'Hint' + (why ? ' warn' : busy ? ' busy' : '');
    if(why){ h.textContent = why; }
    else if(busy){ h.textContent = '⏳ ' + S.waiting.label + '. Плагин забирает команды раз в ~3 с, подождите…'; }
    else if(S.sync.canApply){ h.textContent = 'Изменения проверены. Нажмите «Применить» или сделайте новый Push.'; }
    else{ h.textContent = 'Готово к работе.'; }
}

function lineClass(s){
    if(/^\s/.test(s)){ return 'Note'; }
    if(s.length < 2 || s[1] !== ' '){ return ''; }
    switch(s[0]){
        case '+': return 'Add';
        case '-': case '−': return 'Del';
        case '~': return 'Mod';
        case 'x': return 'Skip';
        case '!': return 'Warn';
    }
    return '';
}

function renderDiff(){
    const Y = S.sync, head = $('DiffHead'), list = $('DiffList');

    let a = 0, m = 0, d = 0;
    for(const l of Y.lines){
        const c = lineClass(l);
        if(c === 'Add'){ a++; } else if(c === 'Mod'){ m++; } else if(c === 'Del'){ d++; }
    }

    head.hidden = !(Y.text || Y.lines.length);
    const t = $('DiffText');
    t.textContent = Y.text;
    t.className = /err/i.test(Y.kind) ? 'err' : /warn/i.test(Y.kind) ? 'warn' : /ok|done/i.test(Y.kind) ? 'ok' : '';

    const chips = $('DiffChips');
    chips.textContent = '';
    const chip = (cls, txt) => { const c = document.createElement('span'); c.className = 'Chip ' + cls; c.textContent = txt; chips.appendChild(c); };
    if(a){ chip('Add', '+' + a + ' создастся'); }
    if(m){ chip('Mod', '~' + m + ' изменится'); }
    if(d){ chip('Del', '−' + d + ' удалится'); }

    $('BtnApplyS').textContent = Y.canApply && (a + m + d) > 0 ? '+' + a + '  ~' + m + '  −' + d : 'после предпросмотра';

    list.textContent = '';
    if(Y.lines.length === 0){
        const e = document.createElement('div');
        e.className = 'Empty';
        e.textContent = Y.text ? 'Подробного списка нет.' : 'Здесь появится результат Pull/Push: что создастся, изменится, удалится.';
        list.appendChild(e);
        return;
    }
    const frag = document.createDocumentFragment();
    for(const l of Y.lines){
        const row = document.createElement('div');
        row.className = lineClass(l);
        row.textContent = l;
        frag.appendChild(row);
    }
    list.appendChild(frag);
}

// ---------------------------------------------------------------- лог

function addLog(D){
    const list = $('LogList');
    const near = list.scrollHeight - list.scrollTop - list.clientHeight < 40;

    const row = document.createElement('div');
    row.className = 'LogRow ' + (D.Kind || 'Info');
    const t = document.createElement('span'); t.className = 'T'; t.textContent = D.Time || '';
    const x = document.createElement('span'); x.className = 'X ' + (D.Kind === 'Info' ? lineClass(D.Text || '') : ''); x.textContent = D.Text || '';
    row.appendChild(t); row.appendChild(x);
    list.appendChild(row);

    while(list.childElementCount > 1500){ list.removeChild(list.firstChild); }
    if(near){ list.scrollTop = list.scrollHeight; }

    if(D.Kind === 'Error' && Tab !== 'Log'){ ErrUnread++; renderBadge(); }
}

function renderBadge(){
    const b = $('ErrBadge');
    b.hidden = ErrUnread === 0;
    b.textContent = ErrUnread;
}

function showTab(name){
    Tab = name;
    document.querySelectorAll('.Tab').forEach(b => b.classList.toggle('on', b.dataset.tab === name));
    $('PaneDiff').hidden = name !== 'Diff';
    $('PaneLog').hidden  = name !== 'Log';
    if(name === 'Log'){
        ErrUnread = 0; renderBadge();
        const l = $('LogList'); l.scrollTop = l.scrollHeight;
    }
}

function showError(title, details){
    $('ErrorTitle').textContent = title;
    $('ErrorDetails').textContent = details;
    $('ErrorOverlay').classList.add('on');
}

// ---------------------------------------------------------------- события интерфейса

$('BtnServer').onclick = () => {
    if(S.running){ send('StopServer'); return; }
    const p = parseInt($('Port').value, 10);
    if(!(p >= 1 && p <= 65535)){ showError('Порт', 'Введите число от 1 до 65535.'); return; }
    send('StartServer', { Port: p });
};
$('Port').addEventListener('keydown', e => { if(e.key === 'Enter' && !S.running){ $('BtnServer').click(); } });

$('BtnOpen').onclick  = () => send('OpenProject');
$('BtnClose').onclick = () => send('CloseProject');
$('DumpPick').onclick = () => send('PickDump');
$('DumpGit').onclick  = () => send('OpenDumpPage');
$('BtnAgents').onclick = () => send('Agents');

function renderTerrain(){
    $('BtnTApply').hidden = !S.tApply;
    $('BtnTUndo').hidden  = !S.tUndo;
}
$('BtnTPull').onclick  = () => cmd('terrain-pull');
$('BtnTPush').onclick  = () => cmd('terrain-push');
$('BtnTApply').onclick = () => cmd('terrain-apply');
$('BtnTUndo').onclick  = () => cmd('terrain-undo');

$('BtnPull').onclick  = doPull;
$('BtnPush').onclick  = doPush;
$('BtnApply').onclick = doApply;
$('BtnUndo').onclick  = doUndo;

$('AutoApply').checked = LS.get('auto', '1') === '1';
$('AutoApply').onchange = () => { LS.set('auto', $('AutoApply').checked ? '1' : '0'); renderSync(); };

document.querySelectorAll('.Tab').forEach(b => b.onclick = () => showTab(b.dataset.tab));

$('ShowReq').checked = LS.get('showReq', '0') === '1';
$('LogList').classList.toggle('show-req', $('ShowReq').checked);
$('ShowReq').onchange = () => { LS.set('showReq', $('ShowReq').checked ? '1' : '0'); $('LogList').classList.toggle('show-req', $('ShowReq').checked); };
$('OnlyErr').onchange = () => $('LogList').classList.toggle('only-err', $('OnlyErr').checked);
$('BtnClearLog').onclick = () => { $('LogList').textContent = ''; ErrUnread = 0; renderBadge(); };

$('ErrorClose').onclick = () => $('ErrorOverlay').classList.remove('on');

// ---------------------------------------------------------------- старт

if(window.chrome && window.chrome.webview){ window.chrome.webview.addEventListener('message', onHost); }
else{ window.addEventListener('message', onHost); }

renderServer(); renderProject(); renderSync(); renderDiff();
send('Ready');

})();
""";
}