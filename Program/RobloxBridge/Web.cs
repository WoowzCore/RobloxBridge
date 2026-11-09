namespace RobloxBridge;

public static class Web{
    // language=JS
    public static string JS = """
const El = Id => document.getElementById(Id);
let IsRunning = false;

function ShowError(Title, Details){
    El("ErrorTitle").textContent   = Title;
    El("ErrorDetails").textContent = Details ?? "";
    El("ErrorOverlay").style.display = "flex";
}

El("ErrorClose").onclick = () => { El("ErrorOverlay").style.display = "none"; };
window.onerror = (Msg, Src, Line, Col, Err) => ShowError("Ошибка JavaScript", `${Msg}\n${Src}:${Line}:${Col}\n${Err?.stack ?? ""}`);
window.addEventListener("unhandledrejection", E => ShowError("Ошибка Promise", String(E.reason?.stack ?? E.reason)));

function SendToHost(Type, Data){
    if(!window.chrome?.webview){
        ShowError("Нет связи с приложением", `Сообщение [${Type}] не отправлено.`);
        return;
    }

    window.chrome.webview.postMessage(JSON.stringify({ Type, Data }));
}

const Handlers = {
    ServerStatus(D){
        IsRunning = D.Running;

        El("StatusBadge").textContent = D.Running ? `● Запущен на порту ${D.Port}` : "● Остановлен";
        El("StatusBadge").className   = D.Running ? "Running" : "Stopped";

        El("Btn-StartStop").textContent = D.Running ? "⏹ Остановить" : "▶ Запустить";
        El("Btn-StartStop").classList.toggle("Active", D.Running);

        El("Input-Port").value    = D.Port;
        El("Input-Port").disabled = D.Running;

        El("PingBadge").textContent = "";
    },

    PingUpdate(D){
        El("PingBadge").textContent = D.Seconds < 0 ? "Клиент: ждём..." : `Клиент: ${D.Seconds} с назад`;
    },

    ProjectState(D){
        if(D.Open){
            El("ProjectName").textContent = `${D.Name}  (игра ${D.UniverseId})`;
            El("ProjectPath").textContent = D.Path;

            const Lines = Object.entries(D.Places).map(([Id, Folder]) => `${Id}  →  Places/${Folder}`);
            El("ProjectPlaces").textContent = Lines.length ? Lines.join("\n") : "Плейсов пока нет, добавьте из плагина.";
        }else{
            El("ProjectName").textContent   = D.Creating ? "Плагин создаёт проект, выберите папку в диалоге..." : "Проект не открыт";
            El("ProjectPath").textContent   = "Откройте проект или создайте новый из плагина в Roblox Studio.";
            El("ProjectPlaces").textContent = "";
        }

        El("Btn-Project").textContent  = D.Open ? "Закрыть проект" : "📂 Открыть проект";
        El("Btn-Project").disabled     = D.Creating;
        El("Btn-Project").dataset.open = D.Open ? "1" : "";
    },

    LogMessage(D){
        const Row = document.createElement("div");
        Row.className = "LogEntry " + (D.Kind ?? "");
        Row.textContent = `${D.Time}  ${D.Text}`;

        const List = El("LogList");
        List.append(Row);
        while(List.children.length > 500){ List.firstChild.remove(); }

        El("LogWrapper").scrollTop = El("LogWrapper").scrollHeight;
    },

    Error(D){
        ShowError(D.Title ?? "Ошибка", D.Details ?? "");
    }
};

Handlers.DumpState = function(D){
  document.getElementById("DumpBar").className = "dump-" + D.State;
  document.getElementById("DumpText").textContent = D.Message;
  var Sub = [];
  if(D.State == "missing" || D.State == "broken"){
    Sub.push("1) «Скачать на GitHub» → 2) на странице кнопка Download raw file (⬇) → 3) «Выбрать файл…». Пока файла нет, работа заблокирована.");
  }
  if(D.Path){ Sub.push(D.Path); }
  if(D.Classes){ Sub.push("классов " + D.Classes + ", свойств " + D.Props + ", хеш " + D.Hash); }
  if(D.DumpStudio){ Sub.push("принят для Studio " + D.DumpStudio); }
  if(D.Studio){ Sub.push("сейчас Studio " + D.Studio); }
  document.getElementById("DumpSub").textContent = Sub.join(" · ");
};
El("DumpGit").onclick  = () => SendToHost("OpenDumpPage");
El("DumpPick").onclick = () => SendToHost("PickDump");

El("Btn-StartStop").onclick = () => {
    if(IsRunning){ SendToHost("StopServer"); return; }

    let Port = parseInt(El("Input-Port").value, 10);
    if(!Number.isFinite(Port) || Port < 1){ Port = 4949; }
    if(Port > 65535){ Port = 65535; }
    El("Input-Port").value = Port;

    SendToHost("StartServer", { Port });
};

El("Btn-Project").onclick  = () => SendToHost(El("Btn-Project").dataset.open ? "CloseProject" : "OpenProject");
El("Btn-ClearLog").onclick = () => El("LogList").replaceChildren();

if(window.chrome?.webview){
    window.chrome.webview.addEventListener("message", Event => {
        try{
            const Msg = typeof Event.data === "string" ? JSON.parse(Event.data) : Event.data;
            Handlers[Msg?.Type]?.(Msg.Data);
        }catch(e){
            ShowError("Не удалось обработать сообщение от C#", e.message + "\n" + Event.data);
        }
    });

    SendToHost("Ready");
}else{
    ShowError("Нет связи с приложением", "Страница запущена не внутри WebView2.");
}
""";

