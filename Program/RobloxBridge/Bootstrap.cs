using System.Collections.Concurrent;
using System.Diagnostics;
using System.Net;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
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
            
            Dump.Log = Text => __EnqueueLog(Text, "Info");        // подставь свой Kind
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
            using JsonDocument Doc = JsonDocument.Parse(Message);
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

        return (200, JsonSerializer.Serialize(new{
            status   = "ok",
            project  = P?.Data.Name,
            creating = __Creating,
            place    = Dump.Blocking ? "noDump" : Project.CheckPlace(PlaceId, UniverseId),
            folder   = Folder,
            dump     = Dump.PingInfo()
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

    public static int Port{ get => __D.Port; set => __D.Port = value; }
    public static string? LastProject{ get => __D.LastProject; set => __D.LastProject = value; }
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
            studio = Studio, dumpStudio = Settings.DumpStudio, hash = __Hash, classes = Classes, props = Props
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
                    if(!M.TryGetProperty("Serialization", out JsonElement Ser) || !Ser.TryGetProperty("CanSave", out JsonElement CanSave) || !CanSave.GetBoolean()){ continue; }
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