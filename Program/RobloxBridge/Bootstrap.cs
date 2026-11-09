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

    private static readonly ConcurrentQueue<string> __PendingMessages = [];

    private static HttpListener?            __Listener;
    private static CancellationTokenSource? __ListenerCts;
    private static volatile bool            __IsRunning   = false;
    private static volatile int             __CurrentPort = 4949;

    private static volatile string? __PendingTitle = null;

    private static DateTime __LastPingTime = DateTime.MinValue;

    [STAThread]
    public static int Main(string[] Args){
        try{
            WL.Core.Start(Args);

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

    private static void __OnWebMessage(string Message){
        try{
            using JsonDocument Doc = JsonDocument.Parse(Message);
            string Type = Doc.RootElement.GetProperty("Type").GetString() ?? "";

            switch(Type){
                case "Ready":
                    __SendStatus();
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

                default:
                    WL.Logger.Warn($"Получено неизвестное сообщение от Web, Тип: {Type}");
                    break;
            }
        }catch(Exception e){
            __SendError($"Не удалось обработать сообщение от Web!\nСообщение: {Message}", e);
        }
    }

    // ----------------------------------------------------------------------

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
        try{
            HttpListenerRequest  Request  = Context.Request;
            HttpListenerResponse Response = Context.Response;

            string Path = Request.Url?.AbsolutePath ?? "";

            // /ping не логируем как обычный запрос, чтобы не засорять лог —
            // просто обновляем таймстамп последнего пинга
            if(Path == "/ping"){
                __LastPingTime = DateTime.Now;
            }else{
                __EnqueueLog($"{Request.HttpMethod} {Path}", "Request");
            }

            string ResponseBody;
            int    StatusCode = 200;

            switch(Path){
                case "/ping":
                    ResponseBody = """{"status":"ok","message":"RobloxBridge работает"}""";
                    break;

                case "/pull":{
                    ResponseBody = JsonSerializer.Serialize(new{
                        status = "ok",
                        data = new{
                            Example   = "Это тестовые данные с сервера",
                            Timestamp = DateTime.Now.ToString("HH:mm:ss"),
                            Items     = new[] { "Part1", "Part2", "Script1" }
                        }
                    });
                    break;
                }

                default:
                    StatusCode   = 404;
                    ResponseBody = """{"error":"Not Found"}""";
                    break;
            }

            byte[] Buffer = Encoding.UTF8.GetBytes(ResponseBody);
            Response.StatusCode      = StatusCode;
            Response.ContentType     = "application/json";
            Response.ContentLength64 = Buffer.Length;
            Response.OutputStream.Write(Buffer, 0, Buffer.Length);
            Response.OutputStream.Close();
        }catch(Exception e){
            WL.Logger.Error("Ошибка при обработке запроса.", e);
            __EnqueueLog($"Ошибка при обработке запроса: {e.Message}", "Error");
        }
    }

    // ----------------------------------------------------------------------

    private static DateTime __LastPingBadgeUpdate = DateTime.MinValue;

    private static void __UpdatePingBadgeIfNeeded(){
        if(!__IsRunning){ return; }

        // обновляем бейдж раз в секунду, не чаще
        if((DateTime.Now - __LastPingBadgeUpdate).TotalMilliseconds < 500){ return; }
        __LastPingBadgeUpdate = DateTime.Now;

        if(__LastPingTime == DateTime.MinValue){
            __SendPingUpdate(-1); // ещё ни одного пинга не было
            return;
        }

        long SecondsAgo = (long)(DateTime.Now - __LastPingTime).TotalSeconds;
        __SendPingUpdate(SecondsAgo);
    }

    private static void __SendPingUpdate(long SecondsAgo){
        string JSON = JsonSerializer.Serialize(new{
            Type = "PingUpdate",
            Data = new{ Ms = SecondsAgo }
        });

        __PendingMessages.Enqueue(JSON);
    }

    // ----------------------------------------------------------------------

    private static void __UpdateWindowTitle(){
        __PendingTitle = __IsRunning
            ? $"RobloxBridge [:{__CurrentPort}]"
            : "RobloxBridge [остановлен]";
    }

    private static void __SendStatus(){
        string JSON = JsonSerializer.Serialize(new{
            Type = "ServerStatus",
            Data = new{ Running = __IsRunning, Port = __CurrentPort }
        });

        __PendingMessages.Enqueue(JSON);
    }

    private static void __EnqueueLog(string Text, string Kind){
        string Time = DateTime.Now.ToString("HH:mm:ss");

        string JSON = JsonSerializer.Serialize(new{
            Type = "LogMessage",
            Data = new{ Text, Time, Kind }
        });

        __PendingMessages.Enqueue(JSON);
    }

    private static void __SendError(string Message, Exception e){
        WL.Logger.Error(Message, e);
        try{
            string Details = e.ToString();
            string JSON = JsonSerializer.Serialize(new{ Type = "Error", Data = new{ Title = Message, Details } });
            WebView.PostMessage(JSON);
        }catch{
        }
    }
}