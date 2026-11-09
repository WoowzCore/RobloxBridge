namespace RobloxBridge;

public static class Web{
    // language=JS
    public static string JS = """
const El = Id => document.getElementById(Id);

let IsRunning = false;

// ----------------------------------------------------------------------

function ShowError(Title, Details){
    El("ErrorTitle").textContent   = Title;
    El("ErrorDetails").textContent = Details ?? "";
    El("ErrorOverlay").style.display = "flex";
}

El("ErrorClose").onclick = () => { El("ErrorOverlay").style.display = "none"; };

window.onerror = (Message, Source, Line, Column, Err) => {
    ShowError("Необработанная ошибка JavaScript", `${Message}\n${Source}:${Line}:${Column}\n${Err?.stack ?? ""}`);
};

window.addEventListener("unhandledrejection", E => {
    ShowError("Необработанная ошибка Promise", String(E.reason?.stack ?? E.reason));
});

function SendToHost(Type, Data){
    if(!window.chrome?.webview){
        ShowError("Нет связи с приложением", `window.chrome.webview недоступен, сообщение [${Type}] не отправлено.`);
        return;
    }

    window.chrome.webview.postMessage(JSON.stringify({ Type, Data }));
}

// ----------------------------------------------------------------------
// Сообщения от C#

const Handlers = {
    ServerStatus(D){
        IsRunning = D.Running;

        El("StatusBadge").textContent = D.Running ? `● Запущен на порту ${D.Port}` : "● Остановлен";
        El("StatusBadge").className   = "StatusBadge " + (D.Running ? "Running" : "Stopped");

        El("Btn-StartStop").textContent = D.Running ? "⏹ Остановить" : "▶ Запустить";
        El("Btn-StartStop").classList.toggle("Active", D.Running);

        El("Input-Port").value    = D.Port;
        El("Input-Port").disabled = D.Running;

        El("PingBadge").style.display = D.Running ? "inline-block" : "none";
        if(!D.Running){ El("PingBadge").textContent = ""; }
    },

    PingUpdate(D){
        El("PingBadge").textContent = D.Seconds < 0 ? "Клиент: ждём..." : `Клиент: ${D.Seconds} с назад`;
    },

    ProjectState(D){
        if(D.Open){
            El("ProjectName").textContent = D.Name;
            El("ProjectPath").textContent = D.Path;
        }else if(D.Creating){
            El("ProjectName").textContent = "Плагин создаёт проект...";
            El("ProjectPath").textContent = "Выберите папку в открытом диалоге.";
        }else{
            El("ProjectName").textContent = "Проект не открыт";
            El("ProjectPath").textContent = "Откройте существующий проект или создайте новый из плагина в Roblox Studio.";
        }

        El("Btn-Project").textContent = D.Open ? "Закрыть проект" : "📂 Открыть проект";
        El("Btn-Project").disabled    = D.Creating;
        El("Btn-Project").dataset.open = D.Open ? "1" : "";
    },

    LogMessage(D){
        const Entry = document.createElement("div");
        Entry.className = "LogEntry" + (D.Kind ? ` LogEntry-${D.Kind}` : "");

        const Time = document.createElement("span");
        Time.className   = "LogTime";
        Time.textContent = D.Time;

        const Text = document.createElement("span");
        Text.className   = "LogText";
        Text.textContent = D.Text;

        Entry.append(Time, Text);

        const List = El("LogList");
        List.append(Entry);
        while(List.children.length > 500){ List.firstChild.remove(); }

        El("LogWrapper").scrollTop = El("LogWrapper").scrollHeight;
    },

    Error(D){
        ShowError(D.Title ?? "Ошибка", D.Details ?? "");
    }
};

// ----------------------------------------------------------------------
// Кнопки

El("Btn-StartStop").onclick = () => {
    if(IsRunning){
        SendToHost("StopServer");
        return;
    }

    let Port = parseInt(El("Input-Port").value, 10);
    if(!Number.isFinite(Port) || Port < 1){ Port = 4949; }
    if(Port > 65535){ Port = 65535; }
    El("Input-Port").value = Port;

    SendToHost("StartServer", { Port });
};

El("Btn-Project").onclick = () => {
    SendToHost(El("Btn-Project").dataset.open ? "CloseProject" : "OpenProject");
};

El("Btn-ClearLog").onclick = () => { El("LogList").replaceChildren(); };

// ----------------------------------------------------------------------

if(window.chrome?.webview){
    window.chrome.webview.addEventListener("message", Event => {
        try{
            const Msg = typeof Event.data === "string" ? JSON.parse(Event.data) : Event.data;
            const Handler = Handlers[Msg?.Type];

            if(Handler){
                Handler(Msg.Data);
            }else{
                console.warn("Неизвестное сообщение от C#:", Msg);
            }
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

html, body{ height:100%; background:#121212; color:#e0e0e0; font-family:"Segoe UI", sans-serif; overflow:hidden; }

#App{ display:flex; flex-direction:column; height:100vh; }

#TopBar{ display:flex; align-items:center; gap:16px; padding:16px 20px; background:#1a1a1a; border-bottom:1px solid #2a2a2a; flex-shrink:0; }
#TopBar h1{ font-size:18px; color:#fff; margin-right:auto; }

#ProjectBar{ display:flex; align-items:center; gap:16px; padding:12px 20px; background:#161619; border-bottom:1px solid #2a2a2a; flex-shrink:0; }
#ProjectInfo{ flex:1; min-width:0; }
#ProjectName{ font-weight:600; }
#ProjectPath{ font-size:12px; color:#8a8a8a; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }

.StatusBadge{ font-size:13px; padding:6px 12px; border-radius:6px; font-weight:600; }
.StatusBadge.Running{ background:rgba(76,175,80,.15); color:#66ff66; }
.StatusBadge.Stopped{ background:rgba(150,150,150,.15); color:#9a9a9a; }

#PingBadge{ font-size:12px; color:#6a9fd8; display:none; }

.TopBarLabel{ font-size:12px; color:#9a9a9a; }
.TopBarInput{ background:#0f0f0f; border:1px solid #333; color:#e0e0e0; border-radius:6px; padding:8px 10px; font-size:13px; width:90px; }
.TopBarInput:focus{ outline:none; border-color:#4fc3f7; }
.TopBarInput:disabled{ opacity:.5; }

.Button{ background:#333; color:#fff; border:none; border-radius:6px; padding:8px 16px; font-size:13px; font-weight:600; cursor:pointer; }
.Button:hover{ background:#444; }
.Button:disabled{ opacity:.5; cursor:not-allowed; }
.Button.Primary{ background:#2e7d32; }
.Button.Primary:hover{ background:#388e3c; }
.Button.Primary.Active{ background:#c62828; }
.Button.Primary.Active:hover{ background:#d32f2f; }

#LogWrapper{ flex-grow:1; overflow-y:auto; padding:12px 20px; }
#LogList{ display:flex; flex-direction:column; gap:4px; }
.LogEntry{ display:flex; gap:10px; font-family:Consolas, monospace; font-size:12px; padding:4px 8px; border-radius:4px; }
.LogEntry-Request{ background:rgba(33,150,243,.08); }
.LogEntry-Error{ background:rgba(204,0,0,.1); color:#ff8888; }
.LogEntry-Info{ color:#9a9a9a; }
.LogTime{ color:#6a6a6a; flex-shrink:0; }
.LogText{ white-space:pre-wrap; word-break:break-word; }
#LogWrapper::-webkit-scrollbar{ width:8px; }
#LogWrapper::-webkit-scrollbar-thumb{ background:#333; border-radius:4px; }

#ErrorOverlay{ display:none; position:fixed; inset:0; background:rgba(0,0,0,.75); align-items:center; justify-content:center; z-index:1000; }
#ErrorBox{ background:#2a1111; border:1px solid #c00; border-radius:8px; padding:20px 24px; max-width:600px; max-height:70vh; display:flex; flex-direction:column; gap:12px; }
#ErrorTitle{ color:#f66; font-size:16px; }
#ErrorDetails{ color:#e0b0b0; font-size:12px; white-space:pre-wrap; word-break:break-word; overflow-y:auto; max-height:300px; }
#ErrorClose{ align-self:flex-end; background:#c00; color:#fff; border:none; border-radius:6px; padding:6px 14px; cursor:pointer; }
#ErrorClose:hover{ background:#e60000; }
</style>
</head>

<body>
<div id="App">

    <div id="TopBar">
        <h1>RobloxBridge</h1>

        <span class="StatusBadge Stopped" id="StatusBadge">● Остановлен</span>
        <span id="PingBadge"></span>

        <span class="TopBarLabel">Порт:</span>
        <input type="number" id="Input-Port" class="TopBarInput" min="1" max="65535" value="4949">

        <button class="Button Primary" id="Btn-StartStop">▶ Запустить</button>
        <button class="Button" id="Btn-ClearLog">Очистить лог</button>
    </div>

    <div id="ProjectBar">
        <div id="ProjectInfo">
            <div id="ProjectName">Проект не открыт</div>
            <div id="ProjectPath">Откройте существующий проект или создайте новый из плагина в Roblox Studio.</div>
        </div>
        <button class="Button" id="Btn-Project">📂 Открыть проект</button>
    </div>

    <div id="LogWrapper"><div id="LogList"></div></div>

</div>

<div id="ErrorOverlay">
    <div id="ErrorBox">
        <h2 id="ErrorTitle">Ошибка</h2>
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