using System.Collections.Concurrent;
using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
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

    private static volatile bool __Creating   = false; // плагин попросил создать проект, ждём выбор папки
    private static volatile bool __DialogOpen = false;

    private static volatile string? __PendingTitle = null;

    private static DateTime __LastPingTime        = DateTime.MinValue;
    private static DateTime __LastPingBadgeUpdate = DateTime.MinValue;

    private static readonly JsonSerializerOptions __JsonIn = new(){ PropertyNameCaseInsensitive = true };

    [STAThread]
    public static int Main(string[] Args){
        try{
            WL.Core.Start(Args);

            Settings.Load();
            
            Dump.Log = Text => __EnqueueLog(Text, "Info");
            Sync.Log        = __EnqueueLog;
            Sync.Report = D => __Post("SyncResult", D);
            Sync.ProjectDir = () => Project.Current?.Dir;
            Dump.Changed = () => __Post("DumpState", Dump.Snapshot());
            Dump.Open();
            
            Project.Log   = __EnqueueLog;
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
            string Json = Message;
            using(JsonDocument Probe = JsonDocument.Parse(Message)){
                if(Probe.RootElement.ValueKind == JsonValueKind.String){ Json = Probe.RootElement.GetString() ?? ""; }
            }
            using JsonDocument Doc = JsonDocument.Parse(Json);
            string Type = Doc.RootElement.GetProperty("Type").GetString() ?? "";

            switch(Type){
                case "Ready":
                    __TryReopenLastProject();
                    __SendStatus();
                    __SendProject();
                    __UpdateWindowTitle();
                    __EnqueueLog("RobloxBridge готов к запуску.", "Info");
                    __Post("DumpState", Dump.Snapshot());
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

                case "PickDump": __PickDump(); break;
                case "OpenDumpPage": Process.Start(new ProcessStartInfo(Dump.GitHubUrl){ UseShellExecute = true }); break;
                
                case "SyncCmd":{
                    string Cmd = Doc.RootElement.GetProperty("Data").GetProperty("Cmd").GetString() ?? "";
                    if(Cmd != "pull" && Cmd != "preview" && Cmd != "apply" && Cmd != "undo"){ break; }
                    Live.Send(Cmd);
                    __EnqueueLog($"Команда плагину: {Cmd} (дойдёт за ~3 с)", "Info");
                    break;
                }
                
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

    static void __PickDump(){
        Thread T = new Thread(() => {
            string F = FileDialog.Pick("Выберите Full-API-Dump.json");
            if(F != null){ Dump.Choose(F); }   // внутри сработает Changed → DumpState в UI
        });
        T.SetApartmentState(ApartmentState.STA);
        T.IsBackground = true;
        T.Start();
    }
    
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
        if(Project.IsOpen || string.IsNullOrEmpty(Last)){ return; }

        if(Project.TryOpen(Last, out string Error)){
            __EnqueueLog($"Открыт последний проект: {Project.Current!.Data.Name}", "Info");
        }else{
            Settings.LastProject = null;
            __EnqueueLog($"Последний проект недоступен: {Error}", "Error");
        }
    }

    /// Плагин просит создать проект для игры: спрашиваем папку и создаём bridge.json.
    private static void __BeginCreate(PlaceInfo Info){
        if(__Creating || __DialogOpen){ return; }

        __Creating = true;
        __SendProject();
        __EnqueueLog($"Плагин просит создать проект для игры {Info.UniverseId}. Выберите папку.", "Info");

        __PickFolder("Выберите папку для нового проекта (можно создать новую)", Folder => {
            __Creating = false;

            if(Folder == null){
                __EnqueueLog("Создание проекта отменено.", "Info");
            }else if(Project.TryCreate(Folder, Info.UniverseId, out string Error)){
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
        try{
            if(Sync.TryHandle(Context.Request.Url?.AbsolutePath ?? "", Context.Request, Context.Response)){ return; }
        }catch(Exception e){
            WL.Logger.Warn("Sync: не удалось отправить ответ.", e);
            return;
        }

        int    Code;
        string Body;

        try{
            (Code, Body) = __Route(Context.Request);
        }catch(Exception e){
            WL.Logger.Error("Ошибка при обработке запроса.", e);
            __EnqueueLog($"Ошибка при обработке запроса: {e.Message}", "Error");

            Code = 500;
            Body = __Err(e.Message);
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

    private static string __Err(string Message) => JsonSerializer.Serialize(new{ error = Message });
    
    private static PlaceInfo? __ReadInfo(HttpListenerRequest Request){
        using StreamReader Reader = new(Request.InputStream, Encoding.UTF8);
        return JsonSerializer.Deserialize<PlaceInfo>(Reader.ReadToEnd(), __JsonIn);
    }

    private static string __ReadBody(HttpListenerRequest Request){
    using StreamReader Reader = new(Request.InputStream, Encoding.UTF8);
    return Reader.ReadToEnd();
}

private static (int Code, string Body) __Route(HttpListenerRequest Request){
    string Route = Request.Url?.AbsolutePath ?? "";

    // /ping не логируем, чтобы не засорять лог
    if(Route == "/ping"){
        __LastPingTime = DateTime.Now;

        // Версия Studio → проверка дампа (должна выполняться на каждом пинге, даже при блокировке)
        Dump.OnPing(Request.QueryString["studio"]);

        // Подхватываем ручные правки bridge.json (например, переименование папки плейса)
        if(Project.Refresh()){ __SendProject(); }

        long.TryParse(Request.QueryString["place"],    out long PlaceId);
        long.TryParse(Request.QueryString["universe"], out long UniverseId);

        ProjectHandle? P      = Project.Current;
        string?        Folder = null;
        P?.Data.Places.TryGetValue(PlaceId.ToString(), out Folder);

        string PlaceState = Dump.Blocking ? "noDump" : Project.CheckPlace(PlaceId, UniverseId);

        return (200, JsonSerializer.Serialize(new{
            status   = "ok",
            project  = P?.Data.Name,
            creating = __Creating,
            place    = PlaceState,
            folder   = Folder,
            dump     = Dump.PingInfo(),
            cmd      = PlaceState == "ready" ? Live.TakeCommand() : null
        }));
    }

    // Схему и результат проверки не засоряем в лог
    if(Route != "/schema" && Route != "/dump/probe"){
        __EnqueueLog($"{Request.HttpMethod} {Route}", "Request");
    }

    switch(Route){
        case "/schema":{
            string? Schema = Dump.SchemaJson;
            if(Schema == null){ return (503, """{"status":"missing"}"""); }
            return (200, Schema);
        }

        case "/dump/probe":{
            if(Request.HttpMethod != "POST"){ return (405, __Err("Нужен POST")); }

            Dump.OnProbe(__ReadBody(Request));
            return (200, """{"status":"ok"}""");
        }

        case "/project/create":{
            if(Request.HttpMethod != "POST"){ return (405, __Err("Нужен POST")); }
            if(Dump.Blocking){                return (409, __Err(Dump.Message)); }
            if(Project.IsOpen){               return (409, __Err("Проект уже открыт")); }

            PlaceInfo? Info = __ReadInfo(Request);
            if(Info == null || Info.UniverseId == 0){
                return (400, __Err("Плейс не опубликован в Roblox"));
            }

            __BeginCreate(Info);
            return (200, """{"status":"waiting"}""");
        }

        case "/place/add":{
            if(Request.HttpMethod != "POST"){ return (405, __Err("Нужен POST")); }
            if(Dump.Blocking){                return (409, __Err(Dump.Message)); }

            PlaceInfo? Info = __ReadInfo(Request);
            if(Info == null){ return (400, __Err("Пустой запрос")); }

            if(!Project.TryAddPlace(Info, out string Error)){
                __EnqueueLog($"Не удалось добавить плейс: {Error}", "Error");
                return (409, __Err(Error));
            }

            __SendProject();
            return (200, """{"status":"ok"}""");
        }

        default:
            return (404, __Err("Not Found"));
    }
}

public sealed class SyncReply{
    public int Code = 200;
    public object Body = new{ status = "ok" };
    public string Text = "";
    public List<string> Lines = [];
}

public sealed class DiffOp{
    public string Op = "";              // create | set | delete
    public string Path = "";
    public string Name = "";
    public string Class = "";
    public bool Nested;                 // создаётся внутри другого создаваемого объекта
    public int Inner;                   // сколько вложенных создаётся вместе с этим
    public List<BridgeProp> Set = [];
    public List<string> Reset = [];
    public List<BridgeProp> AttrSet = [];
    public List<string> AttrDel = [];
    public List<string>? Tags;
    public List<string> Notes = [];
}

public static class Diff{
    // Что нужно сделать с Current, чтобы получить Wanted.
    public static List<DiffOp> Compute(IEnumerable<BridgeNode> Current, IEnumerable<BridgeNode> Wanted){
        List<DiffOp> Ops = [];
        __Level("", Current, Wanted, Ops);
        return Ops;
    }

    private static string __Esc(string Name){ return Name.Replace("%", "%25").Replace("/", "%2F"); }

    // Сегменты путей: одинаковые братья после сортировки (имя, класс) получают ~2, ~3...
    internal static List<(string Key, BridgeNode Node)> __Keyed(IEnumerable<BridgeNode> Nodes){
        List<(string Key, BridgeNode Node)> Res = [];
        string? Prev = null;
        int Dup = 0;
        foreach(BridgeNode N in Nodes.OrderBy(X => X.Name, StringComparer.Ordinal).ThenBy(X => X.Class, StringComparer.Ordinal)){
            if(N.Name == Prev){ Dup++; }else{ Dup = 1; Prev = N.Name; }
            Res.Add((__Esc(N.Name) + (Dup > 1 ? "~" + Dup : ""), N));
        }
        return Res;
    }

    private static void __Level(string Parent, IEnumerable<BridgeNode> Cur, IEnumerable<BridgeNode> Want, List<DiffOp> Ops){
        Dictionary<string, BridgeNode> C = new(), W = new();
        foreach(var K in __Keyed(Cur)){ C[K.Key] = K.Node; }
        foreach(var K in __Keyed(Want)){ W[K.Key] = K.Node; }

        foreach(string Key in C.Keys.Union(W.Keys).OrderBy(K => K, StringComparer.Ordinal)){
            string At = Parent == "" ? Key : Parent + "/" + Key;
            C.TryGetValue(Key, out BridgeNode? A);
            W.TryGetValue(Key, out BridgeNode? B);
            if(A != null && B != null && A.Class == B.Class){
                DiffOp? Op = __Props(At, A, B);
                if(Op != null){ Ops.Add(Op); }
                __Level(At, A.Children, B.Children, Ops);
            }else{
                if(A != null){ Ops.Add(new DiffOp{ Op = "delete", Path = At, Name = A.Name, Class = A.Class }); }
                if(B != null){ __Create(At, B, false, Ops); }
            }
        }
    }

    private static int __Create(string At, BridgeNode N, bool Nested, List<DiffOp> Ops){
        DiffOp Op = new(){ Op = "create", Path = At, Name = N.Name, Class = N.Class, Nested = Nested,
            Set = [..N.Props], AttrSet = [..N.Attrs], Tags = [..N.Tags] };
        Ops.Add(Op);
        int Total = 0;
        foreach(var K in __Keyed(N.Children)){ Total += 1 + __Create(At + "/" + K.Key, K.Node, true, Ops); }
        Op.Inner = Total;
        return Total;
    }

    private static DiffOp? __Props(string At, BridgeNode A, BridgeNode B){
        DiffOp Op = new(){ Op = "set", Path = At, Name = B.Name, Class = B.Class };
        __Compare(A.Props, B.Props, Op.Set, Op.Reset, Op.Notes, "", true);
        __Compare(A.Attrs, B.Attrs, Op.AttrSet, Op.AttrDel, Op.Notes, "$", false);
        List<string> TA = [..A.Tags.Order(StringComparer.Ordinal)], TB = [..B.Tags.Order(StringComparer.Ordinal)];
        if(!TA.SequenceEqual(TB)){
            Op.Tags = TB;
            Op.Notes.Add($"Теги: [{string.Join(", ", TA)}] → [{string.Join(", ", TB)}]");
        }
        bool Any = Op.Set.Count + Op.Reset.Count + Op.AttrSet.Count + Op.AttrDel.Count > 0 || Op.Tags != null;
        return Any ? Op : null;
    }

    private static void __Compare(List<BridgeProp> Cur, List<BridgeProp> Want, List<BridgeProp> Set, List<string> Reset, List<string> Notes, string Mark, bool IsProps){
        Dictionary<string, BridgeProp> C = new(), W = new();
        foreach(BridgeProp P in Cur){ C[P.Key] = P; }
        foreach(BridgeProp P in Want){ W[P.Key] = P; }
        foreach(BridgeProp P in W.Values.OrderBy(X => X.Key, StringComparer.Ordinal)){
            C.TryGetValue(P.Key, out BridgeProp? Old);
            if(Old != null && __Sig(Old) == __Sig(P)){ continue; }
            Set.Add(P);
            Notes.Add($"{Mark}{P.Key}: {__Show(Old)} → {__Show(P)}");
        }
        foreach(BridgeProp P in C.Values.OrderBy(X => X.Key, StringComparer.Ordinal)){
            if(W.ContainsKey(P.Key)){ continue; }
            if(IsProps && P.Key == "Source"){ continue; }   // отсутствие Source в файле не сбрасывает код скрипта
            Reset.Add(P.Key);
            Notes.Add($"{Mark}{P.Key}: {__Show(P)} → (по умолчанию)");
        }
    }

    private static string __Sig(BridgeProp P){
        return (P.Kind == BridgeKind.Raw ? "r:" : P.Kind == BridgeKind.Str ? "s:" : "f:") + __Norm(P);
    }

    // Числа приводятся к единому виду, чтобы 3.0 и 3 считались одинаковыми
    private static string __Norm(BridgeProp P){
        if(P.Kind == BridgeKind.Str){ return P.Key == "Source" ? P.Value.Replace("\r\n", "\n") : P.Value; }
        if(P.Kind == BridgeKind.Ref){ return P.Value; }
        return string.Join("|", P.Value.Split('|').Select(H => string.Join(",", H.Split(',').Select(T =>
            double.TryParse(T, NumberStyles.Float, CultureInfo.InvariantCulture, out double D) ? Bridge.Num(D) : T.ToUpperInvariant()))));
    }

    private static string __Show(BridgeProp? P){
        if(P == null){ return "(по умолчанию)"; }
        if(P.Key == "Source"){ return P.Value.Split('\n').Length + " строк"; }
        string V = P.Kind == BridgeKind.Str ? "\"" + P.Value.Replace("\n", "\\n") + "\"" : P.Kind == BridgeKind.Ref ? "@\"" + P.Value + "\"" : P.Value;
        return V.Length > 40 ? V[..37] + "..." : V;
    }

    public static (int Created, int Changed, int Deleted) Counts(List<DiffOp> Ops){
        return (Ops.Count(O => O.Op == "create"), Ops.Count(O => O.Op == "set"), Ops.Count(O => O.Op == "delete"));
    }

    // + создастся, ~ изменится, - удалится
    public static List<string> Render(List<DiffOp> Ops, int Max = 300){
        List<string> L = [];
        foreach(DiffOp Op in Ops){
            if(Op.Nested){ continue; }
            if(Op.Op == "create"){ L.Add($"+ {Op.Path} ({Op.Class})" + (Op.Inner > 0 ? $"  +{Op.Inner} вложенных" : "")); }
            else if(Op.Op == "delete"){ L.Add($"- {Op.Path} ({Op.Class})"); }
            else{
                L.Add($"~ {Op.Path}");
                foreach(string N in Op.Notes){ L.Add("      " + N); }
            }
        }
        if(L.Count > Max){ int More = L.Count - Max; L.RemoveRange(Max, More); L.Add($"… ещё строк: {More}"); }
        return L;
    }

    private static string __F(BridgeKind K){ return K == BridgeKind.Str ? "s" : K == BridgeKind.Ref ? "f" : "r"; }

    // Операции для плагина
    public static List<object> Plain(List<DiffOp> Ops){
        return Ops.Select(O => (object)new{
            op = O.Op, path = O.Path, name = O.Name, @class = O.Class,
            set = O.Set.Select(P => new{ k = P.Key, v = P.Value, f = __F(P.Kind) }).ToList(),
            reset = O.Reset,
            attrs = O.AttrSet.Select(P => new{ k = P.Key, v = P.Value, f = __F(P.Kind) }).ToList(),
            adel = O.AttrDel,
            tags = O.Tags
        }).ToList();
    }

    public static string Token(List<object> Plain){
        byte[] Data = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(Plain));
        return Convert.ToHexString(SHA256.HashData(Data))[..16];
    }
}

public static class Pull{
    public static readonly JsonSerializerOptions Json = new(){ WriteIndented = true, IncludeFields = true, PropertyNameCaseInsensitive = true };

    public static int Threshold(PlaceData P){ return P.AutoSplit <= 0 ? int.MaxValue : P.AutoSplit; }
    
    // Состояние Studio из JSON запроса: только сервисы из Services, без Ignore
    public static List<BridgeNode> ReadStudio(JsonElement Root, PlaceData Place, out int Count){
        int N = 0;
        List<BridgeNode> Res = [];
        if(Root.TryGetProperty("services", out JsonElement Svc) && Svc.ValueKind == JsonValueKind.Object){
            foreach(JsonProperty P in Svc.EnumerateObject()){
                if(!Place.Services.Contains(P.Name)){ continue; }
                Res.Add(__Node(P.Value, ref N));
            }
        }
        Count = N;
        return [..Bridge.Filter(Res, Place.Services, Place.Ignore)];
    }

    public static SyncReply Run(string PlaceDir, PlaceData Place, JsonObject Req){
        using JsonDocument Doc = JsonDocument.Parse(Req.ToJsonString());
        JsonElement Root = Doc.RootElement;
        List<BridgeNode> Fresh = ReadStudio(Root, Place, out int Count);
        if(Fresh.Count == 0){ throw new InvalidOperationException("Присланные сервисы не входят в Services (place.json)"); }

        List<string> Prob = [];
        List<BridgeNode> Old = Bridge.ReadScene(PlaceDir, Prob);
        if(Prob.Count > 0){ throw new InvalidOperationException("Файлы сцены не читаются, Pull остановлен: " + string.Join("; ", Prob.Take(5))); }

        HashSet<string> Names = [..Fresh.Select(F => F.Name)];

        // вторая копия сцены с развёрнутыми префабами: только для сравнения со Studio
        string PRoot = Prefabs.ProjectRoot(PlaceDir);
        List<BridgeNode> OldFull = Bridge.ReadScene(PlaceDir, Prob);
        Prefabs.Expand(OldFull, PRoot, Prob);
        if(Prob.Count > 0){ throw new InvalidOperationException("Префабы не читаются, Pull остановлен: " + string.Join("; ", Prob.Take(5))); }

        List<BridgeNode> OldView = [..Bridge.Filter(OldFull, Place.Services, Place.Ignore)];
        // ссылки: и в Studio, и на диске приводим к одному виду (*id или путь)
        List<string> IdWarn = [], Lost = [];
        Refs.Canon(Fresh, Refs.Build(Fresh, IdWarn), Lost, true);
        Refs.Canon(OldView, Refs.Build(OldView, []), [], false);
        List<DiffOp> Ops = Diff.Compute(OldView.Where(O => Names.Contains(O.Name)), Fresh);

        // объекты с _prefab превращаются обратно в одну строку (после того, как diff посчитан)
        List<string> PrefabWarn = [];
        Prefabs.Collapse(Fresh, "", PRoot, PrefabWarn);

        // Сервисы, которых нет в запросе, берём с диска как есть
        List<BridgeNode> All = [..Old.Where(O => !Names.Contains(O.Name)), ..Fresh];
        List<BridgeNode> Result = [..Bridge.Filter(All, Place.Services, Place.Ignore)];

        List<string> Warn = [];
        Bridge.WriteScene(PlaceDir, Result, Place.Splits, Threshold(Place), Warn);
        Bridge.WriteMeta(PlaceDir, Result, Place.Splits);
        __SavePlace(PlaceDir, Place);

        var C = Diff.Counts(Ops);
        string Text = $"Pull: {string.Join(", ", Names)}, объектов {Count}. В файлах: +{C.Created} ~{C.Changed} −{C.Deleted}";
        if(C.Created + C.Changed + C.Deleted == 0){ Text = $"Pull: {string.Join(", ", Names)}, объектов {Count}. Файлы не изменились"; }
        if(Root.TryGetProperty("skipped", out JsonElement Sk) && Sk.ValueKind == JsonValueKind.Object){
            string Types = string.Join(", ", Sk.EnumerateObject().Select(S => $"{S.Name}×{S.Value}"));
            if(Types.Length > 0){ Text += ". Не сохранено по типам: " + Types; }
        }
        if(Warn.Count > 0){ Text += ". Замечаний: " + Warn.Count; }

        List<string> Lines = Diff.Render(Ops);
        Lines.AddRange(PrefabWarn.Select(W => W.StartsWith(" ") ? W : "! " + W));
        Lines.AddRange(IdWarn.Select(W => "! " + W));
        Lines.AddRange(Lost.Take(10).Select(W => "! ссылка не сохранена (цель вне сохраняемых объектов): " + W));
        if(Lost.Count > 10){ Lines.Add($"! … ещё ссылок: {Lost.Count - 10}"); }
        return new SyncReply{ Text = Text, Lines = Lines, Body = new{ status = "ok", text = Text, lines = Lines } };
    }

    // Если у тебя уже есть метод записи place.json - вызови его вместо этого.
    private static void __SavePlace(string PlaceDir, PlaceData Place){
        string Target = Path.Combine(PlaceDir, "place.json");
        string Text = JsonSerializer.Serialize(Place, Json);
        if(!File.Exists(Target) || File.ReadAllText(Target) != Text){ File.WriteAllText(Target, Text); }
    }

    private static BridgeNode __Node(JsonElement E, ref int Count){
        Count++;
        BridgeNode Node = new(){ Class = __Str(E, "c"), Name = __Str(E, "n") };
        Node.Props = __Props(E, "p");
        Node.Attrs = __Props(E, "a");

        List<string> Tags = [];
        if(E.TryGetProperty("g", out JsonElement G) && G.ValueKind == JsonValueKind.Array){
            foreach(JsonElement T in G.EnumerateArray()){ Tags.Add(T.GetString() ?? ""); }
        }
        Tags.Sort(StringComparer.Ordinal);
        Node.Tags = Tags;

        List<BridgeNode> Kids = [];
        if(E.TryGetProperty("k", out JsonElement K) && K.ValueKind == JsonValueKind.Array){
            foreach(JsonElement C in K.EnumerateArray()){ Kids.Add(__Node(C, ref Count)); }
        }
        Node.Children = Kids;
        return Node;
    }

    private static string __Str(JsonElement E, string Key){
        return E.TryGetProperty(Key, out JsonElement V) ? V.GetString() ?? "" : "";
    }

    // Пустой Lua-словарь приходит как [], поэтому проверяем, что это объект.
    private static List<BridgeProp> __Props(JsonElement E, string Key){
        List<BridgeProp> List = [];
        if(!E.TryGetProperty(Key, out JsonElement O) || O.ValueKind != JsonValueKind.Object){ return List; }
        foreach(JsonProperty P in O.EnumerateObject()){
            if(__TryProp(P.Name, P.Value, out BridgeProp Prop)){ List.Add(Prop); }
        }
        List.Sort((A, B) => string.CompareOrdinal(A.Key, B.Key));
        return List;
    }

    private static string __Join(JsonElement X){
        return string.Join(",", X.EnumerateArray().Select(N => Bridge.Num(N.GetDouble())));
    }

    private static bool __TryProp(string Key, JsonElement V, out BridgeProp Prop){
        Prop = default!;
        if(V.ValueKind != JsonValueKind.Object || !V.TryGetProperty("t", out JsonElement T) || !V.TryGetProperty("v", out JsonElement X)){ return false; }
        switch(T.GetString()){
            case "b": Prop = new(Key, X.GetBoolean() ? "true" : "false"); return true;
            case "n": Prop = new(Key, Bridge.Num(X.GetDouble())); return true;
            case "s": case "ct": Prop = new(Key, X.GetString() ?? "", BridgeKind.Str); return true;
            case "e": Prop = new(Key, X.GetString() ?? ""); return true;
            case "ref": Prop = new(Key, X.GetString() ?? "", BridgeKind.Ref); return true;
            case "v2": case "v3": case "v3i": case "u": case "u2": case "nr": case "rc":
                Prop = new(Key, __Join(X)); return true;
            case "ns": case "cs": case "fc": case "ax": case "pp":
                Prop = new(Key, X.GetString() ?? ""); return true;
            case "ft": case "bc":
                Prop = new(Key, X.GetString() ?? "", BridgeKind.Str); return true;
            case "c3":
                Prop = new(Key, $"#{X[0].GetInt32():X2}{X[1].GetInt32():X2}{X[2].GetInt32():X2}"); return true;
            case "cf": {
                double[] N = X.EnumerateArray().Select(E => E.GetDouble()).ToArray();
                string Pos = string.Join(",", N.Take(3).Select(D => Bridge.Num(D)));
                bool Rot = N.Skip(3).Any(D => Math.Abs(D) >= 0.0005);
                Prop = new(Key, Rot ? Pos + "|" + string.Join(",", N.Skip(3).Select(D => Bridge.Num(D))) : Pos);
                return true;
            }
        }
        return false;
    }
}

public static class Push{
    public static SyncReply Run(string PlaceDir, PlaceData Place, JsonObject Req){
        using JsonDocument Doc = JsonDocument.Parse(Req.ToJsonString());
        List<BridgeNode> Studio = Pull.ReadStudio(Doc.RootElement, Place, out int _);

        List<string> Prob = [];
        List<BridgeNode> Scene = Bridge.ReadScene(PlaceDir, Prob);
        Prefabs.Expand(Scene, Prefabs.ProjectRoot(PlaceDir), Prob);
        List<BridgeNode> Disk = [..Bridge.Filter(Scene, Place.Services, Place.Ignore)];
        if(Prob.Count > 0){ throw new InvalidOperationException("Файлы сцены не читаются: " + string.Join("; ", Prob.Take(5))); }
        if(Disk.Count == 0){ throw new InvalidOperationException("В папке плейса нет файлов сцены. Сначала сделай Pull."); }
        
        // ссылки: проверка и единый вид
        List<string> IdProb = [], Lost = [];
        Refs.RefMap DiskMap = Refs.Build(Disk, IdProb);
        Refs.Canon(Disk, DiskMap, Lost, false);
        if(IdProb.Count > 0){ throw new InvalidOperationException("Ссылки: " + string.Join("; ", IdProb.Take(5))); }
        if(Lost.Count > 0){ throw new InvalidOperationException("Ссылки не найдены: " + string.Join("; ", Lost.Take(5)) + (Lost.Count > 5 ? $" …и ещё {Lost.Count - 5}" : "")); }
        Refs.Canon(Studio, Refs.Build(Studio, []), [], true);   // ссылки Studio на объекты вне сохраняемых не сравниваем

        // Трогаем только сервисы, для которых есть файл
        HashSet<string> Names = [..Disk.Select(D => D.Name)];
        List<string> Lines = [];
        foreach(BridgeNode S in Studio.Where(S => !Names.Contains(S.Name))){ Lines.Add($"x {S.Name}: нет файла сцены, не трогаю"); }

        List<DiffOp> Ops = Diff.Compute(Studio.Where(S => Names.Contains(S.Name)), Disk);
        Refs.ToPaths(Ops, DiskMap);
        List<object> Plain = Diff.Plain(Ops);
        string Token = Diff.Token(Plain);
        var C = Diff.Counts(Ops);

        bool Apply = (bool?)Req["apply"] ?? false;
        if(Apply && (string?)Req["token"] != Token){
            return new SyncReply{ Code = 409, Text = "Push отменён: Studio или файлы изменились после предпросмотра",
                Body = new{ error = "Studio или файлы изменились после предпросмотра. Сделай предпросмотр заново.", changed = true } };
        }

        Lines.AddRange(Diff.Render(Ops));
        string Text = Apply
            ? $"Push: применяется +{C.Created} ~{C.Changed} −{C.Deleted}"
            : $"Push, предпросмотр: создастся {C.Created}, изменится {C.Changed}, удалится {C.Deleted}";
        return new SyncReply{
            Text = Text,
            Lines = Apply ? [] : Lines,
            Body = new{ status = "ok", token = Token, counts = new{ created = C.Created, changed = C.Changed, deleted = C.Deleted }, lines = Lines, ops = Plain }
        };
    }
}

public static class Splitter{
    public static SyncReply Run(string PlaceDir, PlaceData Place, string At, bool On){
        if(At == "" || !At.Contains('/')){ throw new InvalidOperationException("Нужен путь объекта внутри сервиса (например Workspace/Door). Сервис целиком выносить нельзя."); }

        List<string> Prob = [];
        List<BridgeNode> Scene = [..Bridge.Filter(Bridge.ReadScene(PlaceDir, Prob), Place.Services, Place.Ignore)];
        if(Prob.Count > 0){ throw new InvalidOperationException("Файлы сцены не читаются: " + string.Join("; ", Prob.Take(5))); }
        if(!__Has(Scene, At.Split('/'), 0)){ throw new InvalidOperationException($"В файлах сцены нет объекта «{At}». Сначала сделай Pull."); }

        string? OldFile = null;
        string NewFile = $"Scene/{At}.bridge";
        if(On){
            if(Place.Splits.TryGetValue(At, out string? Have)){ throw new InvalidOperationException($"«{At}» уже вынесен в {Have}"); }
            Place.Splits[At] = NewFile;
        }else{
            if(!Place.Splits.Remove(At, out OldFile)){ throw new InvalidOperationException($"«{At}» не вынесен, возвращать нечего"); }
        }

        List<string> Warn = [];
        Bridge.WriteScene(PlaceDir, Scene, Place.Splits, Pull.Threshold(Place), Warn);
        Bridge.WriteMeta(PlaceDir, Scene, Place.Splits);

        string Text;
        if(On){
            Text = $"Вынесено: {At} → {NewFile}";
        }else if(Place.Splits.ContainsKey(At)){
            Text = $"«{At}» снова вынесен автоматически (больше {Place.AutoSplit} строк). Поставь \"AutoSplit\": 0 в place.json, чтобы решал только ты.";
        }else{
            Text = $"Возвращено в общий файл: {At}";
            string Full = System.IO.Path.GetFullPath(System.IO.Path.Combine(PlaceDir, OldFile ?? ""));
            if(OldFile != null && Full.StartsWith(System.IO.Path.GetFullPath(PlaceDir)) && File.Exists(Full)){ File.Delete(Full); }
        }
        if(Warn.Count > 0){ Text += ". Замечаний: " + Warn.Count; }

        File.WriteAllText(System.IO.Path.Combine(PlaceDir, "place.json"), JsonSerializer.Serialize(Place, Pull.Json));

        List<string> Lines = ["Вынесено сейчас:"];
        foreach(var S in Place.Splits.OrderBy(X => X.Key, StringComparer.Ordinal)){ Lines.Add($"  {S.Key} → {S.Value}"); }
        if(Place.Splits.Count == 0){ Lines.Add("  (ничего)"); }
        bool Again = !On && Place.Splits.ContainsKey(At);
        return new SyncReply{ Text = Text, Lines = [], Body = new{ status = "ok", text = Text, lines = Lines, warn = Again } };
    }

    // Убирает запись из Splits (фантомную или ненужную). Объект в сцене не трогает.
    public static SyncReply Forget(string PlaceDir, PlaceData Place, string At){
        if(!Place.Splits.TryGetValue(At, out string? Rel)){ throw new InvalidOperationException($"«{At}» нет в списке вынесенных"); }

        string Root   = System.IO.Path.GetFullPath(PlaceDir);
        string Full   = System.IO.Path.GetFullPath(System.IO.Path.Combine(PlaceDir, Rel));
        bool   Exists = File.Exists(Full);

        bool Known   = false;   // удалось ли прочитать сцену без проблем
        bool InScene = false;
        try{
            List<string> Prob = [];
            List<BridgeNode> Scene = [..Bridge.Filter(Bridge.ReadScene(PlaceDir, Prob), Place.Services, Place.Ignore)];
            Known   = Prob.Count == 0;
            InScene = At.Contains('/') && __Has(Scene, At.Split('/'), 0);
        }catch{}

        if(InScene && Exists){
            throw new InvalidOperationException($"«{At}» сейчас лежит в {Rel} и есть в сцене. Нажми «Вернуть», а не ✕.");
        }

        Place.Splits.Remove(At);

        string Text = $"Убрано из вынесенных: {At}";
        if(Exists){
            if(Known && Full.StartsWith(Root)){ File.Delete(Full); Text += $" (файл {Rel} удалён)"; }
            else{ Text += $" (файл {Rel} оставлен: сцену не удалось проверить)"; }
        }

        File.WriteAllText(System.IO.Path.Combine(PlaceDir, "place.json"), JsonSerializer.Serialize(Place, Pull.Json));
        return new SyncReply{ Text = Text };
    }
    
    // Те же правила путей, что в Diff: сортировка (имя, класс), одинаковые братья ~2, ~3
    private static bool __Has(IEnumerable<BridgeNode> Level, string[] Parts, int I){
        string? Prev = null;
        int Dup = 0;
        foreach(BridgeNode N in Level.OrderBy(X => X.Name, StringComparer.Ordinal).ThenBy(X => X.Class, StringComparer.Ordinal)){
            if(N.Name == Prev){ Dup++; }else{ Dup = 1; Prev = N.Name; }
            string Key = N.Name.Replace("%", "%25").Replace("/", "%2F") + (Dup > 1 ? "~" + Dup : "");
            if(Key != Parts[I]){ continue; }
            return I == Parts.Length - 1 || __Has(N.Children, Parts, I + 1);
        }
        return false;
    }
}

public static class Sync{
    public static           Action<string, string>? Log;          // (текст, "Info"/"Error")
    public static           Func<string?>?          ProjectDir;            // папка открытого проекта
    private static readonly object                  __Lock    = new();
    private static          string                  __Session = "";
    private static          JsonObject?             __Acc;
    private static          bool                    __Dbg;
    private static string __Cut(string S){ return S.Length > 300 ? S[..300] + "…" : S; }
    public static Action<JsonNode>? Report;

    // Возвращает true, если путь обработан здесь
    public static bool TryHandle(string Route, HttpListenerRequest Req, HttpListenerResponse Res){
        if(Route != "/config" && Route != "/pull" && Route != "/push" && Route != "/note" && Route != "/split" && Route != "/split/forget" && Route != "/unsplit" && Route != "/settings" && Route != "/report"  && Route != "/terrain/put" && Route != "/terrain/get" && Route != "/terrain/info"){ return false; }
        __Dbg = false;
        try{
            if(Dump.Blocking){ Reply(Res, 409, new{ error = "Нет файла Full-API-Dump: работа заблокирована" }); return true; }
            string Body = "";
            if(Req.HttpMethod == "POST"){
                using StreamReader Reader = new(Req.InputStream, Encoding.UTF8);
                Body = Reader.ReadToEnd();
            }
            
            __Dbg = Route != "/note" && Req.Headers["X-Bridge-Debug"] == "1";
            if(__Dbg){ Log?.Invoke($"[debug] → {Req.HttpMethod} {Req.Url?.PathAndQuery}, тело {Body.Length} байт: {__Cut(Body)}", "Info"); }

            if(Route == "/note"){
                using JsonDocument Doc = JsonDocument.Parse(Body);
                if(Doc.RootElement.TryGetProperty("lines", out JsonElement Ls) && Ls.ValueKind == JsonValueKind.Array){
                    foreach(JsonElement L in Ls.EnumerateArray().Take(80)){ Log?.Invoke(L.GetString() ?? "", "Info"); }
                }
                Reply(Res, 200, new{ status = "ok" });
                return true;
            }
            
            if(Route == "/report"){
                Report?.Invoke(JsonNode.Parse(Body) ?? new JsonObject());
                Reply(Res, 200, new{ status = "ok" });
                return true;
            }

            __Resolve(Req, out string PlaceDir, out PlaceData Place);
            if(Route == "/config"){
                Reply(Res, 200, new{ services = Place.Services, ignore = Place.Ignore, splits = Place.Splits });
                return true;
            }
            
            if(Route == "/terrain/put" || Route == "/terrain/get" || Route == "/terrain/info"){
                lock(__Lock){
                    Reply(Res, 200, __Terrain(Route, Req, Body, PlaceDir));
                }
                return true;
            }
            
            if(Route == "/settings"){
                lock(__Lock){
                    string Text = "";
                    if(Req.HttpMethod == "POST"){
                        Text = __SaveSettings(PlaceDir, Place, Body);
                        Log?.Invoke(Text, "Info");
                    }
                    Reply(Res, 200, __SettingsView(PlaceDir, Place, Text));
                }
                return true;
            }
            
            if(Route == "/split/forget"){
                lock(__Lock){
                    string Target = (string?)JsonNode.Parse(Body)?["path"] ?? "";
                    SyncReply R = Splitter.Forget(PlaceDir, Place, Target);
                    Log?.Invoke(R.Text, "Info");
                    Reply(Res, 200, __SettingsView(PlaceDir, Place, R.Text));
                }
                return true;
            }
            
            if(Route == "/split" || Route == "/unsplit"){
                lock(__Lock){
                    string Target = (string?)JsonNode.Parse(Body)?["path"] ?? "";
                    SyncReply R = Splitter.Run(PlaceDir, Place, Target, Route == "/split");
                    Log?.Invoke(R.Text, "Info");
                    Reply(Res, 200, R.Body);
                }
                return true;
            }

            lock(__Lock){
                JsonObject? Joined = __Join(Req.QueryString["session"] ?? "", __Int(Req, "part", 1), __Int(Req, "parts", 1), Body);
                if(Joined == null){ Reply(Res, 200, new{ status = "partial" }); return true; }

                SyncReply Out = Route == "/pull" ? Pull.Run(PlaceDir, Place, Joined) : Push.Run(PlaceDir, Place, Joined);
                if(Out.Text.Length > 0){ Log?.Invoke(Out.Text, Out.Code == 200 ? "Info" : "Error"); }
                foreach(string L in Out.Lines.Take(60)){ Log?.Invoke(L, "Info"); }
                if(Out.Lines.Count > 60){ Log?.Invoke($"… ещё {Out.Lines.Count - 60} строк (полностью - в окне плагина)", "Info"); }
                Reply(Res, Out.Code, Out.Body);
            }
        }catch(InvalidOperationException E){
            Log?.Invoke(E.Message, "Error");
            Reply(Res, 400, new{ error = E.Message });
        }catch(Exception E){
            Log?.Invoke("Sync: " + E.Message, "Error");
            Reply(Res, 500, new{ error = E.Message });
        }
        return true;
    }

        private const int          __TerrainPart = 300000;   // символов base64 в одном ответе
    private static string      __TSession = "";
    private static StringBuilder? __TBuf;

    // Террейн: сервер только хранит байты, формат знает плагин
    private static object __Terrain(string Route, HttpListenerRequest Req, string Body, string PlaceDir){
        string Target = Path.Combine(PlaceDir, "Terrain.voxels");

        if(Route == "/terrain/info"){
            FileInfo I = new(Target);
            return new{ status = "ok", exists = I.Exists, size = I.Exists ? I.Length : 0,
                        time = I.Exists ? I.LastWriteTime.ToString("yyyy-MM-dd HH:mm") : "" };
        }

        if(Route == "/terrain/get"){
            if(!File.Exists(Target)){ throw new InvalidOperationException("Файла Terrain.voxels нет. Сначала «Террейн: Pull»."); }
            string B64   = Convert.ToBase64String(File.ReadAllBytes(Target));
            int    Parts = Math.Max(1, (B64.Length + __TerrainPart - 1) / __TerrainPart);
            int    Part  = __Int(Req, "part", 1);
            if(Part < 1 || Part > Parts){ throw new InvalidOperationException("Неверная часть файла террейна"); }
            int From = (Part - 1) * __TerrainPart;
            return new{ status = "ok", part = Part, parts = Parts, data = B64.Substring(From, Math.Min(__TerrainPart, B64.Length - From)) };
        }

        // /terrain/put: части base64 копятся, на последней файл записывается
        string Session = Req.QueryString["session"] ?? "";
        int    P       = __Int(Req, "part", 1), Ps = __Int(Req, "parts", 1);
        string Data    = (string?)JsonNode.Parse(Body)?["data"] ?? "";

        if(P <= 1 || Session != __TSession || __TBuf == null){ __TSession = Session; __TBuf = new StringBuilder(); }
        __TBuf.Append(Data);
        if(P < Ps){ return new{ status = "partial" }; }

        byte[] Bytes = Convert.FromBase64String(__TBuf.ToString());
        __TBuf = null;
        string Tmp = Target + ".tmp";
        File.WriteAllBytes(Tmp, Bytes);
        File.Move(Tmp, Target, true);
        Log?.Invoke($"Террейн: записано {Bytes.Length / 1024} КБ → Terrain.voxels", "Info");
        return new{ status = "ok", size = Bytes.Length };
    }
    
    private static List<string> __Lines(JsonNode? N){
        List<string> R = [];
        if(N is JsonArray A){
            foreach(JsonNode? X in A){
                string S = ((string?)X ?? "").Trim();
                if(S.Length > 0 && !R.Contains(S)){ R.Add(S); }
            }
        }
        return R;
    }

    private static string __SaveSettings(string PlaceDir, PlaceData Place, string Body){
        JsonNode? J = JsonNode.Parse(Body);
        List<string> Changes = [];

        if(J?["autoSplit"] != null){
            int V = (int?)J["autoSplit"] ?? -1;
            if(V < 0 || V > 100000){ throw new InvalidOperationException("AutoSplit: нужно целое число от 0"); }
            if(V != Place.AutoSplit){ Changes.Add($"AutoSplit {Place.AutoSplit} → {V}"); Place.AutoSplit = V; }
        }
        if(J?["services"] != null){
            List<string> S = __Lines(J["services"]);
            if(S.Count == 0){ throw new InvalidOperationException("Services не может быть пустым"); }
            if(!S.SequenceEqual(Place.Services)){ Changes.Add($"Services: {Place.Services.Count} → {S.Count}"); Place.Services = S; }
        }
        if(J?["ignore"] != null){
            List<string> I = __Lines(J["ignore"]);
            if(!I.SequenceEqual(Place.Ignore)){ Changes.Add($"Ignore: {Place.Ignore.Count} → {I.Count}"); Place.Ignore = I; }
        }

        if(Changes.Count == 0){ return "Настройки не изменились"; }
        File.WriteAllText(Path.Combine(PlaceDir, "place.json"), JsonSerializer.Serialize(Place, Pull.Json));
        return "Настройки сохранены: " + string.Join("; ", Changes);
    }

    private static object __SettingsView(string PlaceDir, PlaceData Place, string Text){
        var Splits = Place.Splits.OrderBy(S => S.Key, StringComparer.Ordinal).Select(S => {
            string F = Path.GetFullPath(Path.Combine(PlaceDir, S.Value));
            bool Ex = File.Exists(F);
            return new{ path = S.Key, file = S.Value, exists = Ex, lines = Ex ? File.ReadLines(F).Count() : 0 };
        }).ToList();
        return new{
            status = "ok", text = Text, placeId = Place.PlaceId, created = Place.Created,
            autoSplit = Place.AutoSplit, services = Place.Services, ignore = Place.Ignore, splits = Splits
        };
    }
    
    public static void Reply(HttpListenerResponse Res, int Code, object Body){
        byte[] B = JsonSerializer.SerializeToUtf8Bytes(Body);
        if(__Dbg){ Log?.Invoke($"[debug] ← {Code}, {B.Length} байт: {__Cut(Encoding.UTF8.GetString(B, 0, Math.Min(B.Length, 300)))}", "Info"); }
        Res.StatusCode = Code;
        Res.ContentType = "application/json; charset=utf-8";
        Res.ContentLength64 = B.Length;
        Res.OutputStream.Write(B, 0, B.Length);
        Res.OutputStream.Close();
    }

    private static int __Int(HttpListenerRequest Req, string Key, int Def){
        return int.TryParse(Req.QueryString[Key], out int V) ? V : Def;
    }

    // Находит папку плейса по PlaceId из запроса, проверяет игру
    private static void __Resolve(HttpListenerRequest Req, out string PlaceDir, out PlaceData Place){
        string Root = ProjectDir?.Invoke() ?? "";
        string BridgeFile = Path.Combine(Root, "bridge.json");
        if(Root.Length == 0 || !File.Exists(BridgeFile)){ throw new InvalidOperationException("Проект не открыт"); }
        long.TryParse(Req.QueryString["place"], out long PlaceId);
        long.TryParse(Req.QueryString["universe"], out long UniverseId);

        using JsonDocument Doc = JsonDocument.Parse(File.ReadAllText(BridgeFile));
        JsonElement J = Doc.RootElement;
        if(J.TryGetProperty("UniverseId", out JsonElement U) && U.ValueKind == JsonValueKind.Number && U.GetInt64() != 0 && U.GetInt64() != UniverseId){
            throw new InvalidOperationException("Этот плейс из другой игры (UniverseId не совпадает с проектом)");
        }
        string? Folder = null;
        if(J.TryGetProperty("Places", out JsonElement Pl) && Pl.ValueKind == JsonValueKind.Object && Pl.TryGetProperty(PlaceId.ToString(), out JsonElement F)){
            Folder = F.GetString();
        }
        if(string.IsNullOrEmpty(Folder)){ throw new InvalidOperationException("Этот плейс не добавлен в проект"); }
        PlaceDir = Path.Combine(Root, "Places", Folder);
        if(!Directory.Exists(PlaceDir)){ throw new InvalidOperationException("Нет папки плейса: " + PlaceDir); }

        string PlaceFile = Path.Combine(PlaceDir, "place.json");
        Place = File.Exists(PlaceFile) ? JsonSerializer.Deserialize<PlaceData>(File.ReadAllText(PlaceFile), Pull.Json) ?? new PlaceData() : new PlaceData();
    }

    // Склеивает части запроса (плагин режет большие сервисы). null - пока пришли не все части.
    private static JsonObject? __Join(string Session, int Part, int Parts, string Body){
        JsonObject Cur = JsonNode.Parse(Body) as JsonObject ?? throw new InvalidOperationException("Тело запроса не JSON-объект");
        if(Part <= 1 || Session != __Session || __Acc == null){
            __Session = Session;
            __Acc = new JsonObject{ ["services"] = new JsonObject() };
        }
        JsonObject Acc = __Acc;
        JsonObject Svc = (JsonObject)Acc["services"]!;
        if(Cur["services"] is JsonObject In){
            foreach(KeyValuePair<string, JsonNode?> P in In.ToList()){
                if(P.Value == null){ continue; }
                In.Remove(P.Key);
                if(Svc[P.Key] is JsonObject Have && Have["k"] is JsonArray HaveKids && P.Value["k"] is JsonArray NewKids){
                    foreach(JsonNode? Kid in NewKids.ToList()){ NewKids.Remove(Kid); HaveKids.Add(Kid); }
                }else{
                    Svc[P.Key] = P.Value;
                }
            }
        }
        foreach(KeyValuePair<string, JsonNode?> P in Cur.ToList()){
            if(P.Key == "services"){ continue; }
            Cur.Remove(P.Key);
            Acc[P.Key] = P.Value;
        }
        if(Part < Parts){ return null; }
        __Acc = null;
        return Acc;
    }
}

public static class Live{
    private static readonly ConcurrentQueue<string> __Cmds = [];

    public static void Send(string Cmd){ __Cmds.Enqueue(Cmd); }
    public static string? TakeCommand(){ return __Cmds.TryDequeue(out string? C) ? C : null; }
}

// Префабы: шаблон лежит в Prefabs/*.bridge (корень проекта), экземпляр - объект с атрибутом $_prefab="Prefabs/Имя.bridge"
public static class Prefabs{
    public const string Attr = "_prefab";

    private static readonly string[] __PosKeys = ["CFrame", "Pivot", "Position"];
    private static readonly Regex    __Slot    = new(@"\{([A-Za-z0-9_]+)\}");

    public static string ProjectRoot(string PlaceDir){
        return System.IO.Path.GetFullPath(System.IO.Path.Combine(PlaceDir, "..", ".."));
    }

    // ---------------------------------------------------------------- Push: развернуть экземпляры в полные деревья

    public static void Expand(List<BridgeNode> Level, string Root, List<string> Problems){
        for(int I = 0; I < Level.Count; I++){
            BridgeNode  N    = Level[I];
            BridgeProp? Mark = N.Attrs.Find(A => A.Key == Attr);

            if(Mark == null){ Expand(N.Children, Root, Problems); continue; }

            string      Where = N.Origin.Length > 0 ? N.Origin : N.Name;
            BridgeNode? T     = __Load(Root, Mark.Value, Where, Problems);
            if(T != null){ Level[I] = __Apply(N, T, Where, Problems); }
        }
    }

    // ---------------------------------------------------------------- Pull: свернуть обратно в одну строку

    public static void Collapse(List<BridgeNode> Level, string Parent, string Root, List<string> Warn){
        for(int I = 0; I < Level.Count; I++){
            BridgeNode N  = Level[I];
            string     At = Parent.Length == 0 ? N.Name : Parent + "/" + N.Name;

            if(N.Attrs.Any(A => A.Key == Attr)){ Level[I] = __Fold(N, At, Root, Warn); }
            else{                                Collapse(N.Children, At, Root, Warn); }
        }
    }

    private static BridgeNode __Fold(BridgeNode N, string At, string Root, List<string> Warn){
        BridgeProp   Mark = N.Attrs.First(A => A.Key == Attr);
        List<string> Prob = [];

        BridgeNode? T = __Load(Root, Mark.Value, At, Prob);
        if(T == null){ return __Unlink(N, At, Root, Warn, string.Join("; ", Prob)); }
        if(N.Class != T.Class){ return __Unlink(N, At, Root, Warn, $"класс {N.Class} не совпадает с корнем шаблона ({T.Class})"); }

        string?     Key = __PosKey(T);
        BridgeProp? NP  = Key == null ? null : N.Get(Key);

        if(Key != null && NP != null && !__SameRot(NP.Value, T.Get(Key)!.Value)){
            return __Unlink(N, At, Root, Warn, "объект повёрнут, а повороты префабов пока не поддерживаются");
        }

        // как выглядел бы объект строго по шаблону с его параметрами
        BridgeNode Probe = new(){ Class = N.Class, Name = N.Name, Origin = At };
        if(NP != null){ Probe.Props.Add(NP); }
        foreach(BridgeProp A in N.Attrs){ Probe.Attrs.Add(A); }
        BridgeNode E = __Apply(Probe, __Clone(T), At, Prob);
        if(Prob.Count > 0){ return __Unlink(N, At, Root, Warn, string.Join("; ", Prob)); }

        // строка экземпляра: только отличия от шаблона
        BridgeNode Row = new(){ Class = N.Class, Name = N.Name, Origin = At, Tags = [..N.Tags.Where(G => !T.Tags.Contains(G))] };

        if(Key != null && NP != null && !__Same(NP, T.Get(Key)!)){ Row.Props.Add(new BridgeProp(NP.Key, NP.Value, NP.Kind)); }
        if(Key == "CFrame" && NP == null){ Row.Props.Add(new BridgeProp("CFrame", "0,0,0")); }   // нулевая позиция в Studio не присылается

        foreach(BridgeProp P in N.Props){
            if(Array.IndexOf(__PosKeys, P.Key) >= 0){ continue; }

            BridgeProp? EP = E.Get(P.Key);
            if(EP == null || !__Same(P, EP)){ Row.Props.Add(new BridgeProp(P.Key, P.Value, P.Kind)); }
        }

        foreach(BridgeProp A in N.Attrs){
            BridgeProp? TA = T.Attrs.Find(X => X.Key == A.Key);
            if(A.Key == Attr || TA == null || !__Same(A, TA)){ Row.Attrs.Add(new BridgeProp(A.Key, A.Value, A.Kind)); }
        }

        // дети: если в Studio их меняли руками, в файл это не попадёт
        BridgeNode X2 = __Apply(Row, __Clone(T), At, Prob);
        if(Prob.Count > 0){ return __Unlink(N, At, Root, Warn, string.Join("; ", Prob)); }

        List<DiffOp> Ops = Diff.Compute(N.Children, X2.Children);
        if(Ops.Count > 0){
            Warn.Add($"{At}: изменено внутри префаба, в файл не попадёт (чтобы сохранить - «Отвязать»: удали атрибут {Attr} у корня в Studio)");
            foreach(string L in Diff.Render(Ops, 4)){ Warn.Add("   " + L); }
        }

        return Row;
    }

    private static BridgeNode __Unlink(BridgeNode N, string At, string Root, List<string> Warn, string Why){
        N.Attrs.RemoveAll(A => A.Key == Attr);
        Collapse(N.Children, At, Root, Warn);
        Warn.Add($"{At}: {Why}. Записан полным деревом, связь с префабом снята");
        return N;
    }

    // ---------------------------------------------------------------- шаблон

    private static BridgeNode? __Load(string Root, string Rel, string Where, List<string> Problems){
        string? Full = __Safe(Root, Rel);
        if(Full == null){        Problems.Add($"{Where}: недопустимый путь префаба \"{Rel}\""); return null; }
        if(!File.Exists(Full)){  Problems.Add($"{Where}: префаб не найден: {Rel}");             return null; }

        List<string>     Own = [];
        List<BridgeNode> T   = Bridge.Parse(File.ReadAllText(Full), Rel, Own);

        if(Own.Count == 0 && T.Count != 1){ Own.Add($"{Rel}: в шаблоне нужен ровно один корневой объект (сейчас {T.Count})"); }
        if(Own.Count == 0){ __Files(T[0], System.IO.Path.GetDirectoryName(Full)!, Root, Own); }

        if(Own.Count > 0){ Problems.AddRange(Own); return null; }
        return T[0];
    }

    // @src в шаблоне - путь от папки шаблона
    private static void __Files(BridgeNode N, string Dir, string Root, List<string> Own){
        if(N.AtFile != null){ Own.Add($"{N.Origin}: @file в префабе не поддерживается"); N.AtFile = null; }
        if(N.Attrs.Any(A => A.Key == Attr)){ Own.Add($"{N.Origin}: вложенные префабы пока не поддерживаются"); }

        if(N.AtSrc != null){
            string Full = System.IO.Path.GetFullPath(System.IO.Path.Combine(Dir, N.AtSrc));
            string Rel  = System.IO.Path.GetRelativePath(Root, Full);

            if(System.IO.Path.IsPathRooted(N.AtSrc) || Rel.StartsWith("..") || !File.Exists(Full)){
                Own.Add($"{N.Origin}: файл @src не найден или вне проекта: {N.AtSrc}");
            }else{
                N.Props.RemoveAll(X => X.Key == "Source");
                N.Props.Add(new BridgeProp("Source", File.ReadAllText(Full), BridgeKind.Str));
            }
            N.AtSrc = null;
        }

        foreach(BridgeNode C in N.Children){ __Files(C, Dir, Root, Own); }
    }

    // Подставляет параметры, сдвигает позицию, накладывает строку экземпляра. T портится.
    private static BridgeNode __Apply(BridgeNode Row, BridgeNode T, string At, List<string> Problems){
        if(Row.Class != T.Class){ Problems.Add($"{At}: класс {Row.Class} не совпадает с корнем шаблона ({T.Class})"); }
        if(Row.Children.Count > 0){ Problems.Add($"{At}: у экземпляра префаба не может быть вложенных объектов"); }

        // параметры: атрибуты корня шаблона, поверх них - атрибуты строки
        Dictionary<string, BridgeProp> Par = [];
        foreach(BridgeProp A in T.Attrs){   Par[A.Key] = A; }
        foreach(BridgeProp A in Row.Attrs){ Par[A.Key] = A; }
        __Subst(T, Par);

        string? Key = __PosKey(T);

        foreach(BridgeProp P in Row.Props){
            if(Array.IndexOf(__PosKeys, P.Key) >= 0 && P.Key != Key){
                Problems.Add($"{At}: у корня шаблона нет {P.Key} (ожидается {Key ?? "CFrame или Pivot"})");
            }
        }

        BridgeProp? RowPos = Key == null ? null : Row.Get(Key);
        if(Key != null && RowPos != null){
            BridgeProp TP   = T.Get(Key)!;
            double[]?  From = __Pos(TP.Value), To = __Pos(RowPos.Value);

            if(From == null || To == null){
                Problems.Add($"{At}: {Key} должен быть вида x,y,z");
            }else{
                if(!__SameRot(RowPos.Value, TP.Value)){ Problems.Add($"{At}: поворот экземпляра пока не поддерживается (уберите часть после |)"); }

                double[] D = [To[0] - From[0], To[1] - From[1], To[2] - From[2]];
                if(D.Any(V => Math.Abs(V) > 0.0005)){ __Shift(T, D); }
            }
        }

        T.Name   = Row.Name;
        T.Origin = Row.Origin;

        foreach(BridgeProp P in Row.Props){
            if(Array.IndexOf(__PosKeys, P.Key) >= 0){ continue; }
            T.Props.RemoveAll(X => X.Key == P.Key);
            T.Props.Add(new BridgeProp(P.Key, P.Value, P.Kind));
        }
        foreach(BridgeProp A in Row.Attrs){
            T.Attrs.RemoveAll(X => X.Key == A.Key);
            T.Attrs.Add(new BridgeProp(A.Key, A.Value, A.Kind));
        }
        foreach(string G in Row.Tags){ if(!T.Tags.Contains(G)){ T.Tags.Add(G); } }

        return T;
    }

    private static void __Subst(BridgeNode N, Dictionary<string, BridgeProp> Par){
        foreach(BridgeProp P in N.Props){ __SubstProp(P, Par); }
        foreach(BridgeProp P in N.Attrs){ __SubstProp(P, Par); }
        foreach(BridgeNode C in N.Children){ __Subst(C, Par); }
    }

    // "{Имя}" целиком - берём значение и тип параметра; внутри строки - подставляем текстом. Source не трогаем.
    private static void __SubstProp(BridgeProp P, Dictionary<string, BridgeProp> Par){
        if(P.Kind != BridgeKind.Str || P.Key == "Source" || !P.Value.Contains('{')){ return; }

        Match M = __Slot.Match(P.Value);
        if(M.Success && M.Value == P.Value && Par.TryGetValue(M.Groups[1].Value, out BridgeProp? Whole)){
            P.Value = Whole.Value;
            P.Kind  = Whole.Kind;
            return;
        }

        P.Value = __Slot.Replace(P.Value, X => Par.TryGetValue(X.Groups[1].Value, out BridgeProp? V) ? V.Value : X.Value);
    }

    // ---------------------------------------------------------------- позиция

    private static string? __PosKey(BridgeNode T){
        foreach(string K in __PosKeys){
            BridgeProp? P = T.Get(K);
            if(P != null && P.Kind == BridgeKind.Raw && __Pos(P.Value) != null){ return K; }
        }
        return null;
    }

    private static double[]? __Pos(string V){
        string[] H = V.Split('|')[0].Split(',');
        if(H.Length != 3){ return null; }

        double[] R = new double[3];
        for(int I = 0; I < 3; I++){
            if(!double.TryParse(H[I], NumberStyles.Float, CultureInfo.InvariantCulture, out R[I])){ return null; }
        }
        return R;
    }

    private static double[] __Rot(string V){
        int I = V.IndexOf('|');
        if(I < 0){ return []; }
        return V[(I + 1)..].Split(',').Select(S => double.TryParse(S, NumberStyles.Float, CultureInfo.InvariantCulture, out double D) ? D : 0).ToArray();
    }

    private static bool __SameRot(string A, string B){
        double[] X = __Rot(A), Y = __Rot(B);
        int N = Math.Max(X.Length, Y.Length);

        for(int I = 0; I < N; I++){
            double P = I < X.Length ? X[I] : 0, Q = I < Y.Length ? Y[I] : 0;
            if(Math.Abs(P - Q) > 0.01){ return false; }
        }
        return true;
    }

    // Attachment/Bone лежат в локальных координатах - их не двигаем
    private static void __Shift(BridgeNode N, double[] D){
        if(N.Class != "Attachment" && N.Class != "Bone"){
            foreach(string K in __PosKeys){
                BridgeProp? P = N.Get(K);
                if(P == null || P.Kind != BridgeKind.Raw){ continue; }

                double[]? V = __Pos(P.Value);
                if(V == null){ continue; }

                int    Bar  = P.Value.IndexOf('|');
                string Rest = Bar < 0 ? "" : P.Value.Substring(Bar);
                P.Value = Bridge.Num(V[0] + D[0]) + "," + Bridge.Num(V[1] + D[1]) + "," + Bridge.Num(V[2] + D[2]) + Rest;
            }
        }
        foreach(BridgeNode C in N.Children){ __Shift(C, D); }
    }

    // ---------------------------------------------------------------- мелочи

    private static BridgeNode __Clone(BridgeNode N){
        return new BridgeNode{
            Class = N.Class, Name = N.Name, Origin = N.Origin,
            Props = N.Props.Select(P => new BridgeProp(P.Key, P.Value, P.Kind)).ToList(),
            Attrs = N.Attrs.Select(P => new BridgeProp(P.Key, P.Value, P.Kind)).ToList(),
            Tags  = [..N.Tags],
            Children = N.Children.Select(__Clone).ToList()
        };
    }

    private static bool __Same(BridgeProp A, BridgeProp B){
        if(A.Kind != B.Kind){ return false; }
        return A.Kind == BridgeKind.Raw ? __Norm(A.Value) == __Norm(B.Value) : A.Value == B.Value;
    }

    private static string __Norm(string V){
        return string.Join(",", V.Split('|', ',').Select(S =>
            double.TryParse(S, NumberStyles.Float, CultureInfo.InvariantCulture, out double D) ? Bridge.Num(D) : S.ToUpperInvariant()));
    }

    private static string? __Safe(string Root, string Rel){
        if(string.IsNullOrWhiteSpace(Rel) || System.IO.Path.IsPathRooted(Rel)){ return null; }

        string Full   = System.IO.Path.GetFullPath(System.IO.Path.Combine(Root, Rel));
        string Prefix = Root.TrimEnd(System.IO.Path.DirectorySeparatorChar) + System.IO.Path.DirectorySeparatorChar;
        return Full.StartsWith(Prefix, StringComparison.OrdinalIgnoreCase) ? Full : null;
    }
}

// Ссылки между объектами: Part0=@"Workspace/Door/Frame" (путь) или Part0=@"*frame1" (id из $_id="frame1")
public static class Refs{
    public const string IdAttr = "_id";

    public sealed class RefMap{
        public readonly Dictionary<string, BridgeNode> Path = [];   // путь → объект
        public readonly Dictionary<BridgeNode, string> Of   = [];   // объект → путь
        public readonly Dictionary<string, string>     Ids  = [];   // id → путь
    }

    public static RefMap Build(IEnumerable<BridgeNode> Tree, List<string> Problems){
        RefMap X = new();
        __Walk("", Tree, X, Problems);
        return X;
    }

    private static void __Walk(string Parent, IEnumerable<BridgeNode> Level, RefMap X, List<string> Problems){
        foreach(var K in Diff.__Keyed(Level)){
            string At = Parent.Length == 0 ? K.Key : Parent + "/" + K.Key;
            X.Path[At]     = K.Node;
            X.Of[K.Node]   = At;

            BridgeProp? Id = K.Node.Attrs.Find(A => A.Key == IdAttr);
            if(Id != null){
                if(X.Ids.TryGetValue(Id.Value, out string? Have)){ Problems.Add($"id «{Id.Value}» повторяется: {Have} и {At}"); }
                else{ X.Ids[Id.Value] = At; }
            }

            __Walk(At, K.Node.Children, X, Problems);
        }
    }

    public static string? Target(RefMap X, string Value){
        if(Value.StartsWith('*')){ return X.Ids.TryGetValue(Value[1..], out string? At) ? At : null; }
        return X.Path.ContainsKey(Value) ? Value : null;
    }

    // Единый вид: *id, если у цели есть $_id, иначе путь. Ненайденные цели → Missing (и удаляются, если Drop).
    public static void Canon(IEnumerable<BridgeNode> Tree, RefMap X, List<string> Missing, bool Drop){
        foreach(BridgeNode N in Tree){ __Canon(N, X, Missing, Drop); }
    }

    private static void __Canon(BridgeNode N, RefMap X, List<string> Missing, bool Drop){
        for(int I = N.Props.Count - 1; I >= 0; I--){
            BridgeProp P = N.Props[I];
            if(P.Kind != BridgeKind.Ref){ continue; }

            string? At = Target(X, P.Value);
            if(At == null){
                Missing.Add($"{X.Of[N]}.{P.Key} → «{P.Value}»");
                if(Drop){ N.Props.RemoveAt(I); }
                continue;
            }

            BridgeProp? Id = X.Path[At].Attrs.Find(A => A.Key == IdAttr);
            P.Value = Id != null && X.Ids.TryGetValue(Id.Value, out string? Owner) && Owner == At ? "*" + Id.Value : At;
        }
        foreach(BridgeNode C in N.Children){ __Canon(C, X, Missing, Drop); }
    }

    // Для плагина: *id → путь (пути в Disk совпадут со Studio после Push)
    public static void ToPaths(List<DiffOp> Ops, RefMap X){
        foreach(DiffOp Op in Ops){
            for(int I = 0; I < Op.Set.Count; I++){
                BridgeProp P = Op.Set[I];
                if(P.Kind != BridgeKind.Ref || !P.Value.StartsWith('*')){ continue; }
                Op.Set[I] = new BridgeProp(P.Key, X.Ids[P.Value[1..]], BridgeKind.Ref);
            }
        }
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
            Open       = P != null,
            Name       = P?.Data.Name,
            Path       = P?.Dir,
            UniverseId = P?.Data.UniverseId ?? 0,
            Places     = P?.Data.Places ?? new Dictionary<string, string>(),
            Creating   = __Creating
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

// ==========================================================================
// Настройки приложения (порт и последний проект, на каждом ПК свои)

public static class Settings{
    public class Data{
        public int Port{ get; set; } = 4949;
        public string? LastProject{ get; set; } = null;
        public string DumpPath{ get; set; } = "";
        public string DumpHash{ get; set; } = "";
        public string DumpStudio{ get; set; } = "";     // версия Studio, при которой дамп принят
        public string DumpProbe{ get; set; } = "";      // "хеш|релиз" — для чего проверка Studio уже пройдена
        public int DumpProbeMissing{ get; set; } = 0;   // сколько элементов дампа не нашлось в Studio
        public string DumpProbeInfo{ get; set; } = "";
    }

    static Data   __D    = new Data();
    static string __File = Path.Combine(AppContext.BaseDirectory, "robloxbridge.settings.json");

    public static int Port{ get => __D.Port; set{ if(__D.Port != value){ __D.Port = value; Save(); } } }
    public static string? LastProject{ get => __D.LastProject; set{ if(__D.LastProject != value){ __D.LastProject = value; Save(); } } }
    public static string DumpPath{ get => __D.DumpPath; set => __D.DumpPath = value; }
    public static string DumpHash{ get => __D.DumpHash; set => __D.DumpHash = value; }
    public static string DumpStudio{ get => __D.DumpStudio; set => __D.DumpStudio = value; }
    public static string DumpProbe{ get => __D.DumpProbe; set => __D.DumpProbe = value; }
    public static int DumpProbeMissing{ get => __D.DumpProbeMissing; set => __D.DumpProbeMissing = value; }
    public static string DumpProbeInfo{ get => __D.DumpProbeInfo; set => __D.DumpProbeInfo = value; }
    
    public static void Load(){
        try{
            if(File.Exists(__File)){ __D = JsonSerializer.Deserialize<Data>(File.ReadAllText(__File)) ?? new Data(); }
        }catch{ __D = new Data(); }
    }

    public static void Save(){
        try{ File.WriteAllText(__File, JsonSerializer.Serialize(__D, new JsonSerializerOptions{ WriteIndented = true })); }catch{}
    }
}

// ==========================================================================
// Проект: bridge.json (игра) + Places/<папка>/place.json (плейсы)

public sealed record PlaceInfo(long PlaceId, long UniverseId);

public sealed class ProjectData{
    public int    Format     { get; set; } = Project.FormatVersion;
    public string Name       { get; set; } = "";
    public long   UniverseId { get; set; }

    /// PlaceId (строкой) -> имя папки внутри Places/. Имя можно менять руками.
    public Dictionary<string, string> Places { get; set; } = [];
}

public sealed class PlaceData{
    public long   PlaceId { get; set; }
    public string Created { get; set; } = "";

    public List<string> Services { get; set; } = [..Bridge.DefaultServices];
    public List<string> Ignore   { get; set; } = [..Bridge.DefaultIgnore];
    
    public int AutoSplit { get; set; } = 500;   // 0 = автоматический вынос выключен

    /// Путь объекта -> файл .bridge (относительно папки плейса). Заполняется и вручную, и автоматически.
    public Dictionary<string, string> Splits { get; set; } = [];
}

public sealed record ProjectHandle(string Dir, ProjectData Data);

public static class Project{
    public const string MarkerFile    = "bridge.json";
    public const string PlaceFile     = "place.json";
    public const string PlacesDir     = "Places";
    public const int    FormatVersion = 1;

    public static Action<string, string> Log = (_, _) => {};

    public static volatile ProjectHandle? Current = null;
    public static bool IsOpen => Current != null;

    private static readonly object __Lock = new();
    private static DateTime        __Stamp;

    private static readonly JsonSerializerOptions __Json = new(){ WriteIndented = true, PropertyNameCaseInsensitive = true };

    // ----------------------------------------------------------------------

    public static bool TryOpen(string Folder, out string Error){
        Error = "";

        lock(__Lock){
            try{
                string Full = Path.GetFullPath(Folder);

                if(!File.Exists(Path.Combine(Full, MarkerFile))){
                    Error = $"В папке нет {MarkerFile}, это не проект RobloxBridge.\nНовый проект создаётся из плагина в Roblox Studio.";
                    return false;
                }

                ProjectData Data = __Read(Full);

                Current = new ProjectHandle(Full, Data);
                __Stamp = File.GetLastWriteTimeUtc(Path.Combine(Full, MarkerFile));

                __Sync(Current);
                return true;
            }catch(Exception e){
                Error = $"Не удалось прочитать проект: {e.Message}";
                return false;
            }
        }
    }

    public static bool TryCreate(string Folder, long UniverseId, out string Error){
        Error = "";

        lock(__Lock){
            try{
                string Full = Path.GetFullPath(Folder);

                if(!Directory.Exists(Full)){
                    Error = "Папка не существует.";
                    return false;
                }

                if(File.Exists(Path.Combine(Full, MarkerFile))){
                    Error = "В этой папке уже есть проект RobloxBridge.\nОткройте его кнопкой «Открыть проект» в приложении.";
                    return false;
                }

                ProjectData Data = new(){ Name = new DirectoryInfo(Full).Name, UniverseId = UniverseId };

                __Write(Full, Data);
                Current = new ProjectHandle(Full, Data);

                return true;
            }catch(Exception e){
                Error = $"Не удалось создать проект: {e.Message}";
                return false;
            }
        }
    }

    public static bool TryAddPlace(PlaceInfo Info, out string Error){
        Error = "";

        lock(__Lock){
            ProjectHandle? H = Current;

            if(H == null){                                  Error = "Проект не открыт.";                    return false; }
            if(Info.PlaceId == 0){                          Error = "Плейс не опубликован в Roblox.";       return false; }
            if(Info.UniverseId != H.Data.UniverseId){       Error = "Этот плейс относится к другой игре.";  return false; }

            string Id = Info.PlaceId.ToString();

            if(H.Data.Places.ContainsKey(Id)){              Error = "Плейс уже добавлен в проект.";         return false; }

            try{
                ProjectData New = new(){
                    Format     = H.Data.Format,
                    Name       = H.Data.Name,
                    UniverseId = H.Data.UniverseId,
                    Places     = new Dictionary<string, string>(H.Data.Places){ [Id] = Id }
                };

                __Write(H.Dir, New);
                Current = new ProjectHandle(H.Dir, New);

                __Sync(Current);
                Log($"Плейс {Id} добавлен: {PlacesDir}/{Id}", "Info");

                return true;
            }catch(Exception e){
                Error = $"Не удалось добавить плейс: {e.Message}";
                return false;
            }
        }
    }

    public static void Close(){
        Current = null;
    }

    /// Если bridge.json правили руками, перечитывает его и приводит папки в соответствие. true, если что-то изменилось.
    public static bool Refresh(){
        lock(__Lock){
            ProjectHandle? H = Current;
            if(H == null){ return false; }

            string Marker = Path.Combine(H.Dir, MarkerFile);
            DateTime Stamp = File.GetLastWriteTimeUtc(Marker);

            if(Stamp == __Stamp){ return false; }
            __Stamp = Stamp; // ошибка чтения будет показана один раз на каждую правку

            try{
                Current = new ProjectHandle(H.Dir, __Read(H.Dir));

                Log("bridge.json изменён, перечитан.", "Info");
                __Sync(Current);

                return true;
            }catch(Exception e){
                Log($"Не удалось перечитать bridge.json: {e.Message}", "Error");
                return false;
            }
        }
    }

    /// Состояние плейса из Studio относительно открытого проекта.
    public static string CheckPlace(long PlaceId, long UniverseId){
        ProjectHandle? P = Current;

        if(PlaceId == 0 || UniverseId == 0){ return "local"; }
        if(P == null){                       return "noProject"; }
        if(P.Data.UniverseId != UniverseId){ return "otherGame"; }

        return P.Data.Places.ContainsKey(PlaceId.ToString()) ? "ready" : "newPlace";
    }

    // ----------------------------------------------------------------------

    private static ProjectData __Read(string Dir){
        ProjectData? Data = JsonSerializer.Deserialize<ProjectData>(File.ReadAllText(Path.Combine(Dir, MarkerFile)), __Json);

        if(Data == null){
            throw new Exception($"{MarkerFile} пуст или повреждён.");
        }

        if(Data.Format > FormatVersion){
            throw new Exception($"Проект создан более новой версией RobloxBridge (формат {Data.Format}, поддерживается {FormatVersion}).");
        }

        Data.Places ??= [];

        if(string.IsNullOrWhiteSpace(Data.Name)){
            Data.Name = new DirectoryInfo(Dir).Name;
        }

        return Data;
    }

    private static void __Write(string Dir, ProjectData Data){
        string Marker = Path.Combine(Dir, MarkerFile);

        File.WriteAllText(Marker, JsonSerializer.Serialize(Data, __Json));
        __Stamp = File.GetLastWriteTimeUtc(Marker); // собственную запись за ручную правку не считаем
    }

    private static bool __IsValidName(string Name){
        return !string.IsNullOrWhiteSpace(Name)
            && Name == Name.Trim()
            && Name != "." && Name != ".."
            && !Name.EndsWith('.')
            && Name.IndexOfAny(Path.GetInvalidFileNameChars()) < 0;
    }

    /// Приводит папки Places/ в соответствие с bridge.json: создаёт недостающие, переименовывает по новому имени.
    private static void __Sync(ProjectHandle H){
        string PlacesPath = Path.Combine(H.Dir, PlacesDir);
        HashSet<string> Used = new(StringComparer.OrdinalIgnoreCase);

        foreach(var (Id, Name) in H.Data.Places){
            if(!long.TryParse(Id, out long PlaceId)){
                Log($"Places: некорректный PlaceId «{Id}».", "Error");
                continue;
            }

            if(!__IsValidName(Name)){
                Log($"Places: недопустимое имя папки «{Name}» (плейс {Id}).", "Error");
                continue;
            }

            if(!Used.Add(Name)){
                Log($"Places: имя папки «{Name}» используется несколько раз.", "Error");
                continue;
            }

            try{
                string Target = Path.Combine(PlacesPath, Name);

                if(!Directory.Exists(Target)){
                    Directory.CreateDirectory(PlacesPath);

                    string? Old = __FindByPlaceId(PlacesPath, PlaceId);

                    if(Old != null){
                        Directory.Move(Old, Target);
                        Log($"Папка плейса {Id} переименована: {Path.GetFileName(Old)} → {Name}", "Info");
                    }else{
                        Directory.CreateDirectory(Target);
                    }
                }

                string PlaceJson = Path.Combine(Target, PlaceFile);

                if(!File.Exists(PlaceJson)){
                    PlaceData Place = new(){ PlaceId = PlaceId, Created = DateTime.Now.ToString("o") };
                    File.WriteAllText(PlaceJson, JsonSerializer.Serialize(Place, __Json));
                }
            }catch(Exception e){
                Log($"Папка плейса {Id} («{Name}»): {e.Message}", "Error");
            }
        }
    }

    /// Ищет папку плейса по PlaceId из place.json (на случай, если её переименовали).
    private static string? __FindByPlaceId(string PlacesPath, long PlaceId){
        foreach(string Dir in Directory.EnumerateDirectories(PlacesPath)){
            string File_ = Path.Combine(Dir, PlaceFile);
            if(!File.Exists(File_)){ continue; }

            try{
                PlaceData? Place = JsonSerializer.Deserialize<PlaceData>(File.ReadAllText(File_), __Json);
                if(Place?.PlaceId == PlaceId){ return Dir; }
            }catch{
            }
        }

        return null;
    }
}

public static class Dump{
    public const string GitHubUrl = "https://github.com/MaximumADHD/Roblox-Client-Tracker/blob/roblox/Full-API-Dump.json";

    static bool __BlockOnOutdated = false;   // true — при устаревшем дампе тоже блокировать работу
    
    static readonly HashSet<string> __Extra   = ["Size", "Color", "Shape"];   // CanSave=false в дампе, но реально нужны
    const           string          SchemaRev = "2";   // увеличивайте, когда меняете правила построения схемы: плагин перезагрузит схему

    public static string State = "missing";  // missing | broken | checking | ok | outdated | newer
    public static string Message = "Файл дампа API не выбран";
    public static string SchemaJson = null;
    public static string Studio = "";        // версия Studio из последнего пинга
    public static int Classes, Props;
    public static string DiffText = "";
    public static Action<string> Log = Text => {};
    public static Action Changed = () => {};

    static string __Hash = "";
    static string __Stamp = "";
    static int __Cmp = 0;                    // >0 Studio новее дампа, <0 дамп новее Studio
    static string __CacheFile = Path.Combine(AppContext.BaseDirectory, "cache", "schema.json");

    public static bool Blocking => State == "missing" || State == "broken" || (__BlockOnOutdated && State == "outdated");
    public static bool NeedProbe => SchemaJson != null && Studio != "" && __Cmp == 0 && Settings.DumpProbe != __ProbeKey();

    // ---- вызывается при каждом /ping ----
    public static void OnPing(string StudioVersion){
        __CheckFile();
        if(!string.IsNullOrEmpty(StudioVersion) && StudioVersion != Studio){
            Studio = StudioVersion;
            Evaluate();
        }
    }

    public static object PingInfo(){
        return new{
            state = State, message = Message, blocking = Blocking, probe = NeedProbe,
            studio = Studio, dumpStudio = Settings.DumpStudio, hash = __Hash + "." + SchemaRev, classes = Classes, props = Props
        };
    }

    public static object Snapshot(){
        return new{ State, Message, Blocking, Path = Settings.DumpPath, Studio, DumpStudio = Settings.DumpStudio,
                    Hash = __Hash, Classes, Props, Diff = DiffText };
    }

    // ---- пользователь выбрал файл ----
    public static void Choose(string FilePath){
        Settings.DumpPath = FilePath;
        Settings.Save();
        __Stamp = "";
        Open();
    }

    public static void Open(){
        string FilePath = Settings.DumpPath;
        SchemaJson = null; Classes = 0; Props = 0; __Hash = "";
        if(string.IsNullOrEmpty(FilePath)){ __Set("missing", "Файл дампа API не выбран"); Changed(); return; }
        if(!File.Exists(FilePath)){ __Set("missing", "Файл дампа не найден: " + FilePath); Changed(); return; }
        try{
            __Stamp = File.GetLastWriteTimeUtc(FilePath).Ticks.ToString();
            byte[] Bytes = File.ReadAllBytes(FilePath);
            string Hash = Convert.ToHexString(SHA256.HashData(Bytes)).Substring(0, 12);
            string NewSchema = __Build(Bytes, out int ClassCount, out int PropCount);

            if(Hash != Settings.DumpHash){   // новый файл
                string Old = File.Exists(__CacheFile) ? File.ReadAllText(__CacheFile) : null;
                DiffText = Old != null ? __Diff(Old, NewSchema) : "";
                Directory.CreateDirectory(Path.GetDirectoryName(__CacheFile));
                File.WriteAllText(__CacheFile, NewSchema);
                Settings.DumpHash = Hash;
                Settings.DumpStudio = "";    // примем при ближайшем пинге для текущей Studio
                Settings.DumpProbe = "";
                Settings.DumpProbeMissing = 0;
                Settings.DumpProbeInfo = "";
                Settings.Save();
                Log("Дамп загружен (" + Hash + "): классов " + ClassCount + ", свойств " + PropCount);
                if(DiffText != ""){ Log(DiffText); }
            }
            __Hash = Hash; SchemaJson = NewSchema; Classes = ClassCount; Props = PropCount;
            Log("Схема: Size " + (NewSchema.Contains("\"Size\":\"Vector3\"") ? "есть" : "НЕТ")
                               + ", Color " + (NewSchema.Contains("\"Color\":\"Color3\"") ? "есть" : "НЕТ")
                               + ", Shape " + (NewSchema.Contains("\"Shape\":\"Enum:") ? "есть" : "НЕТ"));
            Evaluate();
        }catch(Exception Ex){
            __Set("broken", "Файл не подходит: " + Ex.Message);
        }
        Changed();
    }

    // ---- результат проверки из плагина ----
    public static void OnProbe(string Body){
        try{
            using JsonDocument Doc = JsonDocument.Parse(Body);
            JsonElement R = Doc.RootElement;

            bool Skipped  = R.TryGetProperty("Skipped", out JsonElement Sk) && Sk.GetBoolean();
            int  Missing  = R.TryGetProperty("Missing", out JsonElement Mi) ? Mi.GetInt32() : 0;
            int  Checked  = R.TryGetProperty("Checked", out JsonElement Ch) ? Ch.GetInt32() : 0;
            int  ClassCnt = R.TryGetProperty("Classes", out JsonElement Cl) ? Cl.GetInt32() : 0;

            List<string> Samples = new List<string>();
            if(R.TryGetProperty("Samples", out JsonElement Sm) && Sm.ValueKind == JsonValueKind.Array){
                foreach(JsonElement S in Sm.EnumerateArray()){ Samples.Add(S.GetString() ?? ""); }
            }

            string Info = Skipped ? "Проверка пропущена: прошлая не завершилась (возможно, Studio упала)"
                : Missing == 0 ? "Проверено классов " + ClassCnt + ", свойств " + Checked + ": всё найдено"
                : "Проверено классов " + ClassCnt + ", свойств " + Checked + ": не найдено " + Missing;

            Settings.DumpProbe = __ProbeKey();
            Settings.DumpProbeMissing = Missing;
            Settings.DumpProbeInfo = Info;
            Settings.Save();

            if(Missing > 0){
                Log("Не найдено в Studio: " + string.Join(", ", Samples) + (Missing > Samples.Count ? " …и ещё " + (Missing - Samples.Count) : ""));
            }
            if(Missing > 0 || Skipped){ Log("Проверка дампа: " + Info); }

            Evaluate();
            Changed();
        }catch(Exception Ex){ Log("Ошибка результата проверки дампа: " + Ex.Message); }
    }

    public static void Evaluate(){
        if(SchemaJson == null){ return; }
        if(Studio == ""){ __Set("checking", "Жду версию Studio от плагина"); return; }
        if(Settings.DumpStudio == ""){
            Settings.DumpStudio = Studio;
            Settings.Save();
            Log("Дамп принят для Studio " + Studio);
        }
        int A = __Rel(Settings.DumpStudio), B = __Rel(Studio);
        __Cmp = (A < 0 || B < 0) ? (Settings.DumpStudio == Studio ? 0 : 1) : B.CompareTo(A);

        if(__Cmp > 0){ __Set("outdated", "Roblox обновился (" + A + " → " + B + "). Скачайте свежий дамп и выберите его."); return; }
        if(__Cmp < 0){ __Set("newer", "Дамп новее вашей Studio (" + A + " > " + B + "). Обновите Studio или возьмите дамп старее."); return; }
        if(NeedProbe){ __Set("checking", "Проверяю дамп в Studio…"); return; }
        if(Settings.DumpProbeMissing > 0){
            __Set("newer", "В дампе есть " + Settings.DumpProbeMissing + " элементов, которых нет в Studio — дамп новее Studio.");
            return;
        }
        __Set("ok", "Дамп совместим со Studio (релиз " + B + "). " + Settings.DumpProbeInfo);
    }

    // ---- внутреннее ----
    static void __Set(string NewState, string NewMessage){
        bool Diff = NewState != State || NewMessage != Message;
        State = NewState; Message = NewMessage;
        if(Diff){ Log(NewMessage); Changed(); }
    }

    static void __CheckFile(){
        string FilePath = Settings.DumpPath;
        if(string.IsNullOrEmpty(FilePath)){ return; }
        string Now = File.Exists(FilePath) ? File.GetLastWriteTimeUtc(FilePath).Ticks.ToString() : "gone";
        if(Now != __Stamp){ __Stamp = Now; Open(); }
    }

    static string __ProbeKey(){ return __Hash + "|" + __Rel(Studio); }

    // "0.712.0.7120684" → 712
    static int __Rel(string Version){
        string[] Parts = (Version ?? "").Split('.');
        return Parts.Length >= 2 && int.TryParse(Parts[1], out int N) ? N : -1;
    }

    static HashSet<string> __Tags(JsonElement E){
        HashSet<string> R = new HashSet<string>();
        if(E.TryGetProperty("Tags", out JsonElement T) && T.ValueKind == JsonValueKind.Array){
            foreach(JsonElement X in T.EnumerateArray()){
                if(X.ValueKind == JsonValueKind.String){ R.Add(X.GetString()); }
            }
        }
        return R;
    }

    static bool __SecOk(JsonElement M){
        if(!M.TryGetProperty("Security", out JsonElement S)){ return true; }
        string Read, Write;
        if(S.ValueKind == JsonValueKind.Object){ Read = S.GetProperty("Read").GetString(); Write = S.GetProperty("Write").GetString(); }
        else{ Read = Write = S.GetString(); }
        return (Read == "None" || Read == "PluginSecurity") && (Write == "None" || Write == "PluginSecurity");
    }

    static string __Build(byte[] Bytes, out int ClassCount, out int PropCount){
        using JsonDocument Doc = JsonDocument.Parse(Bytes);
        if(Doc.RootElement.ValueKind != JsonValueKind.Object || !Doc.RootElement.TryGetProperty("Classes", out JsonElement Cls) || Cls.ValueKind != JsonValueKind.Array){
            throw new Exception("нет списка Classes — нужен именно Full-API-Dump.json");
        }
        ClassCount = 0; PropCount = 0;
        using MemoryStream Ms = new MemoryStream();
        using(Utf8JsonWriter W = new Utf8JsonWriter(Ms)){
            W.WriteStartObject();
            W.WriteStartObject("Classes");
            foreach(JsonElement C in Cls.EnumerateArray()){
                HashSet<string> CTags = __Tags(C);
                W.WriteStartObject(C.GetProperty("Name").GetString());
                W.WriteString("Super", C.TryGetProperty("Superclass", out JsonElement Sup) ? Sup.GetString() : "");
                W.WriteBoolean("NotCreatable", CTags.Contains("NotCreatable"));
                W.WriteBoolean("Service", CTags.Contains("Service"));
                W.WriteStartObject("Props");
                foreach(JsonElement M in C.GetProperty("Members").EnumerateArray()){
                    if(M.GetProperty("MemberType").GetString() != "Property"){ continue; }
                    string PName = M.GetProperty("Name").GetString();
                    if(PName == "Parent"){ continue; }
                    HashSet<string> MTags = __Tags(M);
                    if(MTags.Contains("ReadOnly") || MTags.Contains("NotScriptable") || MTags.Contains("Deprecated")){ continue; }
                    bool Saves = M.TryGetProperty("Serialization", out JsonElement Ser) && Ser.TryGetProperty("CanSave", out JsonElement CanSave) && CanSave.GetBoolean();
                    if(!Saves && !__Extra.Contains(PName)){ continue; }
                    if(!__SecOk(M)){ continue; }
                    JsonElement VT = M.GetProperty("ValueType");
                    string Cat = VT.GetProperty("Category").GetString(), VName = VT.GetProperty("Name").GetString();
                    if(VName == "BinaryString"){ continue; }
                    string Type = Cat == "Enum" ? "Enum:" + VName : Cat == "Class" ? "Ref" : VName;
                    W.WriteString(PName, Type);
                    PropCount++;
                }
                W.WriteEndObject();
                W.WriteEndObject();
                ClassCount++;
            }
            W.WriteEndObject();
            W.WriteEndObject();
        }
        if(PropCount == 0){ throw new Exception("в файле нет свойств с Serialization — нужен именно Full-API-Dump.json"); }
        return System.Text.Encoding.UTF8.GetString(Ms.ToArray());
    }

    static HashSet<string> __Keys(string Json){
        HashSet<string> R = new HashSet<string>();
        using JsonDocument D = JsonDocument.Parse(Json);
        foreach(JsonProperty C in D.RootElement.GetProperty("Classes").EnumerateObject()){
            R.Add(C.Name);
            foreach(JsonProperty P in C.Value.GetProperty("Props").EnumerateObject()){ R.Add(C.Name + "." + P.Name + ":" + P.Value.GetString()); }
        }
        return R;
    }

    static string __Diff(string Old, string New){
        HashSet<string> A = __Keys(Old), B = __Keys(New);
        List<string> Add = B.Where(K => !A.Contains(K)).OrderBy(K => K).ToList();
        List<string> Del = A.Where(K => !B.Contains(K)).OrderBy(K => K).ToList();
        if(Add.Count == 0 && Del.Count == 0){ return "Схема не изменилась"; }
        int AddC = Add.Count(K => !K.Contains('.')), DelC = Del.Count(K => !K.Contains('.'));
        string S = "Изменения схемы: классы +" + AddC + " −" + DelC + ", свойства +" + (Add.Count - AddC) + " −" + (Del.Count - DelC);
        if(Add.Count > 0){ S += ". Новое: " + string.Join(", ", Add.Take(6).Select(K => K.Split(':')[0])); }
        if(Del.Count > 0){ S += ". Пропало: " + string.Join(", ", Del.Take(6).Select(K => K.Split(':')[0])); }
        return S;
    }
}

// Нативный диалог «Открыть файл» (без WinForms)
public static class FileDialog{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct OFN{
        public int lStructSize; public IntPtr hwndOwner; public IntPtr hInstance;
        public string lpstrFilter; public string lpstrCustomFilter; public int nMaxCustFilter; public int nFilterIndex;
        public IntPtr lpstrFile; public int nMaxFile; public IntPtr lpstrFileTitle; public int nMaxFileTitle;
        public string lpstrInitialDir; public string lpstrTitle; public int Flags;
        public short nFileOffset; public short nFileExtension; public string lpstrDefExt;
        public IntPtr lCustData; public IntPtr lpfnHook; public string lpTemplateName;
        public IntPtr pvReserved; public int dwReserved; public int FlagsEx;
    }

    [DllImport("comdlg32.dll", CharSet = CharSet.Unicode, EntryPoint = "GetOpenFileNameW")]
    static extern bool GetOpenFileName(ref OFN O);
    [DllImport("user32.dll")]
    static extern IntPtr GetForegroundWindow();

    public static string Pick(string Title){
        const int Size = 1024;
        IntPtr Buf = Marshal.AllocHGlobal(Size * 2);
        try{
            Marshal.WriteInt16(Buf, 0);
            OFN O = new OFN();
            O.lStructSize = Marshal.SizeOf<OFN>();
            O.hwndOwner = GetForegroundWindow();
            O.lpstrFilter = "JSON (*.json)\0*.json\0Все файлы\0*.*\0";
            O.lpstrFile = Buf;
            O.nMaxFile = Size;
            O.lpstrTitle = Title;
            O.Flags = 0x80000 | 0x1000 | 0x800 | 0x8;   // EXPLORER | FILEMUSTEXIST | PATHMUSTEXIST | NOCHANGEDIR
            return GetOpenFileName(ref O) ? Marshal.PtrToStringUni(Buf) : null;
        }finally{ Marshal.FreeHGlobal(Buf); }
    }
}

// ==========================================================================
// Нативный диалог выбора папки (IFileOpenDialog). Вызывать только из STA-потока.

public static class FolderDialog{
    private const uint FOS_PICKFOLDERS     = 0x00000020;
    private const uint FOS_FORCEFILESYSTEM = 0x00000040;
    private const uint FOS_PATHMUSTEXIST   = 0x00000800;
    private const uint SIGDN_FILESYSPATH   = 0x80058000;

    private const uint WS_POPUP         = 0x80000000;
    private const uint WS_EX_TOPMOST    = 0x00000008;
    private const uint WS_EX_TOOLWINDOW = 0x00000080;
    private const int  SW_SHOWNA        = 8;

    private const int HResultCancelled = unchecked((int)0x800704C7);

    /// Возвращает путь к папке или null, если пользователь отменил выбор.
    public static string? Pick(string Title){
        // Невидимое TopMost-окно-владелец, чтобы диалог не терялся за Studio
        IntPtr Owner = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW, "STATIC", "", WS_POPUP, 0, 0, 0, 0, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);

        if(Owner != IntPtr.Zero){
            ShowWindow(Owner, SW_SHOWNA);
            SetForegroundWindow(Owner);
        }

        try{
            IFileOpenDialog Dialog = (IFileOpenDialog)new FileOpenDialogCom();

            try{
                Dialog.GetOptions(out uint Options);
                Dialog.SetOptions(Options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST);
                Dialog.SetTitle(Title);

                int Hr = Dialog.Show(Owner);

                if(Hr == HResultCancelled){ return null; }
                Marshal.ThrowExceptionForHR(Hr);

                Dialog.GetResult(out IShellItem Item);

                try{
                    Item.GetDisplayName(SIGDN_FILESYSPATH, out IntPtr Ptr);

                    try{
                        return Marshal.PtrToStringUni(Ptr);
                    }
                    finally{
                        Marshal.FreeCoTaskMem(Ptr);
                    }
                }
                finally{
                    Marshal.ReleaseComObject(Item);
                }
            }
            finally{
                Marshal.ReleaseComObject(Dialog);
            }
        }
        finally{
            if(Owner != IntPtr.Zero){ DestroyWindow(Owner); }
        }
    }

    [ComImport, Guid("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7")]
    private class FileOpenDialogCom{}

    // Порядок методов важен: это vtable. Ненужные методы объявлены как заглушки.
    [ComImport, Guid("D57C7288-D4AD-4768-BE02-9D969532D960"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IFileOpenDialog{
        [PreserveSig]
        int Show(IntPtr Owner);
        void SetFileTypes(uint Count, IntPtr Types);
        void SetFileTypeIndex(uint Index);
        void GetFileTypeIndex(out uint Index);
        void Advise(IntPtr Events, out uint Cookie);
        void Unadvise(uint Cookie);
        void SetOptions(uint Options);
        void GetOptions(out uint Options);
        void SetDefaultFolder(IShellItem Item);
        void SetFolder(IShellItem Item);
        void GetFolder(out IShellItem Item);
        void GetCurrentSelection(out IShellItem Item);
        void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string Name);
        void GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string Name);
        void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string Title);
        void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string Text);
        void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string Text);
        void GetResult(out IShellItem Item);
        void AddPlace(IShellItem Item, uint Placement);
        void SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string Extension);
        void Close(int Hr);
        void SetClientGuid(ref Guid Guid);
        void ClearClientData();
        void SetFilter(IntPtr Filter);
        void GetResults(out IntPtr Items);
        void GetSelectedItems(out IntPtr Items);
    }

    [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItem{
        void BindToHandler(IntPtr Pbc, ref Guid Bhid, ref Guid Riid, out IntPtr Ppv);
        void GetParent(out IShellItem Item);
        void GetDisplayName(uint Sigdn, out IntPtr Name);
        void GetAttributes(uint Mask, out uint Attributes);
        void Compare(IShellItem Other, uint Hint, out int Order);
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateWindowExW(uint ExStyle, string ClassName, string? WindowName, uint Style, int X, int Y, int Width, int Height, IntPtr Parent, IntPtr Menu, IntPtr Instance, IntPtr Param);

    [DllImport("user32.dll")]
    private static extern bool DestroyWindow(IntPtr Hwnd);
    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr Hwnd, int Cmd);
    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr Hwnd);
}