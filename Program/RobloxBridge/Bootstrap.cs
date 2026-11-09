using System.Collections.Concurrent;
using System.Net;
using System.Text;
using System.Text.Json;
using WLO;
using WLO.Math;

namespace RobloxBridge;

public static class Bootstrap{
    private static WLO.Web.WebView2 WebView = null!;
    private static WLO.Window.GLFW  Window  = null!;

    // Все сообщения в Web идут через очередь: PostMessage вызывается только из главного потока.
    private static readonly ConcurrentQueue<string> __PendingMessages = [];

    private static HttpListener?            __Listener;
    private static CancellationTokenSource? __ListenerCts;
    private static volatile bool            __IsRunning   = false;
    private static volatile int             __CurrentPort = 4949;

    private static volatile PlaceInfo? __CreateRequest = null; // запрос на создание проекта от плагина
    private static volatile bool       __DialogOpen    = false;

    private static volatile string? __PendingTitle = null;

    private static DateTime __LastPingTime        = DateTime.MinValue;
    private static DateTime __LastPingBadgeUpdate = DateTime.MinValue;

    [STAThread]
    public static int Main(string[] Args){
        try{
            WL.Core.Start(Args);

            Settings.Load();
            __CurrentPort = Settings.Port;

            WebView = WLO.Web.WebView2.Create();

            Window = new WLO.Window.GLFW(new Vector2I(900, 600), "RobloxBridge", WebView);
            Window.TODO_UseDarkMode();

            WebView.OnMessage += __OnWebMessage;

            WebView.NavigateCustom(Web.HTML.Replace("{{JS}}", Web.JS));

            while(!Window.IsClosed){
                Window.PollEvents();
                Window.PollEvents2();

                while(__PendingMessages.TryDequeue(out string? Pending)){
                    WebView.PostMessage(Pending);
                }

                string? TitleToApply = Interlocked.Exchange(ref __PendingTitle, null);
                if(TitleToApply != null){
                    Window.Title = TitleToApply;
                }

                __UpdatePingBadgeIfNeeded();
            }

            __StopServer();
            Window.Close();
        }catch(Exception e){
            WL.Logger.Fatal("RobloxBridge взорвался...", e);

            return WL.Core.Stop(1);
        }

        return WL.Core.Stop(0);
    }

    // ----------------------------------------------------------------------
    // Сообщения от Web

    private static void __OnWebMessage(string Message){
        try{
            using JsonDocument Doc = JsonDocument.Parse(Message);
            string Type = Doc.RootElement.GetProperty("Type").GetString() ?? "";

            switch(Type){
                case "Ready":
                    __TryReopenLastProject();
                    __SendStatus();
                    __SendProject();
                    __UpdateWindowTitle();
                    __EnqueueLog("RobloxBridge готов к запуску.", "Info");
                    break;

                case "StartServer":{
                    JsonElement DataEl = Doc.RootElement.GetProperty("Data");
                    int Port = DataEl.TryGetProperty("Port", out JsonElement PortEl) ? PortEl.GetInt32() : 4949;
                    __StartServer(Port);
                    break;
                }

                case "StopServer":
                    __StopServer();
                    break;

                case "OpenProject":
                    if(Project.IsOpen || __DialogOpen){ break; }

                    __PickFolder("Выберите папку проекта RobloxBridge", Folder => {
                        if(Folder != null){ __OpenFolder(Folder); }
                    });
                    break;

                case "CloseProject":
                    __CloseProject();
                    break;

                default:
                    WL.Logger.Warn($"Получено неизвестное сообщение от Web, Тип: {Type}");
                    break;
            }
        }catch(Exception e){
            __SendError($"Не удалось обработать сообщение от Web!\nСообщение: {Message}", e);
        }
    }

    // ----------------------------------------------------------------------
    // Проект

    /// Диалог выбора папки в отдельном STA-потоке. OnPicked вызывается из этого потока, Folder == null при отмене.
    private static void __PickFolder(string Title, Action<string?> OnPicked){
        if(__DialogOpen){ return; }
        __DialogOpen = true;

        Thread T = new(() => {
            string? Picked = null;

            try{
                Picked = FolderDialog.Pick(Title);
            }catch(Exception e){
                WL.Logger.Error("Ошибка диалога выбора папки.", e);
            }finally{
                __DialogOpen = false;
            }

            OnPicked(Picked);
        });

        T.SetApartmentState(ApartmentState.STA);
        T.IsBackground = true;
        T.Start();
    }