    // language=HTML
    public static string HTML = """
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<title>RobloxBridge</title>
<style>
*{ box-sizing:border-box; margin:0; padding:0; }
html, body{ height:100%; background:#121212; color:#e0e0e0; font:14px "Segoe UI", sans-serif; overflow:hidden; }
#App{ display:flex; flex-direction:column; height:100vh; }

.Bar{ display:flex; align-items:center; gap:12px; padding:10px 16px; background:#1a1a1a; border-bottom:1px solid #2a2a2a; }
.Bar h1{ font-size:16px; margin-right:auto; }

#StatusBadge.Running{ color:#66ff66; }
#StatusBadge.Stopped{ color:#9a9a9a; }
#PingBadge{ color:#6a9fd8; font-size:12px; }

input, button{ font:inherit; color:#fff; border:none; border-radius:4px; padding:6px 12px; }
input{ background:#0f0f0f; border:1px solid #333; width:80px; }
input:disabled{ opacity:.5; }
button{ background:#333; cursor:pointer; }
button:hover{ background:#444; }
button:disabled{ opacity:.5; cursor:not-allowed; }
#Btn-StartStop{ background:#2e7d32; }
#Btn-StartStop.Active{ background:#c62828; }

#ProjectInfo{ flex:1; min-width:0; }
#ProjectName{ font-weight:600; }
#ProjectPath{ font-size:12px; color:#8a8a8a; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
#ProjectPlaces{ font:12px Consolas, monospace; color:#9a9a9a; white-space:pre; margin-top:4px; }

#LogWrapper{ flex:1; overflow-y:auto; padding:8px 16px; }
.LogEntry{ font:12px Consolas, monospace; padding:2px 6px; white-space:pre-wrap; color:#9a9a9a; }
.LogEntry.Request{ color:#8ab4e8; }
.LogEntry.Error{ color:#ff8888; }

#ErrorOverlay{ display:none; position:fixed; inset:0; background:rgba(0,0,0,.75); align-items:center; justify-content:center; z-index:10; }
#ErrorBox{ background:#2a1111; border:1px solid #c00; border-radius:6px; padding:16px 20px; max-width:600px; max-height:70vh; display:flex; flex-direction:column; gap:10px; }
#ErrorTitle{ color:#f66; font-size:15px; }
#ErrorDetails{ color:#e0b0b0; font-size:12px; white-space:pre-wrap; overflow-y:auto; }
#ErrorClose{ align-self:flex-end; background:#c00; }

#DumpBar{display:flex;align-items:center;gap:8px;padding:8px 12px;border-bottom:1px solid #333}
#DumpBar .Grow{flex:1;min-width:0}
#DumpBar .Sub{font-size:11px;opacity:.7;word-break:break-all}
#DumpBar.dump-missing,#DumpBar.dump-broken{background:#4a1f1f}
#DumpBar.dump-outdated,#DumpBar.dump-newer{background:#4a3d12}
#DumpBar.dump-ok{background:#1d3a24}
#DumpBar.dump-checking{background:#2a2a2a}
</style>
</head>
<body>
<div id="App">
    <div class="Bar">
        <h1>RobloxBridge</h1>
        <span id="StatusBadge" class="Stopped">● Остановлен</span>
        <span id="PingBadge"></span>
        <input type="number" id="Input-Port" min="1" max="65535" value="4949">
        <button id="Btn-StartStop">▶ Запустить</button>
        <button id="Btn-ClearLog">Очистить лог</button>
    </div>

    <div id="DumpBar" class="dump-missing">
        <div class="Grow"><div id="DumpText"></div><div id="DumpSub" class="Sub"></div></div>
        <button id="DumpGit">Скачать на GitHub</button>
        <button id="DumpPick">Выбрать файл…</button>
    </div>

    <div class="Bar">
        <div id="ProjectInfo">
            <div id="ProjectName">Проект не открыт</div>
            <div id="ProjectPath"></div>
            <div id="ProjectPlaces"></div>
        </div>
        <button id="Btn-Project">📂 Открыть проект</button>
    </div>

    <div id="LogWrapper"><div id="LogList"></div></div>
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
}