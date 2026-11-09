namespace RobloxBridge;

public static class Web{
    // language=JS
    public static string JS = """
const StatusBadge  = document.getElementById("StatusBadge");
const PingBadge    = document.getElementById("PingBadge");
const PortInput    = document.getElementById("Input-Port");
const StartStopBtn = document.getElementById("Btn-StartStop");
const LogList      = document.getElementById("LogList");
const ErrorOverlay = document.getElementById("ErrorOverlay");
const ErrorTitle   = document.getElementById("ErrorTitle");
const ErrorDetails = document.getElementById("ErrorDetails");

let IsRunning = false;

// ----------------------------------------------------------------------

function ShowError(Title, Details){
    ErrorTitle.textContent = Title;
    ErrorDetails.textContent = Details ?? "";
    ErrorOverlay.style.display = "flex";
}

document.getElementById("ErrorClose").onclick = () => {
    ErrorOverlay.style.display = "none";
};

window.onerror = (Message, Source, Line, Column, Error) => {
    ShowError("Необработанная ошибка JavaScript", `${Message}\n${Source}:${Line}:${Column}\n${Error?.stack ?? ""}`);
};

window.addEventListener("unhandledrejection", Event => {
    ShowError("Необработанная ошибка Promise", String(Event.reason?.stack ?? Event.reason));
});

// ----------------------------------------------------------------------

function UpdateStatusUI(Running, Port){
    IsRunning = Running;

    if(Running){
        StatusBadge.textContent = `● Запущен на порту ${Port}`;
        StatusBadge.className = "StatusBadge Running";
        StartStopBtn.textContent = "⏹ Остановить";
        StartStopBtn.classList.add("Active");
        PortInput.disabled = true;
        PingBadge.style.display = "inline-block";
    }else{
        StatusBadge.textContent = "● Остановлен";
        StatusBadge.className = "StatusBadge Stopped";
        StartStopBtn.textContent = "▶ Запустить";
        StartStopBtn.classList.remove("Active");
        PortInput.disabled = false;
        PingBadge.style.display = "none";
        PingBadge.textContent = "";
    }
}

function UpdatePingUI(Ms){
    PingBadge.textContent = `Клиент: ${Ms} мс назад`;
}

function AddLogEntry(Text, Time, Kind){
    const Entry = document.createElement("div");
    Entry.className = "LogEntry" + (Kind ? ` LogEntry-${Kind}` : "");

    const TimeSpan = document.createElement("span");
    TimeSpan.className = "LogTime";
    TimeSpan.textContent = Time;

    const TextSpan = document.createElement("span");
    TextSpan.className = "LogText";
    TextSpan.textContent = Text;

    Entry.appendChild(TimeSpan);
    Entry.appendChild(TextSpan);

    LogList.appendChild(Entry);
    LogList.scrollTop = LogList.scrollHeight;
}

function GetPort(){
    let Value = parseInt(PortInput.value, 10);
    if(!Number.isFinite(Value) || Value < 1){ Value = 4949; }
    if(Value > 65535){ Value = 65535; }
    PortInput.value = Value;
    return Value;
}

StartStopBtn.onclick = () => {
    if(IsRunning){
        SendToHost("StopServer");
    }else{
        SendToHost("StartServer", { Port: GetPort() });
    }
};

document.getElementById("Btn-ClearLog").onclick = () => {
    LogList.innerHTML = "";
};

// ----------------------------------------------------------------------

function SendToHost(Type, Data){
    if(!window.chrome?.webview){
        console.warn(`Нет хоста WebView2, сообщение [${Type}] не отправлено.`);
        ShowError("Нет связи с приложением", `window.chrome.webview недоступен, сообщение [${Type}] не отправлено.`);
        return;
    }
    window.chrome.webview.postMessage(JSON.stringify({ Type, Data }));
}

if(window.chrome?.webview){
    window.chrome.webview.addEventListener("message", Event => {
        let Message = Event.data;

        if(typeof Message === "string"){
            try{
                Message = JSON.parse(Message);
            }catch(e){
                console.error("Не удалось распарсить сообщение от C#:", Event.data, e);
                ShowError("Не удалось распарсить сообщение от C#", e.message + "\n" + Event.data);
                return;
            }
        }

        if(!Message || typeof Message.Type !== "string"){
            console.error("Сообщение от C# не соответствует протоколу { Type, Data }:", Message);
            ShowError("Некорректный формат сообщения от C#", JSON.stringify(Message));
            return;
        }

        if(Message.Type === "ServerStatus"){
            UpdateStatusUI(Message.Data.Running, Message.Data.Port);
        }else if(Message.Type === "PingUpdate"){
            UpdatePingUI(Message.Data.Ms);
        }else if(Message.Type === "LogMessage"){
            AddLogEntry(Message.Data.Text, Message.Data.Time, Message.Data.Kind);
        }else if(Message.Type === "Error"){
            ShowError(Message.Data?.Title ?? "Ошибка", Message.Data?.Details ?? "");
        }
    });

    SendToHost("Ready");
}else{
    console.warn("window.chrome.webview недоступен — страница запущена не внутри WebView2.");
    ShowError("Нет связи с приложением", "window.chrome.webview недоступен. Страница запущена не внутри WebView2.");
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
*{
    box-sizing: border-box;
    margin: 0;
    padding: 0;
}

html, body{
    height: 100%;
    background: #121212;
    color: #e0e0e0;
    font-family: "Segoe UI", sans-serif;
    overflow: hidden;
}

#App{
    display: flex;
    flex-direction: column;
    height: 100vh;
}

#TopBar{
    display: flex;
    align-items: center;
    gap: 16px;
    padding: 16px 20px;
    background: #1a1a1a;
    border-bottom: 1px solid #2a2a2a;
    flex-shrink: 0;
}

#TopBar h1{
    font-size: 18px;
    color: #ffffff;
    margin-right: auto;
}

.StatusBadge{
    font-size: 13px;
    padding: 6px 12px;
    border-radius: 6px;
    font-weight: 600;
}

.StatusBadge.Running{
    background: rgba(76, 175, 80, 0.15);
    color: #66ff66;
}

.StatusBadge.Stopped{
    background: rgba(150, 150, 150, 0.15);
    color: #9a9a9a;
}

#PingBadge{
    font-size: 12px;
    color: #6a9fd8;
    display: none;
}

.TopBarInput{
    background: #0f0f0f;
    border: 1px solid #333333;
    color: #e0e0e0;
    border-radius: 6px;
    padding: 8px 10px;
    font-size: 13px;
    width: 90px;
}

.TopBarInput:focus{
    outline: none;
    border-color: #4fc3f7;
}

.TopBarInput:disabled{
    opacity: 0.5;
}

.TopBarLabel{
    font-size: 12px;
    color: #9a9a9a;
}

.Button{
    background: #333333;
    color: #ffffff;
    border: none;
    border-radius: 6px;
    padding: 8px 16px;
    font-size: 13px;
    font-weight: 600;
    cursor: pointer;
}

.Button:hover{
    background: #444444;
}

.Button.Primary{
    background: #2e7d32;
}

.Button.Primary:hover{
    background: #388e3c;
}

.Button.Primary.Active{
    background: #c62828;
}

.Button.Primary.Active:hover{
    background: #d32f2f;
}

#LogWrapper{
    flex-grow: 1;
    overflow-y: auto;
    padding: 12px 20px;
    display: flex;
    flex-direction: column;
    gap: 4px;
}

.LogEntry{
    display: flex;
    gap: 10px;
    font-family: Consolas, monospace;
    font-size: 12px;
    padding: 4px 8px;
    border-radius: 4px;
}

.LogEntry-Request{
    background: rgba(33, 150, 243, 0.08);
}

.LogEntry-Error{
    background: rgba(204, 0, 0, 0.1);
    color: #ff8888;
}

.LogEntry-Info{
    color: #9a9a9a;
}

.LogTime{
    color: #6a6a6a;
    flex-shrink: 0;
}

.LogText{
    white-space: pre-wrap;
    word-break: break-word;
}

#LogWrapper::-webkit-scrollbar{
    width: 8px;
}

#LogWrapper::-webkit-scrollbar-thumb{
    background: #333333;
    border-radius: 4px;
}

#ErrorOverlay{
    display: none;
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background: rgba(0, 0, 0, 0.75);
    align-items: center;
    justify-content: center;
    z-index: 1000;
}

#ErrorBox{
    background: #2a1111;
    border: 1px solid #cc0000;
    border-radius: 8px;
    padding: 20px 24px;
    max-width: 600px;
    max-height: 70vh;
    display: flex;
    flex-direction: column;
    gap: 12px;
}

#ErrorTitle{
    color: #ff6666;
    font-size: 16px;
}

#ErrorDetails{
    color: #e0b0b0;
    font-size: 12px;
    white-space: pre-wrap;
    word-break: break-word;
    overflow-y: auto;
    max-height: 300px;
}

#ErrorBox button{
    align-self: flex-end;
    background: #cc0000;
    color: #fff;
    border: none;
    border-radius: 6px;
    padding: 6px 14px;
    cursor: pointer;
}

#ErrorBox button:hover{
    background: #e60000;
}
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

    <div id="LogWrapper">
        <div id="LogList"></div>
    </div>

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