    private static void __OpenFolder(string Folder){
        if(!Project.TryOpen(Folder, out string Error)){
            __ShowError("Не удалось открыть проект", Error);
            return;
        }

        Settings.LastProject = Project.Current!.Dir;
        __SendProject();
        __UpdateWindowTitle();
        __EnqueueLog($"Проект открыт: {Project.Current.Data.Name} ({Project.Current.Dir})", "Info");
    }

    private static void __CloseProject(){
        if(!Project.IsOpen){ return; }

        string Name = Project.Current!.Data.Name;

        Project.Close();
        Settings.LastProject = null;

        __SendProject();
        __UpdateWindowTitle();
        __EnqueueLog($"Проект закрыт: {Name}", "Info");
    }

    private static void __TryReopenLastProject(){
        string? Last = Settings.LastProject;
        if(Project.IsOpen || Last == null){ return; }

        if(Project.TryOpen(Last, out string Error)){
            __EnqueueLog($"Открыт последний проект: {Project.Current!.Data.Name}", "Info");
        }else{
            Settings.LastProject = null;
            __EnqueueLog($"Последний проект недоступен: {Error}", "Error");
        }
    }

    /// Плагин просит создать проект: спрашиваем папку и создаём bridge.json.
    private static void __BeginCreate(PlaceInfo Info){
        if(__CreateRequest != null || __DialogOpen){ return; }

        __CreateRequest = Info;
        __SendProject();
        __EnqueueLog($"Плагин просит создать проект для плейса «{Info.PlaceName}» (PlaceId {Info.PlaceId}). Выберите папку.", "Info");

        __PickFolder("Выберите папку для нового проекта (можно создать новую)", Folder => {
            __CreateRequest = null;

            if(Folder == null){
                __EnqueueLog("Создание проекта отменено.", "Info");
            }else if(Project.TryCreate(Folder, Info, out string Error)){
                Settings.LastProject = Project.Current!.Dir;
                __EnqueueLog($"Проект создан: {Project.Current.Data.Name} ({Project.Current.Dir})", "Info");
            }else{
                __ShowError("Не удалось создать проект", Error);
            }

            __SendProject();
            __UpdateWindowTitle();
        });
    }

    // ----------------------------------------------------------------------
    // Сервер

    private static void __StartServer(int Port){
        if(__IsRunning){
            __EnqueueLog("Сервер уже запущен.", "Error");
            return;
        }

        try{
            __Listener = new HttpListener();
            __Listener.Prefixes.Add($"http://localhost:{Port}/");
            __Listener.Start();

            __ListenerCts = new CancellationTokenSource();
            CancellationToken Token = __ListenerCts.Token;

            __IsRunning    = true;
            __CurrentPort  = Port;
            __LastPingTime = DateTime.MinValue;

            Settings.Port = Port;

            __UpdateWindowTitle();
            __SendStatus();
            __EnqueueLog($"Сервер запущен на порту {Port}.", "Info");

            Task.Run(() => __ListenLoop(__Listener, Token));
        }catch(Exception e){
            WL.Logger.Error($"Не удалось запустить сервер на порту {Port}!", e);
            __EnqueueLog($"Не удалось запустить сервер на порту {Port}: {e.Message}", "Error");
            __IsRunning = false;
            __SendStatus();
        }
    }

    private static void __StopServer(){
        if(!__IsRunning){ return; }

        try{
            __ListenerCts?.Cancel();
            __Listener?.Stop();
            __Listener?.Close();
        }catch(Exception e){
            WL.Logger.Warn("Ошибка при остановке сервера.", e);
        }finally{
            __Listener    = null;
            __ListenerCts = null;
            __IsRunning   = false;

            __UpdateWindowTitle();
            __SendStatus();
            __EnqueueLog("Сервер остановлен.", "Info");
        }
    }

    private static void __ListenLoop(HttpListener Listener, CancellationToken Token){
        while(!Token.IsCancellationRequested){
            HttpListenerContext Context;

            try{
                IAsyncResult Result = Listener.BeginGetContext(null, null);
                int Index = WaitHandle.WaitAny([Result.AsyncWaitHandle, Token.WaitHandle]);

                if(Index == 1){ break; }

                Context = Listener.EndGetContext(Result);
            }catch(Exception){
                break;
            }

            __HandleRequest(Context);
        }
    }

    private static void __HandleRequest(HttpListenerContext Context){
        int    Code;
        string Body;

        try{
            (Code, Body) = __Route(Context.Request);
        }catch(Exception e){
            WL.Logger.Error("Ошибка при обработке запроса.", e);
            __EnqueueLog($"Ошибка при обработке запроса: {e.Message}", "Error");

            Code = 500;
            Body = JsonSerializer.Serialize(new{ error = e.Message });
        }

        try{
            byte[] Buffer = Encoding.UTF8.GetBytes(Body);

            Context.Response.StatusCode      = Code;
            Context.Response.ContentType     = "application/json";
            Context.Response.ContentLength64 = Buffer.Length;
            Context.Response.OutputStream.Write(Buffer, 0, Buffer.Length);
            Context.Response.OutputStream.Close();
        }catch(Exception e){
            WL.Logger.Warn("Не удалось отправить ответ.", e);
        }
    }

    private static (int Code, string Body) __Route(HttpListenerRequest Request){
        string Route = Request.Url?.AbsolutePath ?? "";

        // /ping не логируем, чтобы не засорять лог
        if(Route == "/ping"){
            __LastPingTime = DateTime.Now;

            long.TryParse(Request.QueryString["place"],    out long PlaceId);
            long.TryParse(Request.QueryString["universe"], out long UniverseId);

            return (200, JsonSerializer.Serialize(new{
                status   = "ok",
                project  = Project.Current?.Data.Name,
                creating = __CreateRequest != null,
                place    = Project.IsOpen ? Project.CheckPlace(PlaceId, UniverseId) : null
            }));
        }

        __EnqueueLog($"{Request.HttpMethod} {Route}", "Request");

        switch(Route){
            case "/project/create":{
                if(Request.HttpMethod != "POST"){
                    return (405, """{"error":"Нужен POST"}""");
                }

                if(Project.IsOpen){
                    return (409, """{"error":"Проект уже открыт"}""");
                }

                using StreamReader Reader = new(Request.InputStream, Encoding.UTF8);

                PlaceInfo? Info = JsonSerializer.Deserialize<PlaceInfo>(
                    Reader.ReadToEnd(),
                    new JsonSerializerOptions{ PropertyNameCaseInsensitive = true }
                );

                if(Info == null){
                    return (400, """{"error":"Пустой запрос"}""");
                }

                __BeginCreate(Info);
                return (200, """{"status":"waiting"}""");
            }

            default:
                return (404, """{"error":"Not Found"}""");
        }
    }

    // ----------------------------------------------------------------------
    // Отправка в Web

    private static void __Post(string Type, object Data){
        __PendingMessages.Enqueue(JsonSerializer.Serialize(new{ Type, Data }));
    }

    private static void __SendStatus(){
        __Post("ServerStatus", new{ Running = __IsRunning, Port = __CurrentPort });
    }

    private static void __SendProject(){
        ProjectHandle? P = Project.Current;

        __Post("ProjectState", new{
            Open     = P != null,
            Name     = P?.Data.Name,
            Path     = P?.Dir,
            Creating = __CreateRequest != null
        });
    }

    private static void __EnqueueLog(string Text, string Kind){
        __Post("LogMessage", new{ Text, Time = DateTime.Now.ToString("HH:mm:ss"), Kind });
    }

    private static void __ShowError(string Title, string Details){
        __Post("Error", new{ Title, Details });
    }

    private static void __SendError(string Message, Exception e){
        WL.Logger.Error(Message, e);
        __ShowError(Message, e.ToString());
    }

    private static void __UpdateWindowTitle(){
        string Name = Project.Current?.Data.Name ?? "нет проекта";
        string Port = __IsRunning ? $"[:{__CurrentPort}]" : "[остановлен]";

        __PendingTitle = $"RobloxBridge, {Name} {Port}";
    }

    private static void __UpdatePingBadgeIfNeeded(){
        if(!__IsRunning){ return; }

        if((DateTime.Now - __LastPingBadgeUpdate).TotalMilliseconds < 500){ return; }
        __LastPingBadgeUpdate = DateTime.Now;

        long Seconds = __LastPingTime == DateTime.MinValue
            ? -1 // пинга ещё не было
            : (long)(DateTime.Now - __LastPingTime).TotalSeconds;

        __Post("PingUpdate", new{ Seconds });
    }
